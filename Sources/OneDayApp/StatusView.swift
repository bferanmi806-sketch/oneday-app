import OneDayCore
import OneDayDesign
import SwiftUI

/// 「状态」屏（0.2.1 新增，仿 Muse 头像/状态屏）：入口在
/// 设置根「状态」行（服务与工作区组工作区段，根行副题标
/// 「汇总」；旧总览入口已随总览撤页退役，本文件头原写
/// 「入口在总览状态头」是陈旧口径，台账 198 收敛 C2 改
/// 实）。顶部智能体身份（名＋当前状态一句话），下分三段：
/// 活动（最近会话＋近期日志事件流）／定时（接下来运行摘
/// 录，只读——数据走共享 CronStore、行走共用
/// CronOverviewRow，全量管理点「全部定时任务」直达正主
/// 页，台账 198 收敛 C3）／系统（资源与版本，来自
/// /api/system/stats ＋ /api/status）。身份头网关状态读
/// 共享枢纽 store 的同一份快照（C4），本页不自拉。
/// 浏览器任务与审核记录两格：openapi 335 路径中无浏览器任务
/// 列表接口，「审核」只有 git 代码审查与安全审计触发端点、
/// 无记录列表接口——两格不做，不用假数据填充（施工前核查
/// 结论，见 0.2.1 汇报）。
struct StatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    var onOpenSession: (String) -> Void = { _ in }

    @State private var segment = 0
    /// 体检留痕（H1-a）：系统段尾次入口读同一份摘要
    @State private var healthSummaryStore = HealthSummaryStore.shared
    @State private var sessions: [ServerSession] = []
    @State private var logLines: [String] = []
    @State private var stats: SystemStats?

    /// 身份头网关状态（台账 198 收敛 C4）：读共享枢
    /// 纽 store 的 serverStatus——同一份状态全 App 只
    /// 此一处取数（枢纽 store 持有），本页 load() 只
    /// 经店内回读口触发刷新、不自拉一份
    private var status: ServerStatus? {
        appState.sharedHubStore().serverStatus
    }

    /// 定时摘录数据（台账 198 收敛 C3＋普查 R4）：
    /// 共享 CronStore 的同一份名单，本页不自拉
    private var cronStore: CronStore { appState.sharedCronStore() }
    private var cronJobs: [CronJob] { cronStore.jobs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identityHead
                Picker("状态分段", selection: $segment) {
                    Text("活动").tag(0)
                    Text("定时").tag(1)
                    Text("系统").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.top, OneDayMetrics.spacingL)
                switch segment {
                case 0: activitySection
                case 1: cronSection
                default: systemSection
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            // 0.4.0（§3.2）：tabBarZone 手算留白删除，底部
            // 避让回系统安全区；留常规尾距
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("状态")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 身份头

    private var identityHead: some View {
        // 0.3.7 卡 4：身份头居中＋头像位（圆面＋字形），
        // host 地址行撤下（归服务器详情）
        VStack(spacing: OneDayMetrics.spacingS) {
            ZStack {
                // 0.3.8：枢纽页头像改白浮纸画法（近白面＋
                // 发丝边＋柔影，与全局浮件令牌同族）
                Circle()
                    .fill(Palette.floatFill)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(Palette.hairline, lineWidth: 0.5)
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
            }
            // 0.4.0（§1.1）：头像圆的手搓阴影随 Elevation
            // 整表废止退役
            HStack(spacing: OneDayMetrics.spacingS) {
                // 0.36.22：页头名收敛档案出口（原字面
                // "Hermes" 是显示名不是版本标识）
                Text(appState.agentDisplayName)
                    .font(.title2)
                    .foregroundStyle(Palette.ink)
                StatusDot(color: status.map { Palette.stateColor($0.gatewayState) }
                    ?? Palette.inkMuted)
            }
            Text(statusLine)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLine: String {
        // 0.4.0（审计 §3.3 #4）：模型后缀撤除——模型露头
        // 只许聊天页胶囊一处（A 案），本行只留状态词
        status == nil
            ? "状态读取中"
            : ServerLabels.gatewayState(status?.gatewayState, running: status?.gatewayRunning)
    }

    // MARK: - 活动

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("最近会话")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            if sessions.isEmpty {
                Text("暂无服务端会话")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            GroupDivider()
                        }
                        Button {
                            onOpenSession(session.id)
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                StatusDot(color: session.isActive
                                    ? Palette.success : Palette.inkMuted)
                                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                                    // 卡 16/18 同源：SessionDisplay
                                    // 人话标题＋副题，原始名不上屏
                                    Text(session.humanTitle)
                                        .font(.body)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text(session.humanSubtitle(now: Date()))
                                        .font(.footnote)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer(minLength: OneDayMetrics.spacingS)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Palette.inkMuted)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .frame(minHeight: OneDayMetrics.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                    }
                }
                .odGroup()
            }
            SectionLabel("近期事件")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            if logLines.isEmpty {
                Text("暂无日志。有新事件时，会记在这里。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                // 0.3.8 基线补遗（审计三行结构）：近期事件
                // 改人话三行——动作标题＋说明＋级别·时间脚
                // 注，原始日志行退到脚注（LogDisplay 解析）
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        let entry = LogDisplay.parse(line)
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(entry.headline)
                                .font(.callout)
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(entry.meta)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .padding(OneDayMetrics.spacingM)
                .odGroup()
            }
        }
    }

    // MARK: - 定时（摘要）

    /// 定时段（台账 198 收敛 C3 定案形态）：本页只做
    /// 摘要——接下来 3 条（行走共用 CronOverviewRow、
    /// 与枢纽概览同一行件）＋「全部定时任务」直达正
    /// 主管理页（与本页系统段体检行直达体检面同式）；
    /// 全量分组概览归枢纽定时段、本页不再整表复刻。
    /// 数据走共享 CronStore（与枢纽/正主同一份）
    private var cronSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("接下来运行")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            if cronJobs.isEmpty {
                Text(cronStore.hasLoaded ? "暂无定时任务" : "正在读取定时任务…")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingJobs.prefix(3).enumerated()), id: \.element.id) { index, job in
                        if index > 0 {
                            GroupDivider()
                        }
                        CronOverviewRow(item: CronHubClassifier.classify(
                            job, lastRunOverride: cronStore.lastRuns[job.id]
                        ))
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingS)
                    }
                    GroupDivider()
                    NavigationLink {
                        CronJobsView()
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Text("全部定时任务")
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: OneDayMetrics.spacingS)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Palette.inkMuted)
                                .accessibilityHidden(true)
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
    }

    /// 启用任务按 next_run 在前，暂停的垫底
    private var upcomingJobs: [CronJob] {
        cronJobs.sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled { return lhs.enabled }
            let l = AdminFormat.iso(lhs.nextRunAt) ?? .distantFuture
            let r = AdminFormat.iso(rhs.nextRunAt) ?? .distantFuture
            return l < r
        }
    }

    // MARK: - 系统

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("资源")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            if let stats {
                VStack(spacing: 0) {
                    percentRow("内存", percent: stats.memory?.percent,
                               detail: memoryDetail(stats))
                    GroupDivider()
                    percentRow("磁盘", percent: stats.disk?.percent,
                               detail: diskDetail(stats))
                    GroupDivider()
                    // 键值行走 KeyValueRow（台账 198 收
                    // 敛 S5 嫌疑页查实：本页系统段九处同
                    // 构造，一并替换；percentRow 是自绘
                    // 条行、不在此列）
                    KeyValueRow("CPU", value: stats.cpuPercent.map {
                        "\(AdminFormat.count($0))% · \(stats.cpuCount ?? 0) 核"
                    } ?? "—")
                    GroupDivider()
                    KeyValueRow("负载", value: stats.loadAvg.map {
                        $0.map { AdminFormat.count($0) }.joined(separator: " / ")
                    } ?? "—")
                    GroupDivider()
                    KeyValueRow("运行时间", value: stats.uptimeSeconds.map(uptimeText) ?? "—")
                    GroupDivider()
                    KeyValueRow("进程内存", value: stats.process?.rss.map(byteText) ?? "—")
                }
                .odGroup()
                SectionLabel("版本与运行时")
                    .padding(.top, OneDayMetrics.sectionOuterSpacing)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    KeyValueRow("Hermes", value: stats.hermesVersion.map { "v\($0)" } ?? "—")
                    GroupDivider()
                    KeyValueRow("主机", value: stats.hostname ?? "—")
                    GroupDivider()
                    KeyValueRow("系统", value: [stats.os, stats.arch]
                        .compactMap { $0 }.joined(separator: " · "))
                    GroupDivider()
                    KeyValueRow("Python", value: stats.pythonVersion ?? "—")
                    GroupDivider()
                    KeyValueRow("内核", value: stats.osRelease ?? "—")
                }
                .odGroup()
            } else {
                Text("正在读取系统状态…")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            // 体检次入口（H1-a）：状态页是「看现在」、
            // 体检面是「跑一遍查问题」——本行只呈上次
            // 结论与时间，点进体检面，不在此处跑检查
            SectionLabel("体检")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            NavigationLink {
                HealthCheckView()
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    StatusDot(color: lastHealthColor)
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingMicro
                    ) {
                        Text("上次体检")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text(lastHealthText)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .odGroup()
        }
    }

    private var lastHealthSummary: HealthCheckSummary? {
        healthSummaryStore.summary(for: appState.config?.baseString)
    }

    private var lastHealthText: String {
        guard let summary = lastHealthSummary else {
            return "还没做过体检"
        }
        return summary.overall.word + " · "
            + DisplayDate.relativeDateTime(summary.date)
    }

    private var lastHealthColor: Color {
        switch lastHealthSummary?.overall {
        case .ok: return Palette.success
        case .attention: return Palette.warning
        case .problem: return Palette.danger
        case .incomplete, nil: return Palette.inkMuted
        }
    }

    private func percentRow(_ label: String, percent: Double?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack {
                Text(label)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(detail)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
            }
            // 0.3.7 卡 4：数据条走共享 DataBar 中性口径
            // （原主色蓝填充退出——蓝只许功能位）
            DataBar(fraction: (percent ?? 0) / 100, height: 6)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingSM)
    }

    // （键值行沿革：infoRow（0.4.0 删）→ LabeledContent
    // → KeyValueRow（台账 198 收敛 S5：组卡内键值行单源件））

    private func memoryDetail(_ stats: SystemStats) -> String {
        guard let memory = stats.memory,
              let used = memory.used, let total = memory.total else {
            return stats.memory?.percent.map { "\(AdminFormat.count($0))%" } ?? "—"
        }
        return "\(byteText(used)) / \(byteText(total))"
    }

    private func diskDetail(_ stats: SystemStats) -> String {
        guard let disk = stats.disk,
              let used = disk.used, let total = disk.total else {
            return stats.disk?.percent.map { "\(AdminFormat.count($0))%" } ?? "—"
        }
        return "\(byteText(used)) / \(byteText(total))"
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private func uptimeText(_ seconds: Double) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours) 小时 \(minutes) 分"
    }

    // MARK: - 数据

    private func load() async {
        // 身份头状态与定时摘录自台账 198 收敛起归共享
        // 店：身份头经枢纽 store 回读其快照（取数仍在
        // 店内一处），定时经 CronStore 按需加载（已加
        // 载即跳过）；本页不再自拉 status/cronJobs 两份
        await appState.sharedHubStore().refreshServerStatus()
        await cronStore.loadIfNeeded()
        if let page = try? await appState.performAdmin({ client, config in
            try await client.serverSessions(config: config, limit: 8)
        }) {
            sessions = page.sessions
        }
        if let logs = try? await appState.performAdmin({ client, config in
            try await client.logs(config: config, level: nil, search: nil, lines: 30)
        }) {
            logLines = Array(logs.lines.suffix(12).reversed())
        }
        if let loaded = try? await appState.performAdmin({ client, config in
            try await client.systemStats(config: config)
        }) {
            stats = loaded
        }
    }
}
