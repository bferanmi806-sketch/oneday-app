import OneDayCore
import Observation

/// 服务端会话全量目录（§198 立、第 67 条包一收编）：
/// 自账本包一起本类降为 SessionLedger 的转发壳——
/// 名单本体、冷热位、拉取调度全归账本单店，本类只
/// 留三件：①旧调用面（publish/remove/refreshIfCold）
/// 转发，删除协调器/收口件/既有测试一字不改；②分
/// 页装配核（fetchAll/fetchAllPages＋完整性判定，
/// B-1 防护）仍是全 App 唯一实现，账本 refresh 调
/// 它、不另抄一份；③未接线（AppState init 前）时读
/// 空集——目录只喂显示，空集＝频道区暂不显，与旧
/// 拉取失败形态一致。
@MainActor
@Observable
final class ServerSessionCatalog {
    /// 账本本体（AppState init 接线）
    @ObservationIgnored
    weak var ledger: SessionLedger?

    /// 可见全量（账本展示名单的转发读）
    var visibleSessions: [ServerSession] {
        ledger?.visibleSessions ?? []
    }

    /// 是否已有一轮全量结果（账本冷热位的转发读）
    var hasLoaded: Bool {
        ledger?.hasLoaded ?? false
    }

    /// 管理页写回（转发账本 publishVisible）
    func publish(visible: [ServerSession]) {
        ledger?.publishVisible(visible)
    }

    /// 摘行（转发账本 removeSession）
    func remove(sessionID: String) {
        ledger?.removeSession(sessionID: sessionID)
    }

    /// 冷缓存补拉（转发账本）：旧签名无本地线程入
    /// 参——本路只喂目录显示集，账本以空本地集刷新
    /// 可见段；记录合并在各面呈现时以其 @Query 注
    /// 入为准，本路不产记录
    func refreshIfCold(appState: AppState) async {
        await ledger?.refreshVisibleIfCold(
            appState: appState, localThreads: []
        )
    }

    /// 名单不完整的判定原因（B-1 防护，2026-11-14
    /// 同类横扫定案）：三类信号任一出现即判不完整
    enum IncompleteReason: Equatable {
        /// 10 页上限走满仍未见名单尽头——旧形态在
        /// 此静默截断，尾部整段无声消失
        case pageCapReached
        /// 服务端报的总数与实拉唯一行数对不上（含
        /// 拉取途中总数漂移：多页报数互不一致）
        case totalMismatch(reported: Int, fetched: Int)
        /// 页内/跨页出现重复行——offset 位移的指纹
        /// （拉取途中名单增删）：有重必有漏
        case duplicateRows(count: Int)

        /// 留痕用人话短句（不带状态码原文）
        var traceLabel: String {
            switch self {
            case .pageCapReached:
                return "分页上限走满、名单未见尽头"
            case .totalMismatch(let reported, let fetched):
                return "总数对不上（服务端报 \(reported)、实拉 \(fetched)）"
            case .duplicateRows(let count):
                return "分页出现重复行 \(count) 条"
            }
        }
    }

    /// 拉全结果：名单本体＋完整性判定。完整性是防
    /// 护闸的唯一凭据——以名单为存活集做删除/回收
    /// 的消费点必须先查 isComplete，不完整即跳过动
    /// 作并留痕（宁可不清、不可误清）；只喂显示的
    /// 消费点可直接取 sessions
    struct FetchResult {
        var sessions: [ServerSession]
        var incompleteReason: IncompleteReason?
        var isComplete: Bool { incompleteReason == nil }
    }

    /// 分页拉全：limit 100 逐页至不足一页或达 total，
    /// 上限 10 页（防服务端分页异常时无界拉取）——
    /// 本函数是管理页 fetchAll 收编后的唯一出处（管
    /// 理页同调本函数，两处不许再各抄一份）。
    /// B-1 防护（2026-11-14）：旧形态 append 累加、
    /// 无去重、无对账、上限处静默截断，下游对账以
    /// 此名单为存活集清本地线程——截断/漏行会被误
    /// 判「服务端已删」造成数据丢失。本形态：装配
    /// 时去重（保首现序）、全程对账，任一不完整信
    /// 号（上限走满/总数对不上或漂移/出现重行）即
    /// 在结果上打标并留痕，删除向消费点据标跳过
    static func fetchAll(
        appState: AppState, archived: String
    ) async throws -> FetchResult {
        let result = try await appState.performAdmin {
            client, config in
            try await Self.fetchAllPages { offset in
                try await client.serverSessionsPage(
                    config: config, limit: 100,
                    offset: offset, archived: archived
                )
            }
        }
        if let reason = result.incompleteReason {
            ChatDiagTrace.record(
                "会话名单不完整（archived=\(archived)）："
                    + reason.traceLabel
                    + "——以名单为存活集的删除/回收本轮跳过"
            )
        }
        return result
    }

    /// 分页装配核（页取口注入，单测以脚本页直驱）：
    /// 与 fetchAll 同一实现，不许另抄一份。offset 按
    /// 原始页行数推进（与服务端分页口径一致）；唯
    /// 一行集保首现序去重
    static func fetchAllPages(
        fetchPage: (Int) async throws -> SessionsPage
    ) async throws -> FetchResult {
        var all: [ServerSession] = []
        var seen = Set<String>()
        var duplicateCount = 0
        var reportedTotals = Set<Int>()
        var lastReportedTotal: Int?
        var offset = 0
        var ranOutOfPages = true
        for _ in 0..<10 {
            let page = try await fetchPage(offset)
            if let total = page.total {
                reportedTotals.insert(total)
                lastReportedTotal = total
            }
            for session in page.sessions {
                if seen.insert(session.id).inserted {
                    all.append(session)
                } else {
                    duplicateCount += 1
                }
            }
            if page.sessions.count < 100 {
                ranOutOfPages = false
                break
            }
            if let total = page.total, all.count >= total {
                ranOutOfPages = false
                break
            }
            offset += 100
        }
        let reason: IncompleteReason?
        if duplicateCount > 0 {
            reason = .duplicateRows(count: duplicateCount)
        } else if reportedTotals.count > 1 {
            reason = .totalMismatch(
                reported: lastReportedTotal ?? all.count,
                fetched: all.count
            )
        } else if let total = lastReportedTotal, total != all.count {
            reason = .totalMismatch(
                reported: total, fetched: all.count
            )
        } else if ranOutOfPages {
            reason = .pageCapReached
        } else {
            reason = nil
        }
        return FetchResult(
            sessions: all, incompleteReason: reason
        )
    }
}
