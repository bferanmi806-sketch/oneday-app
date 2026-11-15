import Foundation
import OneDayCore
import SwiftData

/// 会话账本（第 67 条收口包一，2026-11-15）：「我有
/// 哪些会话」的单店——全 App 唯一拉取者＋合并名单
/// 持有者。底层存储零迁移：SwiftData ChatThread（本
/// 体）、Hermes /api/sessions（服务端真源）、User-
/// Defaults 侧账（原键）都不动，换的是记账的人。
///
/// 读口：records（合并名单，本地线程由各面 @Query
/// 在刷新/呈现时注入——账本不自持 ModelContext）与
/// 其投影（LedgerProjection 纯函数，本店只做转发）。
/// 存活集只许连完整性一并交出（liveSet）：complete
/// 才可用于对账删除判定，incomplete 只可留痕/呈现。
///
/// 写路径：包一只开同步（refresh/refreshVisible）；
/// 包二起删除引擎（SessionDeletionEngine）归本店
/// 持有——删除走账本单管线，SessionDeletionCoordi-
/// nator 降为转发壳；归档/改名仍走动作层写穿（调
/// 用方改读账本）。ServerSessionCatalog 自包一起
/// 降为转发壳（publish/remove/refreshIfCold 转本
/// 店），外部调用方一字不改。
@MainActor
@Observable
final class SessionLedger {
    /// 删除引擎（包二归属）：待删队列/墓碑/后台围
    /// 栏删/落定收口/失败恢复全在此一台，队列是待
    /// 删集的唯一真相（各面过滤只读本队列，经本店
    /// 构建名单时一处过滤）
    let deletions = SessionDeletionEngine()
    /// 可见段展示名单（archived=exclude 拉全、待删
    /// 集已过滤——与旧 ServerSessionCatalog.visible-
    /// Sessions 逐字同义，目录壳转发读本列）
    private(set) var visibleSessions: [ServerSession] = []
    /// 已归档段展示名单（archived=only 拉全、待删集
    /// 已过滤——旧 AllConversationsStore.archived-
    /// Sessions 的收编）
    private(set) var archivedSessions: [ServerSession] = []
    /// 可见段是否已有一轮全量结果（冷/热唯一判定：
    /// 拉到空集也是结果，不许每开一次抽屉重拉全量）
    private(set) var hasLoaded = false
    /// 两段全量刷新是否完成过（收养判定读账本名单
    /// 的凭据：未完成时收养路回落现拉 include）
    private(set) var hasLoadedFull = false
    /// 主线行兜底：两段都没拉到钦定 id 时的单查结果
    /// （旧 AllConversationsStore.mainFallback 收编）
    private(set) var mainFallback: ServerSession?
    /// 最近一轮全量刷新的存活集＋完整性（refresh 内
    /// 以未过滤两段构造；不完整时 completeness 带原
    /// 因、ids 只作留痕呈现、不许喂删除判定）
    private(set) var liveSessionIDs: Set<String> = []
    private(set) var liveCompleteness: LedgerCompleteness =
        .incomplete(reason: "尚未拉取")
    /// 可见段刷新在飞标记（多路触发合并成一轮）
    private var isRefreshingVisible = false

    // MARK: - 读口

    /// 合并名单：账本段名单＋注入的本地线程现场重
    /// 演 join 与合并（合并/分类/投影全在 Core 纯函
    /// 数，本店只摘侧账输入）
    func records(
        appState: AppState, localThreads: [ChatThread]
    ) -> [SessionRecord] {
        SessionLedgerMerge.records(
            visible: visibleSessions,
            archived: archivedSessions,
            localThreads: localThreads.map(LedgerLocalThread.init),
            inputs: SessionLedgerMerge.Inputs(
                mainThreadID: appState.sideChats.mainThreadID,
                mainServerSessionID: appState.sideChats
                    .mainServerSessionID,
                archivedKeys: appState.sideChats.archivedKeys,
                pendingDeletionIDs: deletions.queue.sessionIDs,
                firstUserMessages: appState.sessionTitles
                    .firstUserMessages
            )
        )
    }

    /// 存活集＋完整性（B-1 闸的接口级形态）
    func liveSet() -> (ids: Set<String>,
                       completeness: LedgerCompleteness) {
        (liveSessionIDs, liveCompleteness)
    }

    func drawerSideRows(
        appState: AppState, localThreads: [ChatThread]
    ) -> [SessionRecord] {
        LedgerProjection.drawerSideRows(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func managementVisible(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.managementVisible(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func managementArchived(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.managementArchived(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func channelList(
        appState: AppState, localThreads: [ChatThread],
        channelID: String
    ) -> [ServerSession] {
        LedgerProjection.channelList(
            records(appState: appState, localThreads: localThreads),
            channelID: channelID
        )
    }

    func hubSessions(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.hubSessions(
            records(appState: appState, localThreads: localThreads)
        )
    }

    // MARK: - 同步（唯一拉取者）

    /// 全量刷新（管理页 load 的收编）：两段拉全→合
    /// 并落位→完整时对账回收（B-1 闸：任一段不完整
    /// 跳过对账并留痕，宁可不清、不可误清）→主线兜
    /// 底单查→标题回落素材。§233 归档缓存回写已退
    /// 役（包二）：归档态直接读记录归档列（过回写
    /// 闸的绑定以服务端段为准、余者以本地键为准，
    /// archiveSource 如实分列），不再把服务端态反
    /// 向改写本地键。时序与旧 AllConversationsStore
    /// .load 逐拍一致：可见段拉成即落位（不被归档
    /// 段失败连坐）；任一段 throw 由调用方转人话错误
    func refresh(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async throws {
        let visibleFetch = try await ServerSessionCatalog
            .fetchAll(appState: appState, archived: "exclude")
        let visible = visibleFetch.sessions
        // §232：待删集不进展示与目录（服务端此刻仍
        // 有其行，不过滤会被重拉带回）；对账存活集
        // 用未过滤全集（待删会话在服务端尚存活，其
        // 墓碑线程不许被对账误清）
        let pendingDeletions = deletions.queue.sessionIDs
        visibleSessions = visible.filter {
            !pendingDeletions.contains($0.id)
        }
        hasLoaded = true
        let archivedFetch = try await ServerSessionCatalog
            .fetchAll(appState: appState, archived: "only")
        let archived = archivedFetch.sessions
        archivedSessions = archived.filter {
            !pendingDeletions.contains($0.id)
        }
        // §223 名单对账＋B-1 防护闸（2026-11-14）
        if visibleFetch.isComplete && archivedFetch.isComplete {
            liveSessionIDs = Set(visible.map(\.id))
                .union(archived.map(\.id))
            liveCompleteness = .complete
            DeletedSessionCloseout.reconcileLocalThreads(
                threads: localThreads,
                liveSessionIDs: liveSessionIDs,
                appState: appState, modelContext: modelContext
            )
        } else {
            liveCompleteness = .incomplete(
                reason: "可见段："
                    + (visibleFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "；归档段："
                    + (archivedFetch.incompleteReason?
                        .traceLabel ?? "完整")
            )
            ChatDiagTrace.record(
                "全部对话名单对账跳过：名单不完整"
                    + "（可见段："
                    + (visibleFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "；归档段："
                    + (archivedFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "），本地线程本轮不动"
            )
        }
        if let mainID = appState.sideChats.mainServerSessionID,
           !visible.contains(where: { $0.id == mainID }),
           !archived.contains(where: { $0.id == mainID }) {
            mainFallback = try? await appState.performAdmin {
                client, config in
                try await client.serverSession(
                    config: config, id: mainID
                )
            }
        } else {
            mainFallback = nil
        }
        hasLoadedFull = true
        // 标题回落素材：无服务端标题者才拉消息派生
        await appState.sessionTitles.ensureTitles(
            for: visible + archived, appState: appState,
            budget: 12
        )
    }

    /// 可见段刷新（抽屉/频道页触发点的收编）：旧抽
    /// 屉 loadDrawerData 每开必拉第一页喂 source/标
    /// 题映射；本路改拉可见段全量落账本（现存规模
    /// 下与一页同价），source/标题改读记录列。只喂
    /// 显示、不驱动任何删除——名单不完整也照常落
    /// 位（防护闸只拦以名单为存活集的删除/回收）。
    /// 标题回落素材补拉同在本路（包二：名单面的标
    /// 题补拉只许在账本内发生）。返回是否拉到名单
    /// （频道页据此呈现失败态）
    @discardableResult
    func refreshVisible(
        appState: AppState, localThreads: [ChatThread]
    ) async -> Bool {
        guard !isRefreshingVisible else { return false }
        isRefreshingVisible = true
        defer { isRefreshingVisible = false }
        guard let result = try? await ServerSessionCatalog
            .fetchAll(appState: appState, archived: "exclude")
        else { return false }
        let pending = deletions.queue.sessionIDs
        visibleSessions = result.sessions.filter {
            !pending.contains($0.id)
        }
        hasLoaded = true
        await appState.sessionTitles.ensureTitles(
            for: result.sessions, appState: appState,
            budget: 12
        )
        return true
    }

    /// 冷缓存补拉（目录壳 refreshIfCold 的收编）：
    /// 已热或在飞直接返回；失败不置 hasLoaded（下次
    /// 触发重试）、不抛错
    func refreshVisibleIfCold(
        appState: AppState, localThreads: [ChatThread]
    ) async {
        guard !hasLoaded, !isRefreshingVisible else { return }
        await refreshVisible(
            appState: appState, localThreads: localThreads
        )
    }

    /// 收养判定名单（ChatView adoptOnTitleConflict
    /// 的收编）：账本两段齐全时读账本名单（含已归
    /// 档段——占名者可能已归档）；未齐全回落现拉
    /// include 全量。只用于候选检索、不驱动删除，
    /// 不需完整性闸（不完整至多漏候选、方向保守）；
    /// 拉不到返回 nil（调用方照抛原错误、不收养）
    func adoptionSessions(
        appState: AppState
    ) async -> [ServerSession]? {
        if hasLoadedFull {
            var seen = Set<String>()
            return (visibleSessions + archivedSessions).filter {
                seen.insert($0.id).inserted
            }
        }
        return try? await ServerSessionCatalog.fetchAll(
            appState: appState, archived: "include"
        ).sessions
    }

    // MARK: - 目录壳转发面（旧 Catalog 语义逐字）

    /// 写回（旧 publish）：调用方已付分页代价且已过
    /// 待删过滤，同份可见集落本店
    func publishVisible(_ visible: [ServerSession]) {
        visibleSessions = visible
        hasLoaded = true
    }

    /// 摘行（旧 Catalog.remove＋管理页 removeLocal
    /// 的合一）：服务端会话已确认删除/不存在，两段
    /// 名单与主线兜底同拍摘除，不等下一轮全量拉取
    func removeSession(sessionID: String) {
        visibleSessions.removeAll { $0.id == sessionID }
        archivedSessions.removeAll { $0.id == sessionID }
        if mainFallback?.id == sessionID { mainFallback = nil }
    }

    // MARK: - 标题读点（包二：冲突处理归账本一处）

    /// 服务端行标题的唯一读点：存量本地覆盖（迁移
    /// 未排空的遗留改名）优先，其后统一管线（服务
    /// 端标题＞派生＞人话名）。管理页/频道页行标题
    /// 都经本口，不许各面再直读覆盖表与解析器
    func title(
        for session: ServerSession, appState: AppState
    ) -> String {
        appState.sideChats.titleOverrides[session.id]
            ?? appState.sessionTitles.title(for: session)
    }

    // MARK: - 删除落定收口（包二：收口归账本门面）

    /// 单条落定收口（转发 §223 共享收口实现）：服
    /// 务端删除已回查落定后清侧账＋账本摘行＋删绑
    /// 定线程。删除引擎的落定段与名单对账都经账本
    /// 内部路径至此，外部面不许再直调收口件
    func closeoutDeletedSession(
        sessionID: String, appState: AppState,
        threads: [ChatThread], modelContext: ModelContext
    ) {
        DeletedSessionCloseout.apply(
            sessionID: sessionID, appState: appState,
            threads: threads, modelContext: modelContext
        )
    }

    /// 点开已消失会话的防御收口（转发 §223）：清侧
    /// 账＋账本摘行，行即消失
    func noteOpenedSessionMissing(
        sessionID: String, appState: AppState
    ) {
        DeletedSessionCloseout.handleOpenedSessionMissing(
            sessionID: sessionID, appState: appState
        )
    }
}

/// ChatThread → 账本快照（合并注入形）：逐字段摘
/// 出，账本与 Core 合并函数不直碰 SwiftData 本体
extension LedgerLocalThread {
    init(_ thread: ChatThread) {
        self.init(
            id: thread.id, title: thread.title,
            titleIsManual: thread.titleIsManual,
            serverSessionID: thread.serverSessionID,
            isPendingDeletion: thread.isPendingDeletion,
            isPinned: thread.isPinned,
            updatedAt: thread.updatedAt,
            createdAt: thread.createdAt,
            linkFailureCount: thread.linkFailureCount,
            linkLastError: thread.linkLastError
        )
    }
}
