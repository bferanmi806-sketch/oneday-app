import OneDayDesign
import SwiftUI

/// 流式打字渐显（0.3.0，DESIGN-V4 §14 条 4）：流式回复
/// 的新字以 blur 6px 起、120ms 化开，同批增量内的字
/// 依次错开 30ms 入场；已入场字符静止不重演。落盘后
/// 的成品消息改走 MarkdownText 静态渲染，本组件只活
/// 在流式进行中。
///
/// 词元口径：CJK 逐字成元（任意位置可断行）、拉丁字母
/// 按词成元（词不拆断）；词元以 TokenFlow 换行布局排
/// 布，流式光标作为末尾词元同流排布。
///
/// 动效纪律（0.3.2，DESIGN-V4 §17）：入场动画统一走
/// MotionTokens.streamIn＋resolved 出口（Reduce Motion
/// 开启时整段直显、无 stagger）；stagger 批级封顶——
/// 单批增量 >8 词元时步进压缩至总时长 240ms 且退化为
/// 纯 opacity（无 blur），断线重连的全量补发不被动画
/// 扣留（审查 M-2/E-4）。
///
/// 动画作用域（第 82 条，2026-11-15）：入场动画只许
/// 动 blur＋opacity，词元位置永不进动画事务——动画
/// 收在 StreamingTokenView 内部视觉层，被 TokenFlow
/// 落位的视图自身不挂动画。定因与帧证据见
/// gen4-stream-overlap-diagnosis-20261115.md（旧形态
/// 动画挂在被落位视图整体上，换行边界词元的原点翻
/// 动被插值成纵向滑移＝真机叠字）。
struct StreamingText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tokens: [String] = []
    @State private var visible: Set<Int> = []
    /// 大批量增量中的词元：退化为纯 opacity 入场（无 blur）
    @State private var noBlur: Set<Int> = []

    var body: some View {
        TokenFlow(spacing: OneDayMetrics.tokenFlowSpacing) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                // 第 82 条：被 TokenFlow 落位的是
                // StreamingTokenView——它自身不挂动画，
                // 入场动画收在其内部视觉层（见该类型注）
                StreamingTokenView(
                    token: token,
                    shown: visible.contains(index),
                    flat: noBlur.contains(index)
                )
            }
            StreamingCaret()
                .padding(.leading, OneDayMetrics.spacingMicro)
        }
        // 0.43.0（A11Y-V3）：流式呈现对 VO 合并为整段
        // 文本元素——词元是视觉动画单位、逐个可达只
        // 会把一句话的朗读切碎；标签直读全文（text
        // 状态），流式中焦点停留时按系统节奏刷新，
        // 完成播报另有 S6 通道。视觉零变化
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onChange(of: text, initial: true) { _, newText in
            let newTokens = Self.tokenize(newText)
            let oldCount = tokens.count
            tokens = newTokens
            let batch = newTokens.count - oldCount
            guard batch > 0 else { return }
            if batch > 8 {
                noBlur.formUnion(oldCount..<newTokens.count)
            }
            // Reduce Motion：新词元整段直显，不排 stagger
            if reduceMotion {
                visible.formUnion(oldCount..<newTokens.count)
                return
            }
            // 旧词元保持已入场；新词元按批内序号错开入场，
            // 总时长封顶 240ms（大批量时步进等比压缩）
            let step = batch > 8 ? 0.24 / Double(batch) : 0.03
            for index in oldCount..<newTokens.count {
                let delay = min(Double(index - oldCount) * step, 0.24)
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    visible.insert(index)
                }
            }
        }
    }

    /// 分词：CJK/标点逐字，拉丁与数字按连续段成词，
    /// 空白独立成元（保留断行点）
    static func tokenize(_ text: String) -> [String] {
        var result: [String] = []
        var latinRun = ""
        func flush() {
            if !latinRun.isEmpty {
                result.append(latinRun)
                latinRun = ""
            }
        }
        for character in text {
            if let scalar = character.unicodeScalars.first,
               CharacterSet.alphanumerics.contains(scalar),
               character.isASCII {
                latinRun.append(character)
            } else {
                flush()
                result.append(String(character))
            }
        }
        flush()
        return result
    }
}

/// 词元视觉层（第 82 条）：TokenFlow 落位的就是本视
/// 图，它自身不挂任何动画修饰——父 Layout 赋予的
/// origin 变更永远直跳、不进动画事务。入场动画
/// （blur＋opacity）只挂在 body 内的 Text 上：动画
/// 域仅限本视图内部的视觉属性，够不到外层落位。
///
/// 病根回溯（gen4-stream-overlap-diagnosis-20261115）：
/// 旧形态把 .animation(streamIn, value:) 直接挂在被
/// 落位的词元视图上——该修饰的语义是「值变时本视
/// 图一切可动画属性一并过渡」，TokenFlow 每拍重排
/// 时换行边界词元的原点翻动被 120ms easeOut 插值
/// 成纵向滑移、压住本行字形（真机叠字）。落定字形
/// 与行中追加字的现有观感（只有浓淡、无位移）由本
/// 分层原样保持：shown/flat 语义与旧链逐项同值。
private struct StreamingTokenView: View {
    let token: String
    /// 已入场（visible 含本词元序号）
    let shown: Bool
    /// 大批量退化档：纯 opacity 入场（无 blur）
    let flat: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(token)
            // 0.4.4（§29）：流式行与落盘正文同
            // 口径——16pt（.callout 语义载体）＋
            // bodyInk 炭灰；0.3.8 第 29 条的
            // 17 regular 角色随正文基准一并改
            .font(.callout)
            .foregroundStyle(Palette.bodyInk)
            .blur(radius: shown || flat ? 0 : 6)
            .opacity(shown ? 1 : 0)
            .animation(
                MotionTokens.resolved(
                    MotionTokens.streamIn,
                    reduceMotion: reduceMotion
                ),
                value: shown
            )
    }
}

/// 词元换行布局：左到右排布、满行换行，行距可定。
/// sizeThatFits 与 placeSubviews 共用同一排布算法，
/// 尺寸与落位不会打架
///
/// 第 82 条：排布经 TokenFlowArranger 缓存——贪心逐
/// 行落位下，词元 i 的原点只取决于它之前的词元尺
/// 寸与行宽，追加永不翻动前缀原点；缓存按（行宽＋
/// 间距＋尺寸序列）记账，纯追加只续排尾部。失效口
/// 径：行宽变、或已排前缀任一词元尺寸变（分词重组、
/// 字号环境变都会改尺寸）→ 自首个不一致处起重排，
/// 不给陈旧排版（与流式卡顿定因的「全量重排」同账）
struct TokenFlow: Layout {
    var spacing: CGFloat = OneDayMetrics.tokenFlowSpacing

    func makeCache(subviews: Subviews) -> TokenFlowArranger {
        TokenFlowArranger()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TokenFlowArranger
    ) -> CGSize {
        cache.arrange(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: proposal.width ?? .greatestFiniteMagnitude,
            spacing: spacing
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TokenFlowArranger
    ) {
        let result = cache.arrange(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: bounds.width,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            let origin = result.origins[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + origin.x,
                    y: bounds.minY + origin.y
                ),
                proposal: .unspecified
            )
        }
    }
}

/// TokenFlow 排版引擎（纯值形态，可单测）：贪心逐行
/// 落位＋前缀缓存。缓存键＝（行宽，间距，已排尺寸序
/// 列）；命中形态有二——全等（整表复用）与共享前缀
/// （自首个尺寸不一致处、或纯追加的尾部续排，前缀
/// 原点逐点复用）。行宽/间距变、或前缀尺寸变 → 对
/// 应位置起重排（lastResumeIndex 记本次续排起点：
/// 0＝自首词元重排）。排版结果只由尺寸序列决定，
/// 与子视图身份无关——末尾光标这类「位置会移、尺
/// 寸恒定」的子视图在序列里只是一个普通元素，前缀
/// 比对在它处自然分界、词元前缀照常复用
struct TokenFlowArranger {
    /// 落完一个词元后的游标（续排的衔接状态）
    private struct Cursor: Equatable {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
    }

    private var cachedWidth: CGFloat?
    private var cachedSpacing: CGFloat = 0
    private var cachedSizes: [CGSize] = []
    private var cachedOrigins: [CGPoint] = []
    private var cursors: [Cursor] = []
    /// 最近一次 arrange 的续排起点（诊断/测试读数）
    private(set) var lastResumeIndex = 0

    mutating func arrange(
        sizes: [CGSize], width: CGFloat, spacing: CGFloat
    ) -> (size: CGSize, origins: [CGPoint]) {
        var resume = 0
        var cursor = Cursor()
        var origins: [CGPoint] = []
        if cachedWidth == width, cachedSpacing == spacing {
            let limit = min(cachedSizes.count, sizes.count)
            var prefix = 0
            while prefix < limit,
                  cachedSizes[prefix] == sizes[prefix] {
                prefix += 1
            }
            if prefix > 0 {
                resume = prefix
                origins = Array(cachedOrigins.prefix(prefix))
                cursor = cursors[prefix - 1]
            }
        }
        var nextCursors = Array(cursors.prefix(resume))
        for index in resume..<sizes.count {
            let size = sizes[index]
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += cursor.lineHeight + spacing
                cursor.lineHeight = 0
            }
            origins.append(CGPoint(x: cursor.x, y: cursor.y))
            cursor.lineHeight = max(cursor.lineHeight, size.height)
            cursor.x += size.width
            cursor.maxX = max(cursor.maxX, cursor.x)
            nextCursors.append(cursor)
        }
        let total = CGSize(
            width: cursor.maxX,
            height: cursor.y + cursor.lineHeight
        )
        cachedWidth = width
        cachedSpacing = spacing
        cachedSizes = sizes
        cachedOrigins = origins
        cursors = nextCursors
        lastResumeIndex = resume
        return (total, origins)
    }
}

/// 流式光标：文末的 accent 小块，0.9 秒阶梯闪烁——它是
/// 「正在生成」的活信号，也是聊天页的签名细节。Reduce
/// Motion 时静止。（0.3.0 自 ChatView 移入，与渐显组件
/// 同文件。）
struct StreamingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.45)) { context in
            let on = reduceMotion
                || Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.primary)
                .frame(width: 7, height: 16)
                .opacity(on ? 1 : 0.15)
        }
        .accessibilityHidden(true)
    }
}
