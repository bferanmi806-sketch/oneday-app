import OneDayCore
import OneDayDesign
import SwiftUI

/// §247（2026-11-14，换代包 4）流式块级呈现：
/// 流式正文按 Core 切块分两段呈现——已闭合块走
/// 落定同路渲染（MarkdownText，块内容冻结、渲染
/// 结果与落定形态一致），只有未闭合的尾块走逐词
/// 渐显（StreamingText）。蓝图 §1.4 的呈现落法：
/// blur/渐显只作用于尾块新增词元，TokenFlow 的
/// 全文 arrange 就此退役（组件本身留给尾块尺
/// 度）；块闭合的那一拍，该块由尾块呈现切换为
/// 前缀渲染——切换点与产物冻结同点（同一块切分
/// 事实），落定不过是尾块也闭合的终态，故落定
/// 前后呈现同构、无整树换装。
///
/// 2026-11-20 卡顿修复包改逐块沉淀（全面对比报
/// 告 chat-lag-full-comparison-20261120 §3 处
/// 方）：旧形态把闭合前缀拼成一整串塞进单个
/// MarkdownText——每闭合一块，前缀串变长、整段
/// 重建＋其内单 UITextView 全文重排，成本随已
/// 生成长度线性涨。改后闭合块逐块成 Markdown-
/// Text、以块序为 SwiftUI 身份：块内容冻结→其
/// 输入串不变→解析备忘/属性串缓存恒命中、视图
/// 不重排；每拍新增劳动只剩新闭合的那一块与尾
/// 块。高度侧同日改逐块累加（合成器 liveText-
/// Height），两侧同构。
///
/// 段距两级口径（与落定整段呈现逐值一致、不产
/// 生落定跳变）：装配器把连续散文块（段落／标
/// 题／列表）并成一个 prose 段、段内段距走
/// paragraphSpacing；段界与其余相邻走 spacing-
/// SM；闭合前缀末块与尾块的衔接同走两级口径
/// （同属可并段集＝paragraphSpacing，否则
/// spacingSM——旧「恒 spacingSM」口径在散文
/// 尾块落定时涨 4pt，台账 185 于 2026-11-20
/// 修正）。逐块呈现
/// 以 VStack 零距＋逐块底衬补出同一间隙序列
struct StreamingBlockText: View {
    let text: String

    var body: some View {
        let blocks = StreamingBlockSegmenter.blocks(
            for: text
        )
        let parts = Self.closedParts(for: text)
        let tail = StreamingBlockSegmenter.tailSource(
            of: blocks
        )
        // 末块→尾块衔接口径须知尾块类别（gapAfter
        // 两级口径，台账 185）；空尾无衔接、传 nil
        let tailKind = tail.isEmpty
            ? nil
            : blocks.last(where: { $0.isTail })?.kind
        VStack(alignment: .leading, spacing: 0) {
            ForEach(
                Array(parts.enumerated()),
                id: \.element.block.index
            ) { pair in
                MarkdownText(pair.element.source)
                    .padding(
                        .bottom,
                        Self.gapAfter(
                            index: pair.offset, parts: parts,
                            tailKind: tailKind
                        )
                    )
            }
            StreamingText(tail)
        }
    }

    /// 闭合块分解（呈现与量测共用单点）：逐块规
    /// 范源（空源块剔除）＋块本体。块一经闭合其
    /// 源即冻结——尾块生长、新块闭合都不改已闭
    /// 合块的源（沉淀断言的落点）
    static func closedParts(
        for text: String
    ) -> [(block: StreamingBlock, source: String)] {
        StreamingBlockSegmenter.blocks(for: text).compactMap { block in
            guard !block.isTail else { return nil }
            let source = StreamingBlockSegmenter
                .closedPrefix(of: [block])
            return source.isEmpty ? nil : (block: block, source: source)
        }
    }

    /// 闭合块逐块源（沉淀断言用）
    static func closedBlockSources(for text: String) -> [String] {
        closedParts(for: text).map(\.source)
    }

    /// 块后间隙：散文相邻（两侧都可并段）＝
    /// paragraphSpacing；其余相邻＝spacingSM。
    /// 末闭合块（其后是尾块）同走此两级口径：
    /// 尾块与末块同属可并段集时，落定装配器会
    /// 把两者并入同一 prose 段、界距走 paragrap-
    /// hSpacing——衔接先按 spacingSM 取值会在
    /// 落定瞬间涨 4pt（16−12，台账 185 残差、
    /// 2026-11-20 实测三样本恒差 4.0）；tailKind
    /// 为 nil（调用方不知尾块类别）时保留旧
    /// spacingSM 兜底
    static func gapAfter(
        index: Int,
        parts: [(block: StreamingBlock, source: String)],
        tailKind: StreamingBlockKind? = nil
    ) -> CGFloat {
        guard index < parts.count - 1 else {
            if let tailKind,
               isProseMergeable(parts[index].block.kind),
               isProseMergeable(tailKind) {
                return OneDayMetrics.paragraphSpacing
            }
            return OneDayMetrics.spacingSM
        }
        let here = parts[index].block.kind
        let next = parts[index + 1].block.kind
        return isProseMergeable(here) && isProseMergeable(next)
            ? OneDayMetrics.paragraphSpacing
            : OneDayMetrics.spacingSM
    }

    /// 装配器并段集（MarkdownMessageAssembler 的
    /// prose 累积口径）：段落／标题／列表进同一
    /// 散文段；引用／代码／表格／任务列表／分隔
    /// 各自成段
    static func isProseMergeable(_ kind: StreamingBlockKind) -> Bool {
        kind == .paragraph || kind == .heading || kind == .list
    }
}
