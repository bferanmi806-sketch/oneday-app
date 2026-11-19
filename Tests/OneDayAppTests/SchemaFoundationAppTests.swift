import Foundation
import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 本地库版本迁移地基（根治版包 3，DESIGN §332；
/// 待办第 122 条 G-05）验收钉测：
/// ①V1 指纹＝已发布库指纹（与裸 Schema 逐实体逐
/// 属性一致＋存储属性全集钉死，原地改模型必红）；
/// ②V1 形态旧库经迁移链工厂打开零迁移零丢失＋
/// 迁移前备份存在且可打开；③备份轮转保留 2 组；
/// ④打开失败注入→降级明示＋留痕＋原文件与备份
/// 都保留，不许静默吞、不许装作空库；
/// ⑤侧账解码失败→留痕＋人话提示＋自愈标记，消
/// 费时真走重新发现（改认失效指针/目录不可达保
/// 留提示），键缺席不算失败、健康状态不误报。
/// §184 容器租约：本类全部容器经 SwiftDataTest-
/// Mount 进程级持有、永不释放（文件库落临时目录）
@MainActor
final class SchemaFoundationAppTests: XCTestCase {

    private var swiftDataMount = SwiftDataTestMount()
    private let queueKey = "sessionDeletions.pendingQueue"
    private var suites: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: queueKey)
        for suite in suites {
            UserDefaults.standard.removePersistentDomain(
                forName: suite
            )
        }
        suites = []
        await swiftDataMount.release()
        try await super.tearDown()
    }

    // MARK: - 装配辅助

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "schema-foundation-\(UUID().uuidString)"
            )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private func scratchDefaults() -> UserDefaults {
        let suite = "schema-foundation-\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func copyStoreSet(
        from source: URL, to destination: URL
    ) throws {
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(
                fileURLWithPath: source.path + suffix
            )
            if FileManager.default.fileExists(atPath: src.path) {
                try FileManager.default.copyItem(
                    at: src,
                    to: URL(
                        fileURLWithPath: destination.path + suffix
                    )
                )
            }
        }
    }

    // MARK: - ① V1 指纹

    func testV1FingerprintMatchesPublishedSchema() {
        let plain = Schema([ChatThread.self, ChatEntry.self])
        let versioned = Schema(
            versionedSchema: ChatSchemaV1.self
        )
        XCTAssertEqual(
            Set(plain.entities.map(\.name)),
            Set(versioned.entities.map(\.name))
        )
        for entity in plain.entities {
            let counterpart = versioned.entities.first {
                $0.name == entity.name
            }
            XCTAssertNotNil(counterpart, entity.name)
            XCTAssertEqual(
                Set(entity.properties.map(\.name)),
                Set(counterpart?.properties.map(\.name) ?? []),
                entity.name
            )
        }
        XCTAssertEqual(
            ChatSchemaV1.versionIdentifier, Schema.Version(1, 0, 0)
        )
        XCTAssertEqual(ChatSchemaV1.versionTag, "1.0.0")
        XCTAssertEqual(ChatMigrationPlan.schemas.count, 1)
        XCTAssertTrue(ChatMigrationPlan.stages.isEmpty)

        // 存储属性全集钉死：原地改 V1 模型（加/删/
        // 改名字段）必然在此触发红——冻结的机械守卫
        let allowedExtras: Set<String> = [
            "entries", "thread",
            "toolCardCacheValue", "toolCardCacheSource",
        ]
        let threadProps = Set(
            versioned.entities
                .first { $0.name == "ChatThread" }?
                .properties.map(\.name) ?? []
        )
        let expectedThread: Set<String> = [
            "id", "title", "createdAt", "updatedAt",
            "isPinned", "serverSessionID", "titleIsManual",
            "linkFailureCount", "linkLastError", "linkedModel",
            "serverSeeded", "historyUnsynced",
            "historyServerCount", "historyLoadedCount",
            "seedSyncStateRaw", "isPendingDeletion",
        ]
        XCTAssertTrue(
            expectedThread.isSubset(of: threadProps),
            "ChatThread 缺属性：\(expectedThread.subtracting(threadProps))"
        )
        XCTAssertTrue(
            threadProps.subtracting(expectedThread)
                .isSubset(of: allowedExtras),
            "ChatThread 多出未登记属性：\(threadProps.subtracting(expectedThread))"
        )
        let entryProps = Set(
            versioned.entities
                .first { $0.name == "ChatEntry" }?
                .properties.map(\.name) ?? []
        )
        let expectedEntry: Set<String> = [
            "id", "role", "content", "imageData",
            "imageDatasData", "quoteRole", "quoteContent",
            "feedPostID", "feedPostTitle", "feedPostBody",
            "feedPostSource", "ideaQuoteID", "ideaQuoteTitle",
            "ideaQuoteBody", "fileQuoteName", "fileQuotePath",
            "goalQuoteCategory", "reasoning", "reasoningSeconds",
            "toolCardData", "remoteImagePathsData",
            "remoteFilePathsData", "echoKey", "approvalKey",
            "traceKey", "traceEchoData", "sendFailed",
            "sendStateRaw", "deliveryState", "createdAt",
        ]
        XCTAssertTrue(
            expectedEntry.isSubset(of: entryProps),
            "ChatEntry 缺属性：\(expectedEntry.subtracting(entryProps))"
        )
        XCTAssertTrue(
            entryProps.subtracting(expectedEntry)
                .isSubset(of: allowedExtras),
            "ChatEntry 多出未登记属性：\(entryProps.subtracting(expectedEntry))"
        )
    }

    // MARK: - ② V1 旧库经迁移链打开＋备份实证

    func testV1StoreOpensThroughMigrationChainWithZeroLoss()
        throws {
        let dir = try tempDir()
        let sourceURL = dir.appendingPathComponent("default.store")
        // .69 形态：裸 Schema、无迁移计划建库写数
        let plainSchema = Schema([ChatThread.self, ChatEntry.self])
        let writer = try ModelContainer(
            for: plainSchema,
            configurations: [ModelConfiguration(
                schema: plainSchema, url: sourceURL
            )]
        )
        swiftDataMount.retain(writer)
        let writeContext = ModelContext(writer)
        let thread = ChatThread(title: "旧库主线")
        thread.serverSessionID = "srv-main-69"
        thread.isPinned = true
        thread.linkFailureCount = 2
        writeContext.insert(thread)
        writeContext.insert(
            ChatEntry(role: "user", content: "第一条", thread: thread)
        )
        writeContext.insert(
            ChatEntry(
                role: "assistant", content: "第二条", thread: thread
            )
        )
        try writeContext.save()

        // 旧库文件复制一份作演练面（文件本体即 .69
        // 库形态），经新工厂（备份＋迁移链）打开
        let drillURL = dir.appendingPathComponent("drill.store")
        try copyStoreSet(from: sourceURL, to: drillURL)
        let bootstrap = ChatModelContainerBootstrapFactory
            .makePersistent(storeURL: drillURL)
        XCTAssertFalse(bootstrap.usesFallback)
        XCTAssertNil(bootstrap.failureMessage)
        let container = try XCTUnwrap(bootstrap.container)
        swiftDataMount.retain(container)

        let context = ModelContext(container)
        let threads = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        let entries = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(entries.count, 2)
        let opened = try XCTUnwrap(threads.first)
        XCTAssertEqual(opened.title, "旧库主线")
        XCTAssertEqual(opened.serverSessionID, "srv-main-69")
        XCTAssertTrue(opened.isPinned)
        XCTAssertEqual(opened.linkFailureCount, 2)
        XCTAssertEqual(
            Set(entries.map(\.content)), ["第一条", "第二条"]
        )

        // 迁移前备份实证：备份在册且可按原库方式打开
        let backupURL = try XCTUnwrap(bootstrap.backupStoreURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path)
        )
        XCTAssertTrue(
            backupURL.lastPathComponent
                .contains("drill.store.backup-1.0.0-")
        )
        let backupContainer = try ModelContainer(
            for: plainSchema,
            configurations: [ModelConfiguration(
                schema: plainSchema, url: backupURL
            )]
        )
        swiftDataMount.retain(backupContainer)
        let backupContext = ModelContext(backupContainer)
        XCTAssertEqual(
            try backupContext.fetch(
                FetchDescriptor<ChatThread>()
            ).count,
            1
        )
        XCTAssertEqual(
            try backupContext.fetch(
                FetchDescriptor<ChatEntry>()
            ).count,
            2
        )
    }

    // MARK: - ③ 备份轮转

    func testStoreBackupRotationKeepsNewestTwo() throws {
        let dir = try tempDir()
        let storeURL = dir.appendingPathComponent("default.store")
        // 首装无库：不备份、不建文件
        let absent = try ChatStoreBackup.backupStoreIfPresent(
            at: storeURL, versionTag: "1.0.0",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertNil(absent)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.path)
        )

        try Data("store-bytes".utf8).write(to: storeURL)
        var returned: [URL] = []
        for offset in [0, 60, 120] {
            let backup = try ChatStoreBackup
                .backupStoreIfPresent(
                    at: storeURL, versionTag: "1.0.0",
                    now: Date(
                        timeIntervalSince1970: 1_700_000_000
                            + TimeInterval(offset)
                    )
                )
            returned.append(try XCTUnwrap(backup))
        }
        // 保留最近 2 组：最旧一组已被轮转删净
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: returned[0].path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: returned[1].path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: returned[2].path
            )
        )
        let names = try FileManager.default
            .contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(
            names.filter { $0.contains(".backup-") }.count, 2
        )
        XCTAssertEqual(
            try Data(contentsOf: returned[2]),
            Data("store-bytes".utf8)
        )
    }

    // MARK: - ④ 打开失败注入

    func testCorruptStoreFallsBackKeepsOriginalAndBackup()
        throws {
        let dir = try tempDir()
        let storeURL = dir.appendingPathComponent("default.store")
        let garbage = Data("this-is-not-a-sqlite-store".utf8)
        try garbage.write(to: storeURL)

        let bootstrap = ChatModelContainerBootstrapFactory
            .makePersistent(storeURL: storeURL)

        // 降级明示：内存库在场能开界面、提示点名原
        // 记录没删＋备份已保留，不许静默装作空库
        XCTAssertTrue(bootstrap.usesFallback)
        let container = try XCTUnwrap(bootstrap.container)
        swiftDataMount.retain(container)
        let message = try XCTUnwrap(bootstrap.failureMessage)
        XCTAssertTrue(message.contains("原来的记录没有删除"))
        XCTAssertTrue(message.contains("打开前的备份已保留"))
        // 原文件保留不删、字节不动
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage)
        // 备份在册（回滚点）
        let backupURL = try XCTUnwrap(bootstrap.backupStoreURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path)
        )
        // 失败留痕（痕文案为本包新增、全局查在册即证）
        XCTAssertTrue(
            ChatDiagTrace.snapshots.contains {
                $0.contains("本地库打开失败")
            }
        )
    }

    // MARK: - ⑤ 解码失败可见＋自愈触发

    func testCorruptClaimRecordSurfacesAndSchedulesRediscovery() {
        let defaults = scratchDefaults()
        defaults.set(
            Data("garbage".utf8), forKey: "sideChats.mainClaimRecord"
        )

        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )

        XCTAssertNil(ledger.mainClaimRecord)
        let note = ledger.localStateReadFailureNote
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("本地状态读取失败") == true)
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)
        XCTAssertTrue(
            ChatDiagTrace.snapshots.contains {
                $0.contains("本地状态读取失败")
                    && $0.contains("sideChats.mainClaimRecord")
            }
        )
    }

    func testCorruptAssociationTableSurfaces() {
        let defaults = scratchDefaults()
        defaults.set(
            Data("[not-a-dict".utf8),
            forKey: "sideChats.ideaThreadIDs"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertEqual(ledger.ideaThreadIDs, [:])
        XCTAssertNotNil(ledger.localStateReadFailureNote)
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)
    }

    func testCorruptMainThreadIDStringSurfaces() {
        let defaults = scratchDefaults()
        defaults.set(
            "not-a-uuid", forKey: "sideChats.mainThreadID"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertNil(ledger.mainThreadID)
        XCTAssertNotNil(ledger.localStateReadFailureNote)
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)
    }

    func testHealthyAndMissingStatesStayQuiet() throws {
        // 键缺席＝从未写过：不算失败、不误报
        let fresh = SessionLedger(
            defaults: scratchDefaults(),
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertNil(fresh.localStateReadFailureNote)
        XCTAssertFalse(fresh.stateReadFailurePendingRediscovery)

        // 健康在册值：正常读出、无提示无标记
        let defaults = scratchDefaults()
        let record = MainlineClaimRecord(
            sessionID: "srv-1", messageCount: 3,
            lastActivityAt: nil, isArchived: false,
            candidateCount: 1, claimedAt: 100
        )
        defaults.set(
            try JSONEncoder().encode(record),
            forKey: "sideChats.mainClaimRecord"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertEqual(ledger.mainClaimRecord?.sessionID, "srv-1")
        XCTAssertNil(ledger.localStateReadFailureNote)
        XCTAssertFalse(ledger.stateReadFailurePendingRediscovery)
    }

    // MARK: - 自愈消费（脚本目录）

    private func sessionJSON(
        id: String, title: String?, messageCount: Int?,
        archived: Bool
    ) -> String {
        var fields = ["\"id\":\"\(id)\""]
        if let title { fields.append("\"title\":\"\(title)\"") }
        if let messageCount {
            fields.append("\"message_count\":\(messageCount)")
        }
        fields.append("\"archived\":\(archived ? 1 : 0)")
        fields.append("\"started_at\":1000")
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func makePage(
        sessions: [String], total: Int
    ) -> SessionsPage {
        let json = "{\"sessions\":["
            + sessions.joined(separator: ",")
            + "],\"total\":\(total)}"
        return try! JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
    }

    func testRediscoveryAfterFailureReclaimsStalePointer()
        async {
        let defaults = scratchDefaults()
        defaults.set(
            Data("garbage".utf8), forKey: "sideChats.mainClaimRecord"
        )
        defaults.set(
            "srv-stale", forKey: "sideChats.mainServerSessionID"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)
        XCTAssertEqual(ledger.mainServerSessionID, "srv-stale")

        var client = ScriptedSessionsClient()
        client.scriptedPages = [
            "include|0": makePage(
                sessions: [
                    sessionJSON(
                        id: "srv-real",
                        title: SideChatStore.mainTitle,
                        messageCount: 10, archived: false
                    ),
                ],
                total: 1
            ),
        ]
        let appState = AppState(
            client: client, demoMode: .connected
        )

        await ledger.rediscoverAfterStateReadFailure(
            appState: appState
        )

        // 失效指针被改认到目录里的真主线、认领记录
        // 重建、提示清除、标记消费——自愈全程实证
        XCTAssertEqual(ledger.mainServerSessionID, "srv-real")
        XCTAssertEqual(ledger.mainClaimRecord?.sessionID, "srv-real")
        XCTAssertNil(ledger.localStateReadFailureNote)
        XCTAssertFalse(ledger.stateReadFailurePendingRediscovery)
    }

    func testRediscoveryAfterFailureKeepsNoteWhenDirectoryDown()
        async {
        let defaults = scratchDefaults()
        defaults.set(
            Data("garbage".utf8), forKey: "sideChats.mainClaimRecord"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)

        // 无脚本页＝目录拉取失败（桩抛 unreachable）
        let appState = AppState(
            client: ScriptedSessionsClient(),
            demoMode: .connected
        )
        await ledger.rediscoverAfterStateReadFailure(
            appState: appState
        )

        // 标记已消费（不反复重拉），提示保留待下次
        // 启动再对账，失败原因另落链接错误位留痕
        XCTAssertFalse(ledger.stateReadFailurePendingRediscovery)
        XCTAssertNotNil(ledger.localStateReadFailureNote)
        XCTAssertNotNil(ledger.mainLinkLastError)
    }
}
