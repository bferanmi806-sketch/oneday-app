import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §265（换代包 5·右滑仲裁）识别器桥装配验收：
/// 装配生产原物（SelectableInlineText＋SwipeRep-
/// lyModifier，§199 同式）进真 UIScrollView 入窗，
/// 验四件：
/// 1. 每行在宿主滚动视图上恰装一枚具名 UIPanGe-
///    stureRecognizer、delegate 为本行安装器；
/// 2. 仲裁声明：点按/长按先行（shouldRequireFai-
///    lureOf 对 tap/longPress 恒真、对 pan 恒
///    假）、不同时识别、shouldBegin 在排除帧覆
///    盖起滑点/零速度时恒假（正分支由 Core 方向
///    门单测＋UI 测试真拖动覆盖）；
/// 3. 回调链：经安装器 processPanTranslation 直
///    驱生产修饰符状态——过线只触发一次、收尾
///    复位后可再触发；
/// 4. isEnabled 翻假（选区在场关右滑的生产路径）
///    →桥 dismantle、识别器自滚动视图摘除。
@MainActor
final class SwipeReplyPanBridgeTests: XCTestCase {

    private final class ReplyLog {
        var count = 0
    }

    private final class Control: ObservableObject {
        @Published var enabled = true
    }

    private struct Harness: View {
        @ObservedObject var control: Control
        let log: ReplyLog
        let rowCount: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(0..<rowCount, id: \.self) { _ in
                    SelectableInlineText(
                        paragraphs: [
                            .plain(
                                "alpha bravo charlie delta echo"
                            )
                        ]
                    )
                    .modifier(
                        SwipeReplyModifier(
                            isEnabled: control.enabled,
                            onReply: { log.count += 1 }
                        )
                    )
                }
            }
            .frame(width: 320, alignment: .leading)
            .padding()
        }
    }

    private var window: UIWindow!
    private var scrollView: UIScrollView!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        scrollView = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func assemble(
        control: Control, log: ReplyLog, rowCount: Int
    ) {
        scrollView = UIScrollView(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let host = UIHostingController(
            rootView: Harness(
                control: control, log: log, rowCount: rowCount
            )
        )
        host.view.frame = CGRect(
            x: 0, y: 0, width: 402, height: 600
        )
        scrollView.addSubview(host.view)
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(scrollView)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 1.0)
        window.layoutIfNeeded()
    }

    private func swipePans() -> [UIPanGestureRecognizer] {
        (scrollView.gestureRecognizers ?? []).compactMap {
            $0 as? UIPanGestureRecognizer
        }.filter {
            $0.name == SwipeReplyPanInstallerView.recognizerName
        }
    }

    private func installerViews() -> [SwipeReplyPanInstallerView] {
        var out: [SwipeReplyPanInstallerView] = []
        func walk(_ view: UIView) {
            if let installer = view
                as? SwipeReplyPanInstallerView {
                out.append(installer)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(scrollView)
        return out
    }

    func testBridgeInstallsOneNamedPanPerRow() {
        assemble(
            control: Control(), log: ReplyLog(), rowCount: 2
        )
        let pans = swipePans()
        print("BRIDGE pans=\(pans.count)")
        XCTAssertEqual(
            pans.count, 2, "两行应各装一枚具名横滑识别器"
        )
        let installers = installerViews()
        XCTAssertEqual(installers.count, 2)
        for pan in pans {
            XCTAssertTrue(
                pan.delegate is SwipeReplyPanInstallerView,
                "识别器 delegate 应为本行安装器"
            )
            XCTAssertEqual(pan.maximumNumberOfTouches, 1)
        }
        for installer in installers {
            XCTAssertNotNil(
                installer.installedRecognizer,
                "安装器应持有自己的识别器"
            )
        }
    }

    func testDelegateArbitrationDeclarations() throws {
        assemble(
            control: Control(), log: ReplyLog(), rowCount: 1
        )
        let installer = try XCTUnwrap(installerViews().first)
        let pan = try XCTUnwrap(installer.installedRecognizer)

        // 失败依赖收窄（仲裁重做 2026-11-22）：本口恒假——
        // 不再等点按/长按先失败（慢半拍的病根），共存靠位移式
        // 方向锁；对滚动的让行走安装时 require(toFail:) 单向声明
        XCTAssertFalse(
            installer.gestureRecognizer(
                pan, shouldRequireFailureOf:
                    UITapGestureRecognizer()
            )
        )
        XCTAssertFalse(
            installer.gestureRecognizer(
                pan, shouldRequireFailureOf:
                    UILongPressGestureRecognizer()
            )
        )
        // 对 pan 类不声明失败依赖（纵滚的让行走安
        // 装时对滚动 pan 的 require(toFail:) 单向）
        XCTAssertFalse(
            installer.gestureRecognizer(
                pan, shouldRequireFailureOf:
                    UIPanGestureRecognizer()
            )
        )
        // 不同时识别
        XCTAssertFalse(
            installer.gestureRecognizer(
                pan,
                shouldRecognizeSimultaneouslyWith:
                    UITapGestureRecognizer()
            )
        )
        // shouldBegin 负分支一：起滑点被排除帧覆盖
        installer.excludedFrames = [
            CGRect(x: -500, y: -500, width: 1000, height: 1000)
        ]
        XCTAssertFalse(
            installer.gestureRecognizerShouldBegin(pan),
            "起滑点落在排除帧内不许开始"
        )
        // shouldBegin 正分支：无排除帧即放行——旧速度门已废，
        // 方向判定移交 handlePan 的位移式方向锁，本口只判排除帧
        installer.excludedFrames = []
        XCTAssertTrue(
            installer.gestureRecognizerShouldBegin(pan),
            "无排除帧应放行，方向由位移锁在 handlePan 内判定"
        )
    }

    func testPanCallbacksTriggerOnceAndReset() throws {
        let log = ReplyLog()
        assemble(control: Control(), log: log, rowCount: 1)
        let installer = try XCTUnwrap(installerViews().first)

        installer.processPanTranslation(40)
        XCTAssertEqual(log.count, 0, "未过触发线不许触发")
        installer.processPanTranslation(70)
        XCTAssertEqual(log.count, 1, "过线当刻触发一次")
        installer.processPanTranslation(90)
        XCTAssertEqual(log.count, 1, "整段拖动只触发一次")
        installer.processPanEnd()
        installer.processPanTranslation(70)
        XCTAssertEqual(log.count, 2, "收尾复位后可再触发")
        installer.processPanEnd()
    }

    func testDisablingSwipeDismantlesRecognizer() {
        let control = Control()
        assemble(control: control, log: ReplyLog(), rowCount: 1)
        XCTAssertEqual(swipePans().count, 1)

        control.enabled = false
        spinRunLoop(seconds: 1.0)
        window.layoutIfNeeded()

        XCTAssertEqual(
            swipePans().count, 0,
            "右滑停用后识别器应自宿主滚动视图摘除"
        )
    }
}
