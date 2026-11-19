import Foundation
import OneDayCore

/// 体检留痕（H1-a）：每台服务器只存最近一次体检的结
/// 论摘要（时间＋四态＋各组计数），原始日志永不落盘
/// （可能含敏感路径/配置值）。归宿与 ThreadReadMark-
/// Store 同式（UserDefaults JSON）；体检面与状态页次
/// 入口共读同一份（shared）。
@MainActor
@Observable
final class HealthSummaryStore {
    static let shared = HealthSummaryStore()

    private let defaults: UserDefaults
    private var summaries: [String: HealthCheckSummary] = [:]

    private static let defaultsKey = "health.lastSummary.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(
               [String: HealthCheckSummary].self, from: data
           ) {
            summaries = decoded
        }
    }

    func summary(for serverBase: String?) -> HealthCheckSummary? {
        guard let serverBase else { return nil }
        return summaries[serverBase]
    }

    func save(_ summary: HealthCheckSummary) {
        summaries[summary.serverBase] = summary
        if let data = try? JSONEncoder().encode(summaries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// 体检动作（服务端 action 名即日志名）
enum HealthAction: String, Sendable {
    case doctor = "doctor"
    case securityAudit = "security-audit"

    var name: String { rawValue }
}

/// 引擎内部错误（对外只翻人话，见 humanMessage）
enum HealthCheckEngineError: Error {
    /// 轮询超时（含本轮标记一直没落盘）
    case timedOut
}

/// 体检引擎（H1-a）：两组依次跑（doctor → security-
/// audit）——服务端同一 action 只有一个跟踪槽、日志
/// 又是多方共享的追加文件，并行只会互相串轮（H1-0
/// 探活口径）。每组独立状态：一组失败不拖垮整面，失
/// 败组可单独重试；整轮结束把结论摘要落留痕。
@MainActor
@Observable
final class HealthCheckStore {
    enum Phase: Equatable {
        case idle
        case running(since: Date)
        case finished
        /// 失败的人话原因（这一项没跑成，与「没跑完」
        /// 的检查结论分开：这是客户端/网络层没跑成）
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    /// 一轮动作的执行口：注入点在「按动作名跑到终态
    /// 并带回本轮日志切片＋退出码」这一层——生产实现
    /// 是 spawn＋poll（liveExecutor），测试注入脚本。
    typealias ActionExecutor =
        @MainActor (HealthAction) async throws -> ActionResult

    struct ActionResult: Sendable {
        var lines: [String]
        var exitCode: Int?
    }

    private(set) var doctorPhase: Phase = .idle
    private(set) var auditPhase: Phase = .idle
    private(set) var doctorRun: DoctorRun?
    private(set) var auditRun: SecurityAuditRun?

    private let summaryStore: HealthSummaryStore

    init(summaryStore: HealthSummaryStore = .shared) {
        self.summaryStore = summaryStore
    }

    var isRunning: Bool {
        doctorPhase.isRunning || auditPhase.isRunning
    }

    /// 「开始体检」可用性：任一组在跑时整面禁用重入
    /// （同名动作串行化口径，见类头注）
    var canStart: Bool { !isRunning }

    func phase(for action: HealthAction) -> Phase {
        switch action {
        case .doctor: return doctorPhase
        case .securityAudit: return auditPhase
        }
    }

    // MARK: - 对外入口（生产）

    func runAll(appState: AppState) async {
        guard let base = appState.config?.baseString else {
            doctorPhase = .failed("还没连上服务器")
            auditPhase = .failed("还没连上服务器")
            return
        }
        await runAll(
            serverBase: base,
            execute: Self.liveExecutor(appState: appState)
        )
    }

    /// 单组重试（失败组的人话重试按钮）
    func retry(_ action: HealthAction, appState: AppState) async {
        guard let base = appState.config?.baseString else {
            setPhase(action, .failed("还没连上服务器"))
            return
        }
        await retry(
            action, serverBase: base,
            execute: Self.liveExecutor(appState: appState)
        )
    }

    // MARK: - 状态机（测试可注入执行口）

    func runAll(
        serverBase: String, execute: ActionExecutor
    ) async {
        guard !isRunning else { return }
        await performGroup(.doctor, execute: execute)
        await performGroup(.securityAudit, execute: execute)
        saveSummary(serverBase: serverBase)
    }

    func retry(
        _ action: HealthAction, serverBase: String,
        execute: ActionExecutor
    ) async {
        guard !isRunning else { return }
        await performGroup(action, execute: execute)
        saveSummary(serverBase: serverBase)
    }

    private func performGroup(
        _ action: HealthAction, execute: ActionExecutor
    ) async {
        setPhase(action, .running(since: Date()))
        do {
            let result = try await execute(action)
            switch action {
            case .doctor:
                doctorRun = DoctorLogParser.parse(
                    lines: result.lines, exitCode: result.exitCode
                )
            case .securityAudit:
                auditRun = SecurityAuditLogParser.parse(
                    lines: result.lines, exitCode: result.exitCode
                )
            }
            setPhase(action, .finished)
        } catch {
            setPhase(action, .failed(Self.humanMessage(for: error)))
        }
    }

    private func setPhase(_ action: HealthAction, _ phase: Phase) {
        switch action {
        case .doctor: doctorPhase = phase
        case .securityAudit: auditPhase = phase
        }
    }

    /// 留痕合成：本轮跑过的组用本轮结论，失败组记
    /// 「没跑完」，没跑的组沿用上次留痕（单组重试不
    /// 冲掉另一组的旧结论）
    private func saveSummary(serverBase: String) {
        let previous = summaryStore.summary(for: serverBase)
        let doctorSummary = groupSummary(
            for: .doctor, previous: previous?.doctor
        )
        let auditSummary = groupSummary(
            for: .securityAudit, previous: previous?.audit
        )
        guard doctorSummary != nil || auditSummary != nil else { return }
        summaryStore.save(
            HealthCheckSummary(
                date: Date(), serverBase: serverBase,
                doctor: doctorSummary, audit: auditSummary
            )
        )
    }

    private func groupSummary(
        for action: HealthAction,
        previous: HealthGroupSummary?
    ) -> HealthGroupSummary? {
        switch phase(for: action) {
        case .finished:
            switch action {
            case .doctor: return doctorRun?.groupSummary
            case .securityAudit: return auditRun?.groupSummary
            }
        case .failed:
            return HealthGroupSummary(
                verdict: .incomplete,
                headline: action == .doctor
                    ? "自检没跑完" : "安全审计没跑完"
            )
        case .idle, .running:
            return previous
        }
    }

    /// 失败人话化：不甩状态码与内部名（G-03 同族口径）
    static func humanMessage(for error: Error) -> String {
        if let engine = error as? HealthCheckEngineError {
            switch engine {
            case .timedOut:
                return "等太久了，这一轮没等到结果"
            }
        }
        if let hermes = error as? HermesError {
            switch hermes {
            case .sessionExpired, .loginRejected:
                return "登录已过期，重新连接后再试"
            case .unreachable, .transientNetwork:
                return "连不上服务器，检查网络后再试"
            case .demoLimitReached:
                return "演示模式下不能体检"
            default:
                return "这一项没跑成，稍后再试"
            }
        }
        return "这一项没跑成，稍后再试"
    }

    // MARK: - 生产执行口（spawn＋poll）

    /// 两段式执行（H1-0 探活冻结口径）：
    /// 1. 先读一次状态：同名动作已在跑（可能来自其他
    ///    客户端）就直接收养那一轮，不重复触发——服务
    ///    端按名只有一个跟踪槽，后触发会覆盖先触发；
    /// 2. 触发前数清日志里已有的 started 标记数作基
    ///    线，轮询只认基线之后新落的本轮标记，旧轮的
    ///    「已跑完」状态不许误收（日志多方共享）；
    /// 3. 2.5 秒一轮询，总超时 60 秒（实测每轮 10–15
    ///    秒，60 秒是四倍余量）；超时抛 timedOut，界
    ///    面落「没等到结果」＋单组重试，不无限转圈。
    static func liveExecutor(
        appState: AppState
    ) -> ActionExecutor {
        { action in
            let name = action.name
            let statusPath = name
            let pre = try await appState.performAdmin { client, config in
                try await client.opsActionStatus(
                    config: config, name: statusPath, lines: 500
                )
            }
            let baseline: Int
            if pre.running {
                // 收养在飞的一轮：它的标记已在日志里，
                // 基线退一格把该标记算作本轮
                baseline = max(
                    OpsActionLog.markerCount(
                        lines: pre.lines, actionName: name
                    ) - 1, 0
                )
            } else {
                baseline = OpsActionLog.markerCount(
                    lines: pre.lines, actionName: name
                )
                _ = try await appState.performAdmin { client, config in
                    switch action {
                    case .doctor:
                        return try await client.opsDoctor(config: config)
                    case .securityAudit:
                        return try await client.opsSecurityAudit(
                            config: config
                        )
                    }
                }
            }
            let deadline = Date().addingTimeInterval(60)
            while true {
                let status = try await appState.performAdmin {
                    client, config in
                    try await client.opsActionStatus(
                        config: config, name: statusPath, lines: 500
                    )
                }
                if !status.running,
                   let sliced = OpsActionLog.sliceAfterMarker(
                       lines: status.lines, actionName: name,
                       ordinal: baseline
                   ) {
                    return ActionResult(
                        lines: sliced, exitCode: status.exitCode
                    )
                }
                if Date() > deadline {
                    throw HealthCheckEngineError.timedOut
                }
                try await Task.sleep(for: .seconds(2.5))
            }
        }
    }
}
