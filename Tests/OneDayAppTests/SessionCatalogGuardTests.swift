import Foundation
import OneDayCore
import SwiftData
import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import OneDayApp

/// B-1 防护（2026-11-14 同类横扫定案）验收钉测：
/// 会话名单分页拼接旧形态无去重、无对账、上限 10
/// 页静默截断，下游全部对话页以名单为存活集清本
/// 地线程——截断/漏行即数据丢失。本组钉三层：
/// ①fetchAll 完整性判定——截断（报总数/不报总数
///   两形态）、重复页、总数漂移各自打标，完整名
///   单不误标；装配去重保首现序；
/// ②下游闸——名单不完整时 AllConversationsStore
///   .load 跳过对账回收（存活集外的绑定线程不动、
///   名单展示照常落位）；
/// ③对照——名单完整时对账照常执行（闸不是把对
///   账整体关掉）。
/// 服务端页由脚本客户端按 (archived, offset) 定
/// 页，不走真网络。
@MainActor
final class SessionCatalogGuardTests: XCTestCase {

    private var container: ModelContainer!
    /// §184：容器租约——见 SwiftDataTestMount（容器进进程级
    /// 持有、永不释放）。本类建 ChatThread 容器，属第三轮兜
    /// 底收编范围（「进程内无任何容器死亡」不变量）；原包
    /// 在 .45 基线的自跑中曾被宿主崩溃吃掉对照例判词，移
    /// 植到 .47 线时按 DeleteCloseoutTests 同式对齐
    private var swiftDataMount = SwiftDataTestMount()
    private var context: ModelContext!
    private var priorMainSessionID: String?

    private let mainKey = "sideChats.mainServerSessionID"
    private let queueKey = "sessionDeletions.pendingQueue"

    override func setUp() async throws {
        try await super.setUp()
        priorMainSessionID = UserDefaults.standard.string(
            forKey: mainKey
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        if let priorMainSessionID {
            UserDefaults.standard.set(
                priorMainSessionID, forKey: mainKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: mainKey)
        }
        UserDefaults.standard.removeObject(forKey: queueKey)
        context = nil
        await swiftDataMount.release()
        container = nil
        try await super.tearDown()
    }

    // MARK: - 装配

    /// 页构造：走解码（SessionsPage/ServerSession
    /// 无公开成员构造器，与 DeleteCloseoutTests
    /// makeSession 同式）
    private func makePage(
        ids: [String], total: Int?
    ) -> SessionsPage {
        var json = "{\"sessions\":["
            + ids.map { "{\"id\":\"\($0)\"}" }
                .joined(separator: ",")
            + "]"
        if let total { json += ",\"total\":\(total)" }
        json += "}"
        return try! JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
    }

    private func ids(_ range: ClosedRange<Int>) -> [String] {
        range.map { "s-\($0)" }
    }

    private func makeAppState(
        pages: [String: SessionsPage]
    ) -> AppState {
        var client = ScriptedSessionsClient()
        client.scriptedPages = pages
        return AppState(client: client, demoMode: .connected)
    }

    @discardableResult
    private func makeThread(sessionID: String?) throws -> ChatThread {
        let thread = ChatThread(title: "测试线程")
        thread.serverSessionID = sessionID
        context.insert(thread)
        try context.save()
        return thread
    }

    private func threadExists(_ id: UUID) throws -> Bool {
        try context.fetch(FetchDescriptor<ChatThread>())
            .contains { $0.id == id }
    }

    // MARK: - ① 完整性判定：完整名单不误标

    func testFetchAllCompleteWhenPagesAgreeWithTotal() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ids(1...100), total: 150),
            "exclude|100": makePage(ids: ids(101...150), total: 150),
        ])
        let result = try await SessionLedger.fetchAll(
            appState: appState, archived: "exclude"
        )
        XCTAssertTrue(result.isComplete)
        XCTAssertNil(result.incompleteReason)
        XCTAssertEqual(result.sessions.map(\.id), ids(1...150))
    }

    func testFetchAllCompleteWhenTotalAbsentAndShortLastPage()
        async throws
    {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ids(1...100), total: nil),
            "exclude|100": makePage(ids: ids(101...130), total: nil),
        ])
        let result = try await SessionLedger.fetchAll(
            appState: appState, archived: "exclude"
        )
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.sessions.count, 130)
    }

    // MARK: - ① 截断：10 页走满、尾部名单缺席必打标

    /// 服务端报总数 1500、每页全满——10 页上限处
    /// 旧形态静默截断在 1000 条；新形态必须打标，
    /// 且原因对账得出（报 1500、实拉 1000）
    func testFetchAllFlagsTruncationWhenTotalBeyondCap() async throws {
        var pages: [String: SessionsPage] = [:]
        for pageIndex in 0..<10 {
            let start = pageIndex * 100 + 1
            pages["exclude|\(pageIndex * 100)"] = makePage(
                ids: ids(start...(start + 99)), total: 1500
            )
        }
        let appState = makeAppState(pages: pages)
        let result = try await SessionLedger.fetchAll(
            appState: appState, archived: "exclude"
        )
        XCTAssertEqual(result.sessions.count, 1000)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(
            result.incompleteReason,
            .totalMismatch(reported: 1500, fetched: 1000)
        )
    }

    /// 总数缺席时截断无从对账：上限走满且末页仍全
    /// 满＝名单未见尽头，同样必须打标（不许因为没
    /// 有 total 就默认完整）
    func testFetchAllFlagsTruncationWhenTotalAbsent() async throws {
        var pages: [String: SessionsPage] = [:]
        for pageIndex in 0..<10 {
            let start = pageIndex * 100 + 1
            pages["exclude|\(pageIndex * 100)"] = makePage(
                ids: ids(start...(start + 99)), total: nil
            )
        }
        let appState = makeAppState(pages: pages)
        let result = try await SessionLedger.fetchAll(
            appState: appState, archived: "exclude"
        )
        XCTAssertEqual(result.sessions.count, 1000)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(
            result.incompleteReason, .pageCapReached
        )
    }

    // MARK: - ① 重复页：offset 位移指纹必打标、装配去重

    /// 拉取途中名单增删令 offset 位移：第二页与第
    /// 一页重叠 50 行。唯一行数恰与 total 相等也
    /// 不许判完整——有重必有漏；装配结果去重保首
    /// 现序（显示面不许见重行）
    func testFetchAllFlagsDuplicatePagesAndDedupes() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ids(1...100), total: 150),
            "exclude|100": makePage(ids: ids(51...150), total: 150),
        ])
        let result = try await SessionLedger.fetchAll(
            appState: appState, archived: "exclude"
        )
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(
            result.incompleteReason, .duplicateRows(count: 50)
        )
        XCTAssertEqual(result.sessions.map(\.id), ids(1...150))
    }

    // MARK: - ① 总数漂移：多页报数互不一致必打标

    func testFetchAllFlagsTotalDriftAcrossPages() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ids(1...100), total: 120),
            "exclude|100": makePage(ids: ids(101...120), total: 130),
        ])
        let result = try await SessionLedger.fetchAll(
            appState: appState, archived: "exclude"
        )
        XCTAssertEqual(result.sessions.count, 120)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(
            result.incompleteReason,
            .totalMismatch(reported: 130, fetched: 120)
        )
    }

    // MARK: - ② 下游闸：名单不完整→对账跳过、线程不动

    /// 可见段总数漂移（不完整）、归档段完整为空：
    /// 存活集外的自有绑定线程本该被对账清掉，闸在
    /// 时必须原样保留；名单展示照常落位（闸只拦删
    /// 除向动作、不拦读面）
    func testLoadSkipsReconcileWhenListIncomplete() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ids(1...100), total: 120),
            "exclude|100": makePage(ids: ids(101...120), total: 130),
            "only|0": makePage(ids: [], total: 0),
        ])
        let victim = try makeThread(
            sessionID: "oneday-side-guard-victim"
        )
        let store = AllConversationsStore()
        await store.load(
            appState: appState,
            localThreads: try context.fetch(
                FetchDescriptor<ChatThread>()
            ),
            modelContext: context
        )
        XCTAssertTrue(try threadExists(victim.id))
        XCTAssertEqual(appState.sessionLedger.visibleSessions.count, 120)
        XCTAssertNil(store.loadError)
    }

    // MARK: - ③ 对照：名单完整→对账照常、残留照清

    func testLoadReconcilesWhenListsComplete() async throws {
        let appState = makeAppState(pages: [
            "exclude|0": makePage(ids: ["s-live"], total: 1),
            "only|0": makePage(ids: [], total: 0),
        ])
        let victim = try makeThread(
            sessionID: "oneday-side-guard-victim"
        )
        let live = try makeThread(sessionID: "s-live")
        let store = AllConversationsStore()
        await store.load(
            appState: appState,
            localThreads: try context.fetch(
                FetchDescriptor<ChatThread>()
            ),
            modelContext: context
        )
        XCTAssertFalse(try threadExists(victim.id))
        XCTAssertTrue(try threadExists(live.id))
    }

    // MARK: - ④ 端到端钉链（B-1 销账决胜例，筹备稿 §4.4-3）

    /// 两段同走 AllConversationsStore.load 真路：
    /// 段一（截断）：服务端名单共 1001 条、每页报
    /// total=1001，10 页上限只拉到前 1000 条；自有旁
    /// 聊线程绑第 1001 条（尾部 id）——旧形态名单静
    /// 默截断、对账以残缺名单为存活集，线程被物理删
    /// ＋侧账 purge；防护后必须整件不动（线程在、标
    /// 题覆盖在）。
    /// 段二（offset 位移重页）：第 2 页含第 1 页尾行
    /// （重行指纹），一条自有旁聊被位移挤出名单——
    /// 装配必须去重（展示名单 149 条无重行）、对账必
    /// 须跳过（被挤出的线程不动）。
    /// 本例在 .47 旧代码上两段皆红（线程删＋侧账清
    /// ＋名单带重行），防护入线后必绿
    func testLoadEndToEndTruncationAndShiftedPageKeepLocalThreads()
        async throws
    {
        // 段一：>1000 条名单＋尾部自有旁聊
        var pages: [String: SessionsPage] = [:]
        for pageIndex in 0..<10 {
            let start = pageIndex * 100 + 1
            pages["exclude|\(pageIndex * 100)"] = makePage(
                ids: ids(start...(start + 99)), total: 1001
            )
        }
        pages["only|0"] = makePage(ids: [], total: 0)
        let appState = makeAppState(pages: pages)
        let tailID = "oneday-side-tail-1001"
        let tailVictim = try makeThread(sessionID: tailID)
        appState.sideChats.setTitleOverride("尾巴标题", for: tailID)
        defer {
            appState.sideChats.setTitleOverride(nil, for: tailID)
        }
        let store = AllConversationsStore()
        await store.load(
            appState: appState,
            localThreads: try context.fetch(
                FetchDescriptor<ChatThread>()
            ),
            modelContext: context
        )
        XCTAssertNil(store.loadError)
        XCTAssertEqual(appState.sessionLedger.visibleSessions.count, 1000)
        XCTAssertTrue(try threadExists(tailVictim.id))
        XCTAssertEqual(
            appState.sideChats.titleOverrides[tailID], "尾巴标题"
        )

        // 段二：offset 位移重页＋被挤出的自有旁聊
        let appState2 = makeAppState(pages: [
            "exclude|0": makePage(ids: ids(1...100), total: 150),
            "exclude|100": makePage(
                ids: ["s-100"] + ids(101...149), total: 150
            ),
            "only|0": makePage(ids: [], total: 0),
        ])
        let shiftedVictim = try makeThread(
            sessionID: "oneday-side-shifted-out"
        )
        let store2 = AllConversationsStore()
        await store2.load(
            appState: appState2,
            localThreads: try context.fetch(
                FetchDescriptor<ChatThread>()
            ),
            modelContext: context
        )
        XCTAssertNil(store2.loadError)
        XCTAssertEqual(appState2.sessionLedger.visibleSessions.count, 149)
        XCTAssertEqual(
            Set(appState2.sessionLedger.visibleSessions.map(\.id)).count, 149
        )
        XCTAssertTrue(try threadExists(shiftedVictim.id))
        XCTAssertTrue(try threadExists(tailVictim.id))
    }
}

// MARK: - 脚本客户端（机械变换自 FailingHermesClient）

/// 写回执记录器（第 90 条收尾）：脚本客户端是值型，
/// 调用记录须落在引用型盒里才跨拷贝存活；协议面
/// Sendable——锁护存储、@unchecked 认领
final class SessionUpdateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(id: String, title: String?, pinned: Bool?, archived: Bool?)] = []

    var calls: [(id: String, title: String?, pinned: Bool?, archived: Bool?)] {
        lock.withLock { storage }
    }

    func record(
        id: String, title: String?, pinned: Bool?, archived: Bool?
    ) {
        lock.withLock {
            storage.append(
                (id: id, title: title, pinned: pinned, archived: archived)
            )
        }
    }
}

struct ScriptedSessionsClient: HermesClientProtocol {
    /// 页脚本（键＝"archived|offset"）：只 serverSessionsPage
    /// 查它，其余方法恒抛 unreachable（与 FailingHermesClient
    /// 同口径）。本桩由 FailingHermesClient 机械变换生成——
    /// 协议增删方法时须照同式重跑对齐（编译器以协议一致性
    /// 报错兜底）；原桩本体是 C-13 冻结面，不许给它长行为，
    /// 故脚本行为只活在本文件
    var scriptedPages: [String: SessionsPage] = [:]
    /// 单查行脚本（第 90 条收尾迁移触发测用）：server-
    /// Session(id) 查它，缺席仍抛 unreachable
    var scriptedSessions: [String: ServerSession] = [:]
    /// 写回执记录器（引用型，跨值拷贝存活）：update-
    /// ServerSession 的每次调用落此，缺席时仍抛
    /// unreachable（旧测试口径不变）
    var updateRecorder: SessionUpdateRecorder?

    func health(config: ServerConfig) async throws -> HealthResponse {
        throw HermesError.unreachable("离线桩")
    }

    func login(config: ServerConfig, password: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func status(config: ServerConfig) async throws -> ServerStatus {
        throw HermesError.unreachable("离线桩")
    }

    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary {
        throw HermesError.unreachable("离线桩")
    }

    func models(config: ServerConfig, apiKey: String) async throws -> [String] {
        throw HermesError.unreachable("离线桩")
    }

    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage],
        sessionID: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: HermesError.unreachable("离线桩")
            )
        }
    }

    func submitRun(
        config: ServerConfig, apiKey: String, sessionID: String,
        input: RunInput, model: String, provider: String?,
        idempotencyKey: String
    ) async throws -> RunSubmitResponse {
        throw HermesError.unreachable("离线桩")
    }

    func runStatus(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws -> RunStatusResponse? {
        throw HermesError.unreachable("离线桩")
    }

    func runEvents(
        config: ServerConfig, apiKey: String, runID: String,
        lastSeq: Int
    ) -> AsyncStream<RunEventEnvelope> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    func stopRun(
        config: ServerConfig, apiKey: String, runID: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func clearCookies(config: ServerConfig) {}

    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus {
        throw HermesError.unreachable("离线桩")
    }

    func setMemoryProvider(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func memoryProviderConfig(
        config: ServerConfig, name: String
    ) async throws -> MemoryProviderConfig {
        throw HermesError.unreachable("离线桩")
    }

    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func resetMemory(config: ServerConfig, target: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func skills(config: ServerConfig) async throws -> [SkillItem] {
        throw HermesError.unreachable("离线桩")
    }

    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent {
        throw HermesError.unreachable("离线桩")
    }

    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubSources(config: ServerConfig) async throws -> [HubSource] {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubSearch(
        config: ServerConfig, query: String, source: String?
    ) async throws -> [HubSkill] {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubPreview(
        config: ServerConfig, identifier: String
    ) async throws -> HubPreview {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubInstall(config: ServerConfig, identifier: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func skillHubUninstall(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func cronJobs(config: ServerConfig) async throws -> [CronJob] {
        throw HermesError.unreachable("离线桩")
    }

    func createCronJob(
        config: ServerConfig, name: String?, prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob {
        throw HermesError.unreachable("离线桩")
    }

    func updateCronJob(
        config: ServerConfig, id: String, updates: [String: JSONValue]
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func deleteCronJob(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func pauseCronJob(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func resumeCronJob(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func triggerCronJob(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession] {
        throw HermesError.unreachable("离线桩")
    }

    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage {
        throw HermesError.unreachable("离线桩")
    }

    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession {
        if let row = scriptedSessions[id] { return row }
        throw HermesError.unreachable("离线桩")
    }

    func createServerSession(config: ServerConfig, apiKey: String, id: String?, title: String?) async throws -> ServerSession {
        throw HermesError.unreachable("离线桩")
    }

    func createLinkedServerSession(config: ServerConfig, apiKey: String, id: String, model: String) async throws -> ServerSession {
        throw HermesError.unreachable("离线桩")
    }

    func importServerSession(
        config: ServerConfig, requestID: String,
        expectedRevision: Int, sessionBody: [String: JSONValue]
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func updateServerSessionModel(config: ServerConfig, id: String, model: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage] {
        throw HermesError.unreachable("离线桩")
    }

    func sessionMessagesPage(
        config: ServerConfig, id: String, limit: Int, offset: Int
    ) async throws -> [SessionMessage] {
        throw HermesError.unreachable("离线桩")
    }

    func searchSessions(
        config: ServerConfig, query: String, limit: Int
    ) async throws -> [SessionSearchHit] {
        throw HermesError.unreachable("离线桩")
    }

    func sessionMutationSnapshot(config: ServerConfig, id: String) async throws -> SessionMutationSnapshot {
        throw HermesError.unreachable("离线桩")
    }

    func deleteServerSession(config: ServerConfig, id: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func emptySessionCount(config: ServerConfig) async throws -> Int {
        throw HermesError.unreachable("离线桩")
    }

    func serverSessionsPage(
        config: ServerConfig, limit: Int, offset: Int, archived: String?
    ) async throws -> SessionsPage {
        let key = "\(archived ?? "nil")|\(offset)"
        if let page = scriptedPages[key] { return page }
        throw HermesError.unreachable("脚本页缺失：\(key)")
    }

    func updateServerSession(
        config: ServerConfig, id: String,
        title: String?, pinned: Bool?, archived: Bool?
    ) async throws {
        guard let updateRecorder else {
            throw HermesError.unreachable("离线桩")
        }
        updateRecorder.record(
            id: id, title: title, pinned: pinned, archived: archived
        )
    }

    func pruneSessions(
        config: ServerConfig, olderThanDays: Double, dryRun: Bool
    ) async throws -> Int? {
        throw HermesError.unreachable("离线桩")
    }

    func profiles(config: ServerConfig) async throws -> [ProfileItem] {
        throw HermesError.unreachable("离线桩")
    }

    func activeProfileName(config: ServerConfig) async throws -> String? {
        throw HermesError.unreachable("离线桩")
    }

    func setActiveProfile(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func profileSoul(
        config: ServerConfig, name: String
    ) async throws -> ProfileSoulDocument {
        throw HermesError.unreachable("离线桩")
    }

    func updateProfileSoul(
        config: ServerConfig, name: String, content: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func createProfile(
        config: ServerConfig, name: String, cloneFrom: String?
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func deleteProfile(config: ServerConfig, name: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func exportProfile(
        config: ServerConfig, name: String
    ) async throws -> ProfileExportResult {
        throw HermesError.unreachable("离线桩")
    }

    func importProfile(
        config: ServerConfig, archive: String, name: String?
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func computerUseStatus(
        config: ServerConfig
    ) async throws -> ComputerUseStatus {
        throw HermesError.unreachable("离线桩")
    }

    func mcpServers(config: ServerConfig) async throws -> [MCPServerItem] {
        throw HermesError.unreachable("离线桩")
    }

    func setMCPServerEnabled(
        config: ServerConfig, name: String, enabled: Bool
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func testMCPServer(
        config: ServerConfig, name: String
    ) async throws -> MCPTestResult {
        throw HermesError.unreachable("离线桩")
    }

    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue] {
        throw HermesError.unreachable("离线桩")
    }

    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func envVars(config: ServerConfig) async throws -> [EnvVarEntry] {
        throw HermesError.unreachable("离线桩")
    }

    func setEnvVar(config: ServerConfig, key: String, value: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func deleteEnvVar(config: ServerConfig, key: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func revealEnvVar(config: ServerConfig, key: String) async throws -> String {
        throw HermesError.unreachable("离线桩")
    }

    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics {
        throw HermesError.unreachable("离线桩")
    }

    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics {
        throw HermesError.unreachable("离线桩")
    }

    func modelOptions(config: ServerConfig) async throws -> [String] {
        throw HermesError.unreachable("离线桩")
    }

    func modelOptionsRaw(config: ServerConfig) async throws -> JSONValue {
        throw HermesError.unreachable("离线桩")
    }

    func setMainModel(
        config: ServerConfig, provider: String, model: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func mainModelAssignment(
        config: ServerConfig, providerNames: [String]
    ) async throws -> MainModelAssignment {
        throw HermesError.unreachable("离线桩")
    }

    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse {
        throw HermesError.unreachable("离线桩")
    }

    func egressStatus(config: ServerConfig) async throws -> EgressStatus {
        throw HermesError.unreachable("离线桩")
    }

    func messagingPlatforms(config: ServerConfig) async throws -> MessagingPlatformsResponse {
        throw HermesError.unreachable("离线桩")
    }

    func updateMessagingPlatform(config: ServerConfig, platform: String, enabled: Bool, env: [String: String], clearEnv: [String]) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func gatewayRestart(config: ServerConfig) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func gatewayStart(config: ServerConfig) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func gatewayStop(config: ServerConfig) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func files(config: ServerConfig, path: String?) async throws -> FilesListing {
        throw HermesError.unreachable("离线桩")
    }

    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func fileData(config: ServerConfig, path: String) async throws -> Data {
        throw HermesError.unreachable("离线桩")
    }

    func uploadFile(
        config: ServerConfig, path: String, dataURL: String, overwrite: Bool
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String
    ) async throws -> ManagedFileUploadReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func uploadAttachment(
        config: ServerConfig, path: String, dataURL: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ManagedFileUploadReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func makeDirectory(config: ServerConfig, path: String) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func systemStats(config: ServerConfig) async throws -> SystemStats {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanWorkflow(config: ServerConfig) async throws -> KanbanWorkflow {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanBoards(config: ServerConfig) async throws -> [String] {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanBoard(
        config: ServerConfig, board: String
    ) async throws -> KanbanBoardSnapshot {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanTaskDetail(
        config: ServerConfig, board: String, id: String
    ) async throws -> KanbanTaskDetail {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanCreateTask(
        config: ServerConfig, board: String, title: String, body: String,
        idempotencyKey: String
    ) async throws -> KanbanTask {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanDispatch(
        config: ServerConfig, board: String
    ) async throws -> KanbanDispatchReceipt {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanPatchTaskStatus(
        config: ServerConfig, board: String, id: String, status: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanDeleteTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanComment(
        config: ServerConfig, board: String, id: String, body: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanReclaimTask(
        config: ServerConfig, board: String, id: String
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }

    func kanbanTerminateRun(
        config: ServerConfig, board: String, runID: Int
    ) async throws {
        throw HermesError.unreachable("离线桩")
    }
}
