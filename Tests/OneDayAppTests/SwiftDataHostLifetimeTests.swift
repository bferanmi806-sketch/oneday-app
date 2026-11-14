import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §184 回归：容器租约的生命周期不变量（2026-11-15）。
///
/// 崩溃本身是竞态、无法在单测里确定性复现（复现即杀宿主、
/// 无法断言）——本文件钉三条可确定性断言的不变量：
/// ①挂载树先于容器释放（弱引用时序）；②多轮挂载／拆卸
/// 循环后异容器 save 不触发已销毁实例访问；③拆卸后新容器
/// 的播种＋save（seedThreads 同形）干净落盘。
/// 旧顺序（容器只存方法局部、方法返回即释放）下测试 1 的
/// 弱引用断言直接失败——回归判据不依赖竞态重现。
/// 最终证据仍是 CI 全轮：四条无终局用例恢复终局、宿主零重启。
@MainActor
final class SwiftDataHostLifetimeTests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: UIWindow!
    private var swiftDataMount = SwiftDataTestMount()

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    /// 播种一对线程（主线＋旁聊，同 ChatReliabilityOfflineTests
    /// 的 p1／p2 形态——崩溃里被销毁的恒为 p2 旁聊线程）。
    private func seedThreads(
        in container: ModelContainer
    ) throws -> (main: ChatThread, side: ChatThread) {
        let context = ModelContext(container)
        let main = ChatThread(title: "主线")
        let side = ChatThread(title: "旁聊")
        context.insert(main)
        context.insert(side)
        let entry = ChatEntry(
            role: "user", content: "回归标记", thread: main
        )
        context.insert(entry)
        try context.save()
        return (main, side)
    }

    private func mountRootView(
        container: ModelContainer, appState: AppState
    ) -> UIHostingController<AnyView> {
        swiftDataMount.retain(container)
        let host = UIHostingController(
            rootView: AnyView(
                RootView()
                    .environment(appState)
                    .environment(\.locale, AppLocale.uiLocale)
                    .modelContainer(container)
            )
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.5)
        window.layoutIfNeeded()
        return host
    }

    /// 弱引用在限时内变 nil（轮询至多 2s）：析构本就是同步
    /// 引用计数归零，限时只防偶发滞后，不放水。
    private func waitForNil<T: AnyObject>(
        _ ref: @autoclosure () -> T?,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(2)
        while ref() != nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNil(
            ref(), "弱引用应在限时内释放", file: file, line: line
        )
    }

    // MARK: - 不变量 1：挂载树先于容器释放

    func testContainerOutlivesMountedTree() async throws {
        weak var weakHost: UIHostingController<AnyView>?
        weak var weakContainer: ModelContainer?
        do {
            var container: ModelContainer? = try makeContainer()
            let seeded = try seedThreads(in: container!)
            let appState = AppState(
                client: DemoHermesClient(), demoMode: .connected
            )
            appState.sideChats.designateMainThread(seeded.main.id)
            appState.sideChats.setLastThreadID(seeded.main.id)
            var host: UIHostingController<AnyView>? =
                mountRootView(container: container!, appState: appState)
            weakHost = host
            weakContainer = container
            XCTAssertNotNil(weakHost, "挂载后宿主应存活")
            XCTAssertNotNil(weakContainer, "挂载后容器应存活")

            // 先拆窗、再排空：此时容器仍被租约强持有。
            window.rootViewController = nil
            window.isHidden = true
            window = nil
            host = nil
            try? await Task.sleep(nanoseconds: 600_000_000)
            await waitForNil(weakHost)
            XCTAssertTrue(
                swiftDataMount.isRetained,
                "挂载树拆净时容器必须仍被租约持有——旧顺序下"
                    + "容器随方法返回已释放，此处即为回归红点"
            )
            // 容器仍活：此前播种的 p2 旁聊线程可读、未被 reset 销毁。
            XCTAssertEqual(seeded.side.title, "旁聊")
            do {
                let live = try ModelContext(container!).fetch(
                    FetchDescriptor<ChatThread>()
                )
                XCTAssertEqual(live.count, 2)
            }

            // 再放容器（do 块结束时播种实例与局部容器一并释放）。
            await swiftDataMount.release()
            container = nil
        }
        // 播种实例已出作用域：容器最后引用归零。
        await waitForNil(weakContainer)
    }

    // MARK: - 不变量 2：多轮挂载循环后异容器 save 不杀宿主

    func testRepeatedMountTeardownThenSaveDoesNotTrap() async throws {
        for _ in 0..<8 {
            var container: ModelContainer? = try makeContainer()
            _ = try seedThreads(in: container!)
            let appState = AppState(
                client: DemoHermesClient(), demoMode: .connected
            )
            _ = mountRootView(
                container: container!, appState: appState
            )
            window.rootViewController = nil
            window.isHidden = true
            window = nil
            await swiftDataMount.release()
            container = nil
        }
        // §184 触发器本尊：异容器 save——旧顺序下残留的
        // 挂载树观察者在此拍被唤醒、触已销毁线程即崩溃；
        // 租约排空后旧树已拆净，此 save 必须干净落盘。
        let fresh = try makeContainer()
        let context = ModelContext(fresh)
        let thread = ChatThread(title: "新会话")
        context.insert(thread)
        try context.save()
        let fetched = try ModelContext(fresh).fetch(
            FetchDescriptor<ChatThread>()
        )
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "新会话")
    }

    // MARK: - 不变量 3：拆卸后新容器的播种＋save 同形干净

    func testSeedSaveAfterTeardownDoesNotTrap() async throws {
        var container: ModelContainer? = try makeContainer()
        _ = try seedThreads(in: container!)
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        _ = mountRootView(container: container!, appState: appState)
        window.rootViewController = nil
        window.isHidden = true
        window = nil
        await swiftDataMount.release()
        container = nil

        // seedThreads 同形（主／旁聊双线程＋save）：R2／R3
        // 的崩溃即发生在此拍的通知投递里。
        let fresh = try makeContainer()
        let seeded = try seedThreads(in: fresh)
        XCTAssertEqual(seeded.main.title, "主线")
        XCTAssertEqual(seeded.side.title, "旁聊")
        let fetched = try ModelContext(fresh).fetch(
            FetchDescriptor<ChatThread>()
        )
        XCTAssertEqual(fetched.count, 2)
    }
}
