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
/// 2. 仲裁声明：shouldRequireFailureOf 恒假（不
///    等点按/长按、共存靠位移锁）、不同时识别、
///    shouldBegin 在排除帧覆盖起始点时恒假；
/// 3. 回调链：经安装器 processPanTranslation 直
///    驱生产修饰符状态——过线只触发一次、收尾
///    复位后可再触发；
/// 4. isEnabled 翻假（选区在场关右滑的生产路径）
///    →桥 dismantle、识别器自滚动视图摘除；
/// 5. began 前裁决（换代包 8）：Direction-
///    LockPanGestureRecognizer.preBeginVer-
///    dict 决策表——锁距内观察、右向放行、竖
///    向与左向判死（0.50.79 纵滚全灭的修复钉）。
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
        // shouldBegin 正分支：无排除帧即放行——方向判定在识别器
        // 子类的 began 前裁决（换代包 8），本口只判排除帧
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

    /// began 前裁决决策表（换代包 8）：0.50.79 的
    /// 病根是方向判定在 began 之后——本表把判定
    /// 点钉在 began 之前：锁距内只观察、右向放
    /// 行、竖向/左向在开始之前判死（纵滚得救）
    func testPreBeginVerdictTable() {
        typealias Verdict =
            DirectionLockPanGestureRecognizer
                .PreBeginVerdict
        // 锁距（10pt）内：只观察，不许出结论
        XCTAssertEqual(
            DirectionLockPanGestureRecognizer
                .preBeginVerdict(
                    translationX: 5, translationY: 0
                ),
            Verdict.observe
        )
        XCTAssertEqual(
            DirectionLockPanGestureRecognizer
                .preBeginVerdict(
                    translationX: 0, translationY: 9
                ),
            Verdict.observe
        )
        // 右向占优：放行开始识别
        XCTAssertEqual(
            DirectionLockPanGestureRecognizer
                .preBeginVerdict(
                    translationX: 12, translationY: 3
                ),
            Verdict.begin
        )
        // 竖向占优：在 began 之前判死，纵滚接管
        XCTAssertEqual(
            DirectionLockPanGestureRecognizer
                .preBeginVerdict(
                    translationX: 3, translationY: 12
                ),
            Verdict.fail
        )
        // 左向占优：非本手势辖区，同判死不悬置
        XCTAssertEqual(
            DirectionLockPanGestureRecognizer
                .preBeginVerdict(
                    translationX: -12, translationY: 3
                ),
            Verdict.fail
        )
        // 斜向未分（|dx|＝|dy|）：继续观察
        XCTAssertEqual(
            DirectionLockPanGestureRecognizer
                .preBeginVerdict(
                    translationX: 10, translationY: 10
                ),
            Verdict.observe
        )
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
