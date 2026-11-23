import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §419（修复包二·生成中排队）钉测。
///
/// 可达面口径与 §414 钉同源（见 ChatFailKeepPinTests
/// 文件头实证）：托管单测环境供不出 SwiftUI 无障碍
/// 元素，send() 本体与右端钮点按在挂载环境不可达——
/// 本套钉其消费面与模型面，行为话逐钉如下：
/// 钉一（Q2＋Q7）：上一轮落定后，排队落位的两条
/// （发送状态 .queued＋待发双写，与 send() 账本分
/// 支落盘形态逐字同）被串行出口按先来后到逐条真
/// 发——后一条被派发时前一条必已落定收尾（同会话
/// 至多一轮在飞），两条的幂等键派发前后一字不变、
/// 各只被自动派发一次、失败后原位落失败态（同 id
/// 同序位、总数不变）。
/// 钉二（Q1 消费面＋Q5 账本半边）：上一轮账本未落
/// 定（结果未知对账中）时，排队条目原地不动——不
/// 被抢发、无自动尝试记账、排队身份不变。
/// 钉三（Q4 落定形态）：排队条目原位编辑——正文
/// 覆写、id／创建时间／排队状态／幂等键全不动
/// （§414 路三同原语，排队态同样成立）。
/// 钉四（Q8 模型面）：排队条目落盘后以全新上下文
/// 回读，排队态＋待发＋未确认三谓词如实还原（冷启
/// 恢复与对账未清前不投递的存储面前提）。
/// 钉五（Q9 常量面）：贴底判定容差常量 == 48pt。
/// 列真机门（DESIGN §419）：Q1 的 send() 落位本体
/// 与双钮点按、Q3 撤回、Q5 同拍双触发、Q6 停止保
/// 队列、Q9 行为面（47/96pt）、Q10 在屏行高——挂
/// 载环境不可达或须真轮驱动，理由见 §419。
@MainActor
final class ChatQueueSendPinTests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    private let swiftDataMount = SwiftDataTestMount()
    private weak var ledgerStore: RunLedgerStore?
    private var ledgerThreadIDs: [UUID] = []
    private weak var connectedState: AppState?

    override func tearDown() {
        if let ledgerStore {
            for threadID in ledgerThreadIDs {
                ledgerStore.remove(threadID: threadID)
            }
        }
        ledgerThreadIDs = []
        ledgerStore = nil
        connectedState?.disconnect()
        connectedState = nil
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// 真挂起等待（口径同 §414 钉：同步自旋会饿死
    /// 被测 App 的 MainActor 任务，等待必须让拍）
    private func spinRunLoop(seconds: TimeInterval) async {
        try? await Task.sleep(
            nanoseconds: UInt64(seconds * 1_000_000_000)
        )
    }

    private func pollUntil(
        seconds: TimeInterval, _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            await spinRunLoop(seconds: 0.25)
        }
        return condition()
    }

    // MARK: - 装配与播种（与 §414 钉同装配）

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    @discardableResult
    private func seedThread(
        in container: ModelContainer,
        entries: [(role: String, content: String)]
    ) throws -> ChatThread {
        let context = ModelContext(container)
        let thread = ChatThread(title: "排队钉测线程")
        context.insert(thread)
        let base = Date(timeIntervalSince1970: 1_763_000_000)
        for (index, item) in entries.enumerated() {
            let entry = ChatEntry(
                role: item.role, content: item.content,
                thread: thread
            )
            entry.createdAt = base.addingTimeInterval(
                Double(index) * 10
            )
            context.insert(entry)
        }
        try context.save()
        return thread
    }

    private func mountRoot(
        container: ModelContainer, appState: AppState
    ) async {
        swiftDataMount.retain(container)
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        await spinRunLoop(seconds: 4.0)
        window.layoutIfNeeded()
        await spinRunLoop(seconds: 0.8)
        window.layoutIfNeeded()
    }

    private func makeConnectedAppState(
        mainThreadID: UUID
    ) async throws -> AppState {
        let appState = AppState(
            client: CountingCatalogClient(
                recorder: CatalogCallRecorder()
            ),
            demoMode: .off
        )
        appState.sessionLedger.designateMainThread(mainThreadID)
        appState.sideChats.setLastThreadID(mainThreadID)
        ledgerStore = appState.runLedger
        connectedState = appState
        try await appState.connectDirect(
            config: try XCTUnwrap(
                ServerConfig(rawInput: "https://queuepin.test")
            ),
            apiKey: "queue-pin-test-key"
        )
        return appState
    }

    private func readEntries(
        in container: ModelContainer, threadID: UUID
    ) throws -> [ChatEntry] {
        let context = ModelContext(container)
        let threads = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        guard let thread = threads.first(
            where: { $0.id == threadID }
        ) else { return [] }
        return thread.sortedEntries
    }

    /// 播种：一问一答已落定＋两条排队落位（落位形
    /// 态与 send() 账本分支逐字同：markSendState
    /// (.queued) 后 markPendingSend 双写；幂等键预置
    /// 为首投铸造后的恒定值形态）
    private func seedQueueScene(
        in container: ModelContainer
    ) throws -> (
        thread: ChatThread, firstID: UUID, secondID: UUID
    ) {
        let thread = try seedThread(in: container, entries: [
            ("user", "排队钉已落定问句"),
            ("assistant", "排队钉已落定答复"),
            ("user", "排队钉甲"),
            ("user", "排队钉乙"),
        ])
        let context = ModelContext(container)
        let seeded = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        let first = try XCTUnwrap(
            seeded.first { $0.content == "排队钉甲" }
        )
        let second = try XCTUnwrap(
            seeded.first { $0.content == "排队钉乙" }
        )
        first.clientMessageID = "queue-pin-msg-a"
        second.clientMessageID = "queue-pin-msg-b"
        for entry in [first, second] {
            entry.markSendState(.queued, in: context)
            entry.markPendingSend(in: context)
        }
        try context.save()
        return (thread, first.id, second.id)
    }

    // MARK: - 钉一：落定后 FIFO 串行派发＋幂等键恒定

    func testQueuedEntriesDispatchFIFOWithStableIDs()
        async throws
    {
        let container = try makeContainer()
        let scene = try seedQueueScene(in: container)
        let appState = try await makeConnectedAppState(
            mainThreadID: scene.thread.id
        )
        await mountRoot(container: container, appState: appState)

        // 串行不变量：乙被派发的那一拍，甲必已落定
        // （drain 逐条 await 本轮 sendTask 才动下一条）
        var firstLandedBeforeSecondAttempt = false
        let secondAttempted = await pollUntil(seconds: 15) {
            let entries = (try? readEntries(
                in: container, threadID: scene.thread.id
            )) ?? []
            let firstFailed = entries.first {
                $0.id == scene.firstID
            }?.sendFailed == true
            let secondAttempts = appState.outboxRetry
                .record(for: scene.secondID)?.attempts ?? 0
            if secondAttempts >= 1 {
                firstLandedBeforeSecondAttempt = firstFailed
                return true
            }
            return false
        }
        XCTAssertTrue(
            secondAttempted, "排队第二条未被串行出口派发"
        )
        XCTAssertTrue(
            firstLandedBeforeSecondAttempt,
            "第二条派发时第一条尚未落定——串行不变量被破"
        )
        let bothLanded = await pollUntil(seconds: 10) {
            let entries = (try? readEntries(
                in: container, threadID: scene.thread.id
            )) ?? []
            return entries.first {
                $0.id == scene.firstID
            }?.sendFailed == true && entries.first {
                $0.id == scene.secondID
            }?.sendFailed == true
        }
        XCTAssertTrue(
            bothLanded, "排队条目派发后未原位落失败态"
        )
        let entries = try readEntries(
            in: container, threadID: scene.thread.id
        )
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[2].id, scene.firstID)
        XCTAssertEqual(entries[3].id, scene.secondID)
        XCTAssertEqual(
            entries[2].clientMessageID, "queue-pin-msg-a",
            "派发改动了第一条的幂等键"
        )
        XCTAssertEqual(
            entries[3].clientMessageID, "queue-pin-msg-b",
            "派发改动了第二条的幂等键"
        )
        XCTAssertEqual(
            appState.outboxRetry.record(
                for: scene.firstID
            )?.attempts, 1, "第一条被重复派发"
        )
        XCTAssertEqual(
            appState.outboxRetry.record(
                for: scene.secondID
            )?.attempts, 1, "第二条被重复派发"
        )
    }

    // MARK: - 钉二：账本未落定时排队条目原地不动

    func testQueuedEntryHeldWhileLedgerStale() async throws {
        let container = try makeContainer()
        let scene = try seedQueueScene(in: container)
        let appState = try await makeConnectedAppState(
            mainThreadID: scene.thread.id
        )
        let settledID = try XCTUnwrap(
            try readEntries(in: container, threadID: scene.thread.id)
                .first?.id
        )
        appState.runLedger.upsert(RunLedgerEntry(
            threadID: scene.thread.id.uuidString,
            sessionID: "oneday-queue-stale-session",
            runID: nil,
            idempotencyKey: "queue-stale-key",
            userEntryID: settledID.uuidString,
            submittedAt: Date()
        ))
        ledgerThreadIDs = [scene.thread.id]
        await mountRoot(container: container, appState: appState)
        await spinRunLoop(seconds: 2.5)

        XCTAssertNil(
            appState.outboxRetry.record(for: scene.firstID),
            "账本未落定时排队第一条被抢发"
        )
        XCTAssertNil(
            appState.outboxRetry.record(for: scene.secondID),
            "账本未落定时排队第二条被抢发"
        )
        let entries = try readEntries(
            in: container, threadID: scene.thread.id
        )
        XCTAssertEqual(entries.count, 4)
        XCTAssertTrue(entries[2].isPendingSend)
        XCTAssertEqual(entries[2].sendState, .queued)
        XCTAssertTrue(entries[3].isPendingSend)
        XCTAssertEqual(entries[3].sendState, .queued)
    }

    // MARK: - 钉三：排队条目原位编辑保状态

    func testQueuedEntryEditInPlaceKeepsStateAndID() throws {
        let container = try makeContainer()
        let scene = try seedQueueScene(in: container)
        let context = ModelContext(container)
        let fetched = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        let entry = try XCTUnwrap(
            fetched.first { $0.id == scene.firstID }
        )
        let createdAt = entry.createdAt
        entry.applyUnsentEdit(
            content: "排队钉甲改后正文",
            imageDatas: [], quote: nil, sourceQuote: nil,
            in: context
        )
        try context.save()
        let after = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatEntry>())
                .first { $0.id == scene.firstID }
        )
        XCTAssertEqual(after.content, "排队钉甲改后正文")
        XCTAssertEqual(after.createdAt, createdAt)
        XCTAssertEqual(after.sendState, .queued)
        XCTAssertTrue(after.isPendingSend)
        XCTAssertEqual(after.clientMessageID, "queue-pin-msg-a")
    }

    // MARK: - 钉四：排队态落盘回读还原

    func testQueuedStateRestoredFromStorage() throws {
        let container = try makeContainer()
        let scene = try seedQueueScene(in: container)
        // 全新上下文回读（模拟冷启恢复读数）
        let entries = try readEntries(
            in: container, threadID: scene.thread.id
        )
        let restored = try XCTUnwrap(
            entries.first { $0.id == scene.firstID }
        )
        XCTAssertEqual(restored.sendState, .queued)
        XCTAssertTrue(restored.isPendingSend)
        XCTAssertTrue(
            restored.isUnconfirmedSend,
            "排队条目未被呈现面认作未确认发送（浅色＋时钟）"
        )
        XCTAssertTrue(ChatSendState.queued.remainsInQueue)
        XCTAssertTrue(ChatSendState.queued.mayAutoResume)
    }

    // MARK: - 钉五：贴底容差常量

    func testAtBottomToleranceIs48() {
        XCTAssertEqual(
            ChatRootViewController.atBottomTolerance, 48,
            accuracy: 0.001
        )
    }
}
