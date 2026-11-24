import OneDayDesign
import OneDayCore
import SwiftUI

/// 网关状态页（设置·服务器段）：状态详情（/api/status
/// 全字段呈现）＋启停控制。重启自台账 198 收敛 S4 起
/// 只在本页控制组一条执行路径（设置根行独立重启页与
/// 根页执行副本已删、总览无此动作）：二次确认后 POST，
/// 状态靠回读确认不靠回执猜。页题与设置目录题对齐
/// 「网关状态」（S9，此前页题只写「网关」与目录题不一）
/// §470（S5-11 打包改）：用量自设置根页服务器段移
/// 出、收进本页成「用量」组一行（点达走设置栈同一
/// 路由 .usage，UsageDetailView 本体不变）
struct GatewayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var status: ServerStatus?
    @State private var errorMessage: String?
    @State private var pendingAction: String?
    @State private var notice: String?
    @State private var isActing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let status {
                    statusGroup(status)
                    platformsGroup(status)
                    usageGroup
                    actionsGroup(status)
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取网关状态…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("网关状态")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(dialogButton, role: pendingAction == "stop" ? .destructive : nil) {
                // 0.3.2：确认点不再挂触觉，结果点在 perform()
                if let action = pendingAction {
                    Task { await perform(action) }
                }
                pendingAction = nil
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text(dialogMessage)
        }
    }

    private var dialogTitle: String {
        switch pendingAction {
        case "restart": return "重启网关？"
        case "stop": return "停止网关？"
        default: return "启动网关？"
        }
    }

    private var dialogButton: String {
        switch pendingAction {
        case "restart": return "重启"
        case "stop": return "停止"
        default: return "启动"
        }
    }

    private var dialogMessage: String {
        switch pendingAction {
        case "stop":
            return "停止后 Agent 将无法收发消息，直到重新启动。"
        case "restart":
            return "重启期间对话会短暂中断，进行中的任务会被打断。"
        default:
            return "启动后 Agent 恢复收发消息。"
        }
    }

    private func statusGroup(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("状态")
                .padding(.bottom, OneDayMetrics.spacingS)
            // 0.3.7 卡 11：状态升摘要卡（状态大字＋点，
            // 发布日期次级位）；「配置版本」行删
            VStack(spacing: 0) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    StatusDot(color: Palette.stateColor(status.gatewayState))
                    Text(stateWord(status))
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, OneDayMetrics.spacingSM)
                GroupDivider()
                // 键值行走 KeyValueRow（台账 198 收敛
                // S5：裸 LabeledContent 入组卡贴边溢出
                // 的实锤页之一，自此只许共用件）
                KeyValueRow("服务端版本", value: status.version.map { "v\($0)" } ?? "—")
                if let date = status.releaseDate {
                    GroupDivider()
                    KeyValueRow("发布日期", value: date)
                }
            }
            .odGroup()
        }
    }

    private func platformsGroup(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("平台连接")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if status.platforms.isEmpty {
                    Text("暂无平台状态")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                }
                ForEach(
                    Array(status.platforms.keys.sorted().enumerated()),
                    id: \.element
                ) { index, name in
                    if index > 0 {
                        GroupDivider()
                    }
                    if let platform = status.platforms[name] {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            StatusDot(color: Palette.stateColor(platform.state))
                            // 卡 11：平台名/状态词走翻译层
                            Text(ServerLabels.platformName(name))
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text(ServerLabels.platformState(platform.state))
                                .font(.footnote)
                                // 第 85 条（BC-2）：状态词是文字
                                // 位，走 stateTextColor；左侧点
                                // 位仍走 stateColor
                                .foregroundStyle(Palette.stateTextColor(platform.state))
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                    }
                }
            }
            .odGroup()
        }
    }

    /// 用量入口（§470）：行貌与本页控制行同 metrics
    /// （水平边距/行高/按压反馈），披露箭头走共用件
    /// DisclosureChevron（§453 收口后的全仓单源）
    private var usageGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("用量")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.usage) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Text("用量")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        DisclosureChevron(
                            font: .footnote.weight(.semibold)
                        )
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
            }
            .odGroup()
        }
    }

    private func actionsGroup(_ status: ServerStatus) -> some View {
        let running = status.gatewayRunning == true
            || status.gatewayState?.lowercased() == "running"
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("控制")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                actionRow(title: "重启网关", danger: false) {
                    pendingAction = "restart"
                }
                GroupDivider()
                if running {
                    actionRow(title: "停止网关", danger: true) {
                        pendingAction = "stop"
                    }
                } else {
                    actionRow(title: "启动网关", danger: false) {
                        pendingAction = "start"
                    }
                }
            }
            .odGroup()
        }
    }

    private func actionRow(
        title: String, danger: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(danger ? Palette.danger : Palette.ink)
                Spacer()
                if isActing {
                    ProgressView()
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .disabled(isActing)
    }

    private func stateWord(_ status: ServerStatus) -> String {
        ServerLabels.gatewayState(status.gatewayState, running: status.gatewayRunning)
    }


    private func load() async {
        guard let config = appState.config else { return }
        do {
            status = try await appState.client.status(config: config)
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "网关状态没读出来，可能是网络或服务暂时没响应"
        }
    }

    private func perform(_ action: String) async {
        isActing = true
        defer { isActing = false }
        do {
            switch action {
            case "restart":
                try await appState.performAdmin { client, config in
                    try await client.gatewayRestart(config: config)
                }
                notice = "重启指令已发送。"
            case "stop":
                try await appState.performAdmin { client, config in
                    try await client.gatewayStop(config: config)
                }
                notice = "停止指令已发送。"
            default:
                try await appState.performAdmin { client, config in
                    try await client.gatewayStart(config: config)
                }
                notice = "启动指令已发送。"
            }
            // 结果触感（0.3.2 纪律）：指令发送成功 .success
            Haptics.success()
            // 给服务端几秒落地再回读，状态以回读为准
            try? await Task.sleep(for: .seconds(3))
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "操作失败，请稍后再试。"
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
        }
    }
}
