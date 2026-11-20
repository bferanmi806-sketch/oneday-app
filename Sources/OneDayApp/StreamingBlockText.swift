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
/// 段间口径：外层段距取 spacingSM，与 Mark-
/// downText 内部段距同值——闭合前缀的末段与尾
/// 块的衔接距和落定后同一位置的段距一致，落定
/// 帧不因呈现拼合方式产生段距跳变
///
/// （全面对
/// 比报告 chat-lag-full-comparison-20261120 §3
/// 处方）：旧形态把闭合前缀拼成一整串塞进单个
/// MarkdownText——每闭合一块，前缀串变长、整段
/// 重建＋其内单 UITextView 全文重排，成本随已
/// 生成长度线性涨。改后闭合块逐块成 Markdown-
/// Text、以块序为 SwiftUI 身份：块内容冻结→其
/// 输入串不变→解析备忘/属性串缓存恒命中、视图
/// 不重排；每拍新增劳动只剩新闭合的那一块与尾
/// 块。高度侧同日改逐块累加（合成器 liveText-
/// Height），两侧同构、段距同值不跳变
struct StreamingBlockText: View {
let text: String

/// 闭合块的呈现源序列（逐块、与块序同序）：
/// 追加式增长下前缀恒定——尾块生长/新块闭合
/// 都不改已闭合块的源（沉淀断言的落点）
static func closedBlockSources(
for text: String
) -> [String] {
StreamingBlockSegmenter.blocks(for: text)
.filter {!$0.isTail}
.map {
StreamingBlockSegmenter
.closedPrefix(of: [$0])
}
.filter {!$0.isEmpty}
}

var body: some View {
let blocks = StreamingBlockSegmenter.blocks(
for: text
)
let closed = blocks.filter {!$0.isTail}
let tail = StreamingBlockSegmenter
.tailSource(of: blocks)
VStack(
alignment:.leading,
spacing: OneDayMetrics.spacingSM
) {
ForEach(closed, id: \.index) { block in
MarkdownText(
StreamingBlockSegmenter
.closedPrefix(of: [block])
)
}
StreamingText(tail)
}
}
}
