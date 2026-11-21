import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 195 验收断言：引用条出现前后——输入舱位移
/// 量 vs 条实高的等式关系，键盘收起/弹起两态各钉
/// 一遍。诊断轮实测（run 44843567900，探针版）：
/// 静息态 growth=61.0／topDisp=61.0／bottomDrift
/// =0.0、文本视图 y 不变——条在卡内生长区落位、
/// 输入行底锚不动。本测试把该等式钉成可复测断言：
///   舱生长 == 卡生长 == 舱顶上移 == 条槽实高
///   舱底漂移 == 0、输入行（文本视图）位移 == 0
///   撤引用后舱高与舱底回基线、槽离场
/// 装配＝生产全装配（RootView＋原生面默认开）＋
/// AppState 待发引用表驱动引用槽（feed 变体与消息
/// 变体同槽同几何，见 ChatView composerCard §332
/// 槽位：条本体＋1pt 发丝线直挂卡根）。
@MainActor
final class ChatQuoteDock195Tests: XCTestCase {

    private var window: UIWindow!
    private var container: ModelContainer!
    private var appState: AppState!
    private var swiftDataMount = SwiftDataTestMount()
    private var threadID: UUID!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let context = ModelContext(container)
        let thread = ChatThread(title: "量测会话")
        context.insert(thread)
        context.insert(ChatEntry(
            role: "user", content: "在吗", thread: thread
        ))
        context.insert(ChatEntry(
            role: "assistant", content: "在的。", thread: thread
        ))
        try? context.save()
        threadID = thread.id
        appState.sideChats.setLastThreadID(thread.id)
    }

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        appState = nil
        container = nil
        try await super.tearDown()
    }

    private func spin(seconds: TimeInterval) {
        let exp = expectation(description: "spin")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func spinUntil(
        timeout: TimeInterval, _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            spin(seconds: 0.25)
        }
        return condition()
    }

    private func mountShell() {
        let host = UIHostingController(
            rootView: AnyView(
                RootView()
                    .environment(appState)
                    .environment(\.locale, AppLocale.uiLocale)
                    .modelContainer(container)
            )
        )
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
        }
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    private func findRootVC() -> ChatRootViewController? {
        var found: ChatRootViewController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? ChatRootViewController {
                found = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window?.rootViewController { walk(root) }
        return found
    }

    private func hostFrame() -> CGRect? {
        guard let host = findRootVC()?.composerHost
        else { return nil }
        return host.view.convert(host.view.bounds, to: window)
    }

    /// 等帧落定：两读（间隔 0.4s）三值差 ≤0.5
    private func stableHostFrame(
        timeout: TimeInterval = 10
    ) -> CGRect? {
        var previous = hostFrame()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            spin(seconds: 0.4)
            let current = hostFrame()
            if let p = previous, let c = current,
               abs(p.minY - c.minY) <= 0.5,
               abs(p.height - c.height) <= 0.5,
               abs(p.maxY - c.maxY) <= 0.5 {
                return c
            }
            previous = current
        }
        return hostFrame()
    }

    private func findViews(
        _ root: UIView, where matches: (UIView) -> Bool
    ) -> [UIView] {
        var out: [UIView] = []
        if matches(root) { out.append(root) }
        for sub in root.subviews {
            out += findViews(sub, where: matches)
        }
        return out
    }

    /// 舱内玻璃卡帧（卡层 glassEffect 的平台玻璃
    /// 视图，宽 >300；与组装探针同找法）
    private func cardFrame() -> CGRect? {
        guard let host = findRootVC()?.composerHost
        else { return nil }
        return findViews(host.view) { view in
            String(describing: type(of: view))
                .contains("UIPlatformGlassInteractionView")
                && view.convert(view.bounds, to: window)
                    .width > 300
        }.first.map { $0.convert($0.bounds, to: window) }
    }

    /// 舱内输入文本视图帧（「输入框」本体）
    private func textViewFrame() -> CGRect? {
        guard let host = findRootVC()?.composerHost
        else { return nil }
        return findViews(host.view) { $0 is UITextView }
            .first.map { $0.convert($0.bounds, to: window) }
    }

    /// 引用槽在场直查：条标题标签（feedQuoteBar
    /// 渲染帖题）是否在舱层级内
    private func quoteSlotPresent() -> Bool {
        guard let host = findRootVC()?.composerHost
        else { return false }
        return findViews(host.view) { view in
            (view as? UILabel)?.text?.contains("量测帖标题")
                ?? false
        }.isEmpty == false
    }

    private func postKeyboard(
        name: Notification.Name, top: CGFloat,
        duration: Double
    ) {
        NotificationCenter.default.post(
            name: name, object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: CGRect(
                        x: 0, y: top, width: 402,
                        height: 874 - top
                    )),
                UIResponder
                    .keyboardAnimationDurationUserInfoKey:
                    NSNumber(value: duration),
                UIResponder
                    .keyboardAnimationCurveUserInfoKey:
                    NSNumber(value: 7),
            ]
        )
    }

    private func quoteTargetIDs() -> [UUID] {
        var ids = [threadID!]
        if let main = appState.sessionLedger.mainThreadID,
           main != threadID {
            ids.append(main)
        }
        return ids
    }

    private func setQuote(_ on: Bool) {
        let post = BridgeFeedPost(
            id: "probe195-post", kind: .research,
            title: "量测帖标题",
            body: "量测帖正文摘要。",
            direction: "Rig",
            createdAt: Date().timeIntervalSince1970,
            emoji: "🤖"
        )
        for id in quoteTargetIDs() {
            appState.pendingQuotes
                .feedQuotesByThread[id] =
                on ? FeedPostQuote(post: post) : nil
        }
    }

    private func fmt(_ r: CGRect?) -> String {
        guard let r else { return "nil" }
        return String(
            format: "(y=%.1f h=%.1f maxY=%.1f)",
            r.minY, r.height, r.maxY
        )
    }

    /// 等式断言组（两态共用）：基线帧→引用帧→撤回帧
    /// bottomTolerance：键盘态容忍键盘帧重申的整舱
    /// 微移（诊断轮见 -2.0 的整舱同移：舱/卡/文本
    /// 三帧同量，非引用几何）；静息态严判 0.6。
    private func assertQuoteDockEqualities(
        state: String, bottomTolerance: CGFloat
    ) {
        XCTAssertTrue(
            spinUntil(timeout: 12) {
                findRootVC()?.composerHost != nil
            },
            "\(state)：原生面舱宿主未装配"
        )
        XCTAssertFalse(
            quoteSlotPresent(),
            "\(state)：基线不应有引用槽"
        )
        let base = stableHostFrame()
        let baseCard = cardFrame()
        let baseText = textViewFrame()
        XCTAssertNotNil(base, "\(state)：基线舱帧未取得")

        setQuote(true)
        XCTAssertTrue(
            spinUntil(timeout: 10) { quoteSlotPresent() },
            "\(state)：引用槽未在场"
        )
        let quoted = stableHostFrame()
        let quotedCard = cardFrame()
        let quotedText = textViewFrame()
        print(
            "QUOTE195 \(state) base host=\(fmt(base))"
                + " card=\(fmt(baseCard))"
                + " text=\(fmt(baseText))"
        )
        print(
            "QUOTE195 \(state) quote host=\(fmt(quoted))"
                + " card=\(fmt(quotedCard))"
                + " text=\(fmt(quotedText))"
        )
        guard let base, let quoted,
              let baseCard, let quotedCard,
              let baseText, let quotedText
        else {
            XCTFail("\(state)：引用态帧未齐")
            return
        }
        // 条槽实高＝卡生长（卡内唯一可生长子级）
        let slotHeight = quotedCard.height - baseCard.height
        XCTAssertGreaterThan(
            slotHeight, 30,
            "\(state)：条槽实高异常（应为一条引用条量级）"
        )
        // 等式一：舱生长 == 条槽实高
        XCTAssertEqual(
            quoted.height - base.height, slotHeight,
            accuracy: 0.6,
            "\(state)：舱生长≠条槽实高（多抬/少抬）"
        )
        // 等式二：舱顶上移 == 条槽实高
        XCTAssertEqual(
            base.minY - quoted.minY, slotHeight,
            accuracy: 0.6,
            "\(state)：舱顶上移≠条槽实高"
        )
        // 等式三：舱底不漂（底锚钉住）
        XCTAssertEqual(
            quoted.maxY - base.maxY, 0,
            accuracy: bottomTolerance,
            "\(state)：舱底漂移（底锚未钉住）"
        )
        // 等式四：输入行不位移（生长全在输入行之上）
        XCTAssertEqual(
            quotedText.minY - baseText.minY,
            quoted.maxY - base.maxY,
            accuracy: 0.6,
            "\(state)：输入行相对舱底发生位移"
        )
        // 撤引用：槽离场、舱高与舱底回基线
        setQuote(false)
        XCTAssertTrue(
            spinUntil(timeout: 10) { !quoteSlotPresent() },
            "\(state)：撤引用后槽未离场"
        )
        let back = stableHostFrame()
        print(
            "QUOTE195 \(state) back host=\(fmt(back))"
                + " tableCount="
                + "\(appState.pendingQuotes"
                + ".feedQuotesByThread.count)"
                + " slotPresent=\(quoteSlotPresent())"
        )
        guard let back else {
            XCTFail("\(state)：撤回帧未取得")
            return
        }
        XCTAssertEqual(
            back.height, base.height, accuracy: 0.6,
            "\(state)：撤引用后舱高未回基线"
        )
        XCTAssertEqual(
            back.maxY, base.maxY, accuracy: bottomTolerance,
            "\(state)：撤引用后舱底未回基线"
        )
    }

    /// 静息态（键盘收起，189 入流锚）：严判
    func testRestingStateQuoteDisplacementEqualsStripHeight() {
        mountShell()
        assertQuoteDockEqualities(
            state: "REST", bottomTolerance: 0.6
        )
    }

    /// 键盘态（合成键盘帧顶 541，§194 单常数链）：
    /// 底漂容忍键盘重申整舱微移 2.5，其余等式严判
    func testKeyboardStateQuoteDisplacementEqualsStripHeight() {
        mountShell()
        XCTAssertTrue(
            spinUntil(timeout: 12) {
                findRootVC()?.composerHost != nil
            },
            "KB：原生面舱宿主未装配"
        )
        postKeyboard(
            name: UIResponder.keyboardWillShowNotification,
            top: 541, duration: 0
        )
        _ = stableHostFrame()
        assertQuoteDockEqualities(
            state: "KB", bottomTolerance: 2.5
        )
        postKeyboard(
            name: UIResponder.keyboardWillHideNotification,
            top: 874, duration: 0
        )
        _ = stableHostFrame()
    }
}
