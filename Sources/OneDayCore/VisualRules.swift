import Foundation

/// 视觉纪律的纯逻辑部分（0.3.0，DESIGN-V4 §14）：断行
/// 整形——可单测、不依赖渲染环境的部分先钉死在这里，
/// 视图层只消费结果。（字重映射 VisualWeight 已于
/// 0.4.0 随 TypeScale 废止删除，审计 §3.1）

/// 减透明回退裁决（0.23.0，三设置检查的代码层落点）：
/// 自制材质面（抽屉底条霜层＝Material＋渐变 mask）在
/// Reduce Transparency 开启时必须落实色分支——渐变
/// mask 的上沿淡出不受系统材质自动增不透明的管辖、
/// 仍会透字。系统玻璃（glassEffect）与系统 Material
/// 本体（无 mask 时）由系统全权回退、不经本裁决。
public enum TransparencyFallback {
    public enum Surface: Equatable {
        /// 系统材质原形态（可叠渐变 mask 等自制加工）
        case material
        /// 实色面（Palette.surface 同档），零透出
        case solid
    }

    public static func surface(reduceTransparency: Bool) -> Surface {
        reduceTransparency ? .solid : .material
    }
}

/// 断行整形（条 8：text-wrap: pretty 等价近似）。SwiftUI
/// 无 pretty 原语，近似法＝尾行孤字防护：把段落最后两
/// 个字形以 WORD JOINER（U+2060）绑定，使排版器不能在
/// 两者之间断行——末行因此至少携带 2 个字形，孤字尾行
/// 被结构性消除；末字为句末标点时绑最后三个（标点不
/// 落单、也不与前字分家）。绑定对非尾行情形无副作用
/// （两字本就同行时排版不变）。
/// 近似边界（如实记）：逐行断点最终由 TextKit 按实际
/// 宽度决定，本整形不估算行宽——它保证的是「无论断点
/// 落在哪，末行不小于 2 字形」，这正是 pretty 要消灭
/// 的孤字情形；行长均衡（balance）不在本近似范围内。
public enum TextShaping {
    /// WORD JOINER：零宽、禁断行
    public static let wordJoiner = "\u{2060}"
    /// 句末/收尾标点：与前字绑定范围扩到三个字形
    private static let closingPunctuation: Set<Character> = [
        "。", "！", "？", "；", "：", "）", "】", "」", "』",
        ".", "!", "?", ";", ":", ")", "]",
    ]

    /// 对单个段落做尾行孤字防护。字形数 ≤2 的段落与含
    /// 换行的多行文本原样返回（调用方按段落逐段施加）
    public static func prettyWrap(_ paragraph: String) -> String {
        guard !paragraph.contains("\n") else { return paragraph }
        let chars = Array(paragraph)
        guard chars.count > 2 else { return paragraph }
        let bindCount = closingPunctuation.contains(chars[chars.count - 1])
            ? 3 : 2
        guard chars.count > bindCount else { return paragraph }
        // WORD JOINER 插在尾部字形「之间」（逐对绑定）：
        // 它禁止两侧断行，把最后 bindCount 个字形锁成
        // 不可断单元——要防的是最后一字被断行孤立，绑
        // 定点必须落在尾部内部而非尾部之前（0.3.0 首轮
        // 单测以此定案：插在尾前时末字仍可被断开）
        //
        // §247（2026-11-14，包 4 追加验收）守卫：插点
        // 若正落在同字定界符对（**／~~／``）的中间，
        // 跳过该处插入——整形在行内解析之前施加，连接
        // 符劈开闭合定界符对会使系统解析器把两半当空
        // 斜体对吞掉、开标记随之失配字面化（用户真机
        // 截图定案：`**标题**` 段尾闭合对被劈后呈现
        // 为字面开标记＋无闭合＋无粗体；证据与回归在
        // StreamingAssemblyFidelityTests）。跳过后该
        // 段的孤字绑定在该点缺位（仅防孤字、纯排版
        // 损），定界符完整性优先
        var result = ""
        for (index, character) in chars.enumerated() {
            if index >= chars.count - bindCount + 1,
               !splitsDelimiterPair(chars, at: index) {
                result += wordJoiner
            }
            result.append(character)
        }
        return result
    }

    /// 插点是否正落在同字定界符对中间（§247 守卫
    /// 的判定面）：index 处字符与前一字符相同且同
    /// 属定界符字（*／~／`）时，连接符插在此处即
    /// 把定界符对劈成两半
    private static func splitsDelimiterPair(
        _ chars: [Character], at index: Int
    ) -> Bool {
        guard index > 0 else { return false }
        let character = chars[index]
        guard character == chars[index - 1] else {
            return false
        }
        return character == "*" || character == "~"
            || character == "`"
    }

    /// 全文版：按空行分段，逐段整形后拼回（段内换行不动）
    public static func prettyWrapDocument(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { prettyWrap($0) }
            .joined(separator: "\n")
    }

    /// run 层整形（§271，第 72 条文本管线根治）：先解
    /// 析、后整形——对行内解析已产出的语义 run 施加
    /// 与 prettyWrap 同口径的尾行孤字绑定（逐行、尾
    /// 2 字形／句末标点尾 3 字形）。连接符只落进普通
    /// 文本 run 的字间，结构上不可能劈开定界符：成
    /// 对定界符已被解析消费、run 文本里不存在待劈
    /// 的对（文本层整形的病根——解析前插符劈开段尾
    /// 闭合 `**`／链接尾 `)`／代码闭合反引号——整类
    /// 消除）。两条豁免（同为真值保真、优先于防孤字）：
    /// - 代码 run 相邻不插：代码文本逐字保真，连接
    ///   符不进代码内容（文本层整形曾把符插进闭合
    ///   反引号内侧、污染代码 run 文本）；
    /// - 数字字之间不插：电话／时间／金额等检测令
    ///   牌（NSDataDetector 口径）被零宽符从中劈开
    ///   即识别失败（gen5 T4 探针实见 `1380013800⁠0`
    ///   与 `13:0⁠0`，同根在此一并收）。
    /// 链接 run 的可见标签文本可插（URL 属性不经文
    /// 本、不受影响）。输入为空／无可绑行时原样返回
    public static func shapeRuns(_ runs: [InlineRun]) -> [InlineRun] {
        let fullText = runs.map(\.text).joined()
        guard fullText.count > 2 else { return runs }
        let chars = Array(fullText)
        // run 起点字符下标（runs 文本拼接即全文）
        var starts: [Int] = []
        starts.reserveCapacity(runs.count)
        var offset = 0
        for run in runs {
            starts.append(offset)
            offset += run.text.count
        }
        func runIndex(containing charIndex: Int) -> Int {
            var result = 0
            for (index, start) in starts.enumerated() {
                if start <= charIndex {
                    result = index
                } else {
                    break
                }
            }
            return result
        }
        // 逐行求插入点（在字符下标 i 之前插入连接符）
        var insertions: Set<Int> = []
        func collectLine(start: Int, end: Int) {
            let count = end - start
            guard count > 2 else { return }
            let bindCount = closingPunctuation.contains(chars[end - 1])
                ? 3 : 2
            guard count > bindCount else { return }
            for i in (end - bindCount + 1)..<end {
                if chars[i - 1].isNumber, chars[i].isNumber {
                    continue
                }
                if runs[runIndex(containing: i - 1)].code {
                    continue
                }
                if runs[runIndex(containing: i)].code {
                    continue
                }
                insertions.insert(i)
            }
        }
        var lineStart = 0
        for i in chars.indices where chars[i] == "\n" {
            collectLine(start: lineStart, end: i)
            lineStart = i + 1
        }
        collectLine(start: lineStart, end: chars.count)
        guard !insertions.isEmpty else { return runs }
        // 回填：插入符归 chars[i] 所在 run、落其本地
        // 偏移（代码相邻点已在收集期豁免，不会落进
        // 代码 run）
        return runs.enumerated().map { index, run in
            var text = ""
            for (local, character) in run.text.enumerated() {
                if insertions.contains(starts[index] + local) {
                    text += wordJoiner
                }
                text.append(character)
            }
            var shaped = run
            shaped.text = text
            return shaped
        }
    }
}
