import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 195 量测探针（诊断轮，结论落定后由正式断言
/// 测试取代）：引用条出现前后——输入舱位移量 vs 条
/// 实高，键盘收起/弹起两态各量一遍。
/// 装配＝生产全装配（RootView＋原生面默认开）＋
/// AppState 待发引用驱动引用槽（feed 变体与消息变
/// 体同槽同几何：左轨 30＋两行 caption＋spacing-
/// Micro＋纵 padding 16＋发丝线 1，见 ChatView
/// quoteBar/feedQuoteBar 本体）。
/// 量法：舱宿主帧（ChatRootViewController.compo-
/// serHost）窗口系三读——生长量（高差）／顶位移
/// （minY 差）／底漂移（maxY 差）；卡玻璃帧与文本
/// 视图帧同帧旁证；静息态另采胶囊顶对 189 锚口径。
@MainActor
final class ChatQuoteDock195ProbeTests: XCTestCase {

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

    private func capsuleTop() -> CGFloat? {
        let bars = findViews(window) { $0 is UITabBar }
        guard let bar = bars.first as? UITabBar,
              let capsule = ChatRootViewController
                .findDockCapsule(in: bar)
        else { return nil }
        return capsule.convert(capsule.bounds, to: window).minY
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

    private func num(_ v: CGFloat?) -> String {
        v.map { String(format: "%.1f", $0) } ?? "nil"
    }

    func testProbe195QuoteDockDisplacement() throws {
        mountShell()
        XCTAssertTrue(
            spinUntil(timeout: 12) {
                findRootVC()?.composerHost != nil
            },
            "原生面舱宿主未装配"
        )
        var lines: [String] = []
        // —— 键盘收起态 ——
        let base = stableHostFrame()
        lines.append(
            "REST noquote host=\(fmt(base))"
                + " card=\(fmt(cardFrame()))"
                + " text=\(fmt(textViewFrame()))"
                + " capsuleTop=\(num(capsuleTop()))"
        )
        setQuote(true)
        let quoted = stableHostFrame()
        lines.append(
            "REST quote host=\(fmt(quoted))"
                + " card=\(fmt(cardFrame()))"
                + " text=\(fmt(textViewFrame()))"
        )
        setQuote(false)
        let back = stableHostFrame()
        lines.append("REST back host=\(fmt(back))")
        if let base, let quoted {
            lines.append(
                "REST growth="
                    + "\(quoted.height - base.height)"
                    + " topDisp=\(base.minY - quoted.minY)"
                    + " bottomDrift="
                    + "\(quoted.maxY - base.maxY)"
            )
            if let ct = capsuleTop() {
                lines.append(
                    "REST anchorGap base="
                        + "\(base.maxY - ct)"
                        + " quoted=\(quoted.maxY - ct)"
                )
            }
            if let back {
                lines.append(
                    "REST returnDelta h="
                        + "\(back.height - base.height)"
                        + " maxY=\(back.maxY - base.maxY)"
                )
            }
        }
        // —— 键盘弹起态（合成通知帧顶 541） ——
        postKeyboard(
            name: UIResponder.keyboardWillShowNotification,
            top: 541, duration: 0
        )
        let kbBase = stableHostFrame()
        lines.append("KB noquote host=\(fmt(kbBase))")
        setQuote(true)
        let kbQuoted = stableHostFrame()
        lines.append(
            "KB quote host=\(fmt(kbQuoted))"
                + " card=\(fmt(cardFrame()))"
                + " text=\(fmt(textViewFrame()))"
        )
        setQuote(false)
        let kbBack = stableHostFrame()
        lines.append("KB back host=\(fmt(kbBack))")
        if let kbBase, let kbQuoted {
            lines.append(
                "KB growth="
                    + "\(kbQuoted.height - kbBase.height)"
                    + " topDisp=\(kbBase.minY - kbQuoted.minY)"
                    + " bottomDrift="
                    + "\(kbQuoted.maxY - kbBase.maxY)"
            )
        }
        postKeyboard(
            name: UIResponder.keyboardWillHideNotification,
            top: 874, duration: 0
        )
        _ = stableHostFrame()
        let dump = lines.joined(separator: "\n")
        print("PROBE195-BEGIN\n\(dump)\nPROBE195-END")
        add(XCTAttachment(string: dump))
    }
}
