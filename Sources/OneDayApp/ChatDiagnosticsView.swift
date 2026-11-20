import OneDayCore
import OneDayDesign
import SwiftUI

/// 聊天诊断面（台账 189/190，设置支持组直达）
///
/// 本机聊天面探针的唯一可读面：ChatLagProbe 汇
/// 总、量测台积压、ChatDiagTrace 留痕此前只写不
/// 读（探针落 UserDefaults/os 日志、App 内无消
/// 费方，真机回读无门——182/190 两轮诊断共同点
/// 名的制度缺口），本面把四路读数收敛到一处：
/// ①卡顿探针汇总（喂入/托管/解码份额）②量测
/// 台积压（未量测行数与就地量测计数，190 验收
/// 证据）③当前主题气泡解析值（台账 188 证据出
/// 口：单档定版后填充/字色解析成何色，不再靠截
/// 图反推；184 的浓淡键原文读口随 188 删机制一
/// 并撤除——键已无消费方、原文读出只会误导）
/// ④诊断留痕全文（锚四值探针 anchorQuad 在此
/// 回读）。
/// 纪律：只读呈现、不写任何业务状态；读数在出
/// 现/手动刷新时快照，行文等宽小字、可选中复制
struct ChatDiagnosticsView: View {
    @State private var refreshTick = 0

    var body: some View {
        // refreshTick 入依赖：刷新钮自增即整面重读
        let _ = refreshTick
        List {
            Section {
                Text(ChatLagProbe.summaryLine())
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("卡顿探针")
            }
            .listRowBackground(Palette.surface)

            Section {
                Text(ChatNativeRowMeasureDesk.backlogLine())
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("量测台")
            }
            .listRowBackground(Palette.surface)

            Section {
                Text(bubbleLine())
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("气泡解析（台账 188）")
            }
            .listRowBackground(Palette.surface)

            Section {
                let traces = ChatDiagTrace.snapshots
                if traces.isEmpty {
                    Text("暂无留痕")
                        .font(.footnote)
                        .foregroundStyle(
                            Palette.inkSecondary
                        )
                } else {
                    ForEach(
                        Array(traces.reversed().enumerated()),
                        id: \.offset
                    ) { _, line in
                        Text(line)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("诊断留痕")
            }
            .listRowBackground(Palette.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("聊天诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新") { refreshTick += 1 }
            }
        }
    }

    /// 气泡解析读数：当前主题浅/暗两档的填充与
    /// 字色解析值——与 Palette.userBubbleFill 同
    /// 一解析出口（ChatTheme.bubbleFill/bubble-
    /// Text 单档口径）。188 定版前此节兼读浓淡键
    /// 原文，键随机制删除后无原文可读，只剩解析
    /// 值供颜色争议取证
    private func bubbleLine() -> String {
        let theme = Palette.currentChatTheme
        func hex(_ value: UInt32) -> String {
            String(format: "#%06X", value)
        }
        return "主题 \(theme.displayName)（单档定死）"
            + "\n浅 填充 \(hex(theme.bubbleFill(dark: false)))"
            + " 字 \(hex(theme.bubbleText(dark: false)))"
            + "\n暗 填充 \(hex(theme.bubbleFill(dark: true)))"
            + " 字 \(hex(theme.bubbleText(dark: true)))"
    }
}
