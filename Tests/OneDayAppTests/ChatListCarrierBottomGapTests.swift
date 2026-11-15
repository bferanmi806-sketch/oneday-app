import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §263 回归：新承载静止位「末条→输入舱顶」空距。
///
/// 病根链（gen3-gap-recheck-20261115 诊断定案）：§260
/// 的 86pt 帧外段从未实测、是假设 bottomSpace 精确
/// 时从 102 反解的（分解不唯一）；生产装配下承载帧
/// 底＝窗口底（列表面 ignoresSafeArea 出血到屏底，
/// §186 探针实证），convert 量得帧外段恒 0、扣减空
/// 转；多余量在喂入值——快照 bottomSpace 派生公式
/// 「(窗口高−锚顶)＋栈高」混窗口系记账与 §194 布局
/// 空间钉位，舱实际落座与锚模型差一份壳层链偏差
/// （坞锚实测 +83、键盘态同族），真机双态
/// 117/205 与诊断恒等式闭合。回底箭头同根：距底
/// 读数以已施工 adjustedContentInset.bottom 为标
/// 尺自指，停自家最大偏移恒读 0、箭头永不现。
///
/// 本套装配＝真实壳层链（取代 §260 的裸 UIWindow
/// 摆 788 帧测法——被争议的量正是壳层给承载的帧，
/// 手摆无证明力）：
/// - 窗口 402×874；页帧高 788（收于坞上方）；
/// - 承载以子控制器挂页内、视图四边锚到根视图
///   （＝ignoresSafeArea 出血的 UIKit 等价），帧底
///   ＝窗口底；
/// - 坞（83 高）与键盘面（顶 545）在根视图内、由
///   约束落位，锚顶以 convert 实测（与
///   reportDockTop 同口径）；
/// - 舱（栈高 54）坐在带 +83 y 变换的宿主容器内
///   （生产壳层链含带变换祖先、layoutSpaceMinY 累
///   加失真 +83 的结构等价），底边由约束钉在锚线
///   上——其窗口系实帧（convert，即
///   barFrameInWindow 的量法）比锚模型低 83：喂入
///   派生值与实际落座系统性差 83，与诊断同量级。
///
/// 断言口径（实测单源）：施工 inset 应＝（承载帧
/// 底−舱顶）两实测相减＋单点边距 16；静止总量
/// （末条→舱顶，含底 padding 8）恒 24。
@MainActor
final class ChatListCarrierBottomGapTests: XCTestCase {

    private enum Assembly {
        static let windowWidth: CGFloat = 402
        static let windowHeight: CGFloat = 874
        static let pageHeight: CGFloat = 788
        static let dockHeight: CGFloat = 83
        static let keyboardTop: CGFloat = 545
        static let pocketHeight: CGFloat = 54
        static let chainSkew: CGFloat = 83
        static let bottomPadding: CGFloat = 8
        static let bottomMargin: CGFloat = 16
        static let targetGap: CGFloat = 24
    }

    private var window: UIWindow!
    private var root: UIViewController!
    private var controller: ChatListCarrierViewController!
    private var handle: ChatListCarrierHandle!
    private var dockView: UIView!
    private var keyboardView: UIView!
    private var composerBar: UIView!
    private var restAnchorConstraint: NSLayoutConstraint!
    private var keyboardAnchorConstraint: NSLayoutConstraint!

    override func setUp() {
        super.setUp()
        controller = ChatListCarrierViewController()
        handle = ChatListCarrierHandle()
        controller.handle = handle
        controller.callbacks = ChatListCarrierCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
    }

    override func tearDown() {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        root = nil
        controller = nil
        handle = nil
        dockView = nil
        keyboardView = nil
        composerBar = nil
        restAnchorConstraint = nil
        keyboardAnchorConstraint = nil
        super.tearDown()
    }

    // MARK: 装配（真实壳层链）

    /// skew＝壳层链变换量（83＝生产实测；0＝落座与
    /// 锚模型一致的对照装配）
    private func installShell(skew: CGFloat) {
        window = UIWindow(
            frame: CGRect(
                x: 0, y: 0,
                width: Assembly.windowWidth,
                height: Assembly.windowHeight
            )
        )
        root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let rootView = root.view!

        // 页帧：高 788、收于坞上方（生产壳层同形）
        let page = UIViewController()
        root.addChild(page)
        rootView.addSubview(page.view)
        page.view.translatesAutoresizingMaskIntoConstraints
            = false
        NSLayoutConstraint.activate([
            page.view.topAnchor.constraint(
                equalTo: rootView.topAnchor
            ),
            page.view.leadingAnchor.constraint(
                equalTo: rootView.leadingAnchor
            ),
            page.view.trailingAnchor.constraint(
                equalTo: rootView.trailingAnchor
            ),
            page.view.heightAnchor.constraint(
                equalToConstant: Assembly.pageHeight
            ),
        ])
        page.didMove(toParent: root)

        // 承载：页内子控制器、视图四边锚根视图（出
        // 血到窗口底——ignoresSafeArea 的 UIKit 等价）
        page.addChild(controller)
        page.view.addSubview(controller.view)
        controller.view
            .translatesAutoresizingMaskIntoConstraints
            = false
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(
                equalTo: rootView.topAnchor
            ),
            controller.view.bottomAnchor.constraint(
                equalTo: rootView.bottomAnchor
            ),
            controller.view.leadingAnchor.constraint(
                equalTo: rootView.leadingAnchor
            ),
            controller.view.trailingAnchor.constraint(
                equalTo: rootView.trailingAnchor
            ),
        ])
        controller.didMove(toParent: page)

        // 坞与键盘面（根视图内、约束落位、变换外——
        // 锚探针的 convert 实测与生产同口径）
        dockView = UIView()
        dockView.translatesAutoresizingMaskIntoConstraints
            = false
        rootView.addSubview(dockView)
        NSLayoutConstraint.activate([
            dockView.leadingAnchor.constraint(
                equalTo: rootView.leadingAnchor
            ),
            dockView.trailingAnchor.constraint(
                equalTo: rootView.trailingAnchor
            ),
            dockView.bottomAnchor.constraint(
                equalTo: rootView.bottomAnchor
            ),
            dockView.heightAnchor.constraint(
                equalToConstant: Assembly.dockHeight
            ),
        ])
        keyboardView = UIView()
        keyboardView.translatesAutoresizingMaskIntoConstraints
            = false
        rootView.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(
                equalTo: rootView.leadingAnchor
            ),
            keyboardView.trailingAnchor.constraint(
                equalTo: rootView.trailingAnchor
            ),
            keyboardView.bottomAnchor.constraint(
                equalTo: rootView.bottomAnchor
            ),
            keyboardView.heightAnchor.constraint(
                equalToConstant: Assembly.windowHeight
                    - Assembly.keyboardTop
            ),
        ])

        // 舱宿主容器：全窗＋y 变换（壳层链带变换祖
        // 先的结构等价）；舱由约束钉在容器内的锚线
        // 上（布局空间钉位），窗口系实帧随变换偏移
        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints
            = false
        rootView.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(
                equalTo: rootView.topAnchor
            ),
            host.bottomAnchor.constraint(
                equalTo: rootView.bottomAnchor
            ),
            host.leadingAnchor.constraint(
                equalTo: rootView.leadingAnchor
            ),
            host.trailingAnchor.constraint(
                equalTo: rootView.trailingAnchor
            ),
        ])
        host.transform = CGAffineTransform(
            translationX: 0, y: skew
        )
        composerBar = UIView()
        composerBar.translatesAutoresizingMaskIntoConstraints
            = false
        host.addSubview(composerBar)
        let restLine = UIView()
        restLine.translatesAutoresizingMaskIntoConstraints
            = false
        host.addSubview(restLine)
        let keyboardLine = UIView()
        keyboardLine.translatesAutoresizingMaskIntoConstraints
            = false
        host.addSubview(keyboardLine)
        NSLayoutConstraint.activate([
            restLine.topAnchor.constraint(
                equalTo: host.topAnchor,
                constant: Assembly.windowHeight
                    - Assembly.dockHeight
            ),
            restLine.heightAnchor.constraint(
                equalToConstant: 0
            ),
            keyboardLine.topAnchor.constraint(
                equalTo: host.topAnchor,
                constant: Assembly.keyboardTop
            ),
            keyboardLine.heightAnchor.constraint(
                equalToConstant: 0
            ),
            composerBar.leadingAnchor.constraint(
                equalTo: host.leadingAnchor
            ),
            composerBar.trailingAnchor.constraint(
                equalTo: host.trailingAnchor
            ),
            composerBar.heightAnchor.constraint(
                equalToConstant: Assembly.pocketHeight
            ),
        ])
        restAnchorConstraint = composerBar.bottomAnchor
            .constraint(equalTo: restLine.topAnchor)
        keyboardAnchorConstraint = composerBar.bottomAnchor
            .constraint(equalTo: keyboardLine.topAnchor)
        restAnchorConstraint.isActive = true

        rootView.layoutIfNeeded()
    }

    private func seatComposerOnKeyboard() {
        restAnchorConstraint.isActive = false
        keyboardAnchorConstraint.isActive = true
        root.view.layoutIfNeeded()
    }

    // MARK: 实测量（窗口系，convert——与生产通道同法）

    /// 舱顶实测（＝barFrameInWindow.minY 的量法）
    private var composerTopInWindow: CGFloat {
        composerBar.convert(composerBar.bounds, to: window)
            .minY
    }

    /// 承载帧底实测（承载自家 convert 的量法）
    private var carrierFrameBottomInWindow: CGFloat {
        controller.view.convert(
            controller.view.bounds, to: window
        ).maxY
    }

    /// 锚顶实测（坞/键盘探针 convert——快照锚的来源）
    private func anchorTopInWindow(
        keyboard: Bool
    ) -> CGFloat {
        let probe = keyboard ? keyboardView! : dockView!
        return probe.convert(probe.bounds, to: window).minY
    }

    /// 旧派生公式（KeyboardGeometrySnapshot.
    /// bottomSpace 逐字）：(窗口高−锚顶)＋栈高
    private func derivedBottomSpace(
        keyboard: Bool
    ) -> CGFloat {
        max(
            0,
            Assembly.windowHeight
                - anchorTopInWindow(keyboard: keyboard)
        ) + Assembly.pocketHeight
    }

    /// 实测所需留位：承载帧底−舱顶（两实测相减）
    private var measuredSpace: CGFloat {
        carrierFrameBottomInWindow - composerTopInWindow
    }

    // MARK: 行与喂入

    private func makeRows(count: Int) -> [ChatCarrierRow] {
        (0..<count).map { index in
            ChatCarrierRow(
                key: "gap-\(index)",
                entryID: UUID(),
                version: 1,
                estimatedHeight: 60,
                makeView: {
                    AnyView(Color.clear.frame(height: 60))
                }
            )
        }
    }

    private var testLayout: ChatCarrierLayout {
        ChatCarrierLayout(
            horizontalPadding: 20, topPadding: 16,
            bottomPadding: Assembly.bottomPadding,
            rowSpacing: 24,
            arrowTrailing: 16, arrowSize: 44
        )
    }

    /// 红测期喂入（旧签名）：快照派生值＋单点边距
    /// ——与 0.50.47 出货喂法逐字一致
    private func applyDerived(keyboard: Bool) {
        let space = derivedBottomSpace(keyboard: keyboard)
        controller.apply(
            rows: makeRows(count: 30),
            layout: testLayout,
            topInset: 122,
            bottomInset: space + Assembly.bottomMargin,
            bottomSpace: space,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0,
            arrowView: AnyView(Color.clear)
        )
    }

    private func drainRunLoop(
        seconds: TimeInterval = 0.3
    ) {
        RunLoop.main.run(
            until: Date().addingTimeInterval(seconds)
        )
    }

    /// 末行底边（视图坐标，量实回算）
    private var lastRowBottomInView: CGFloat {
        controller.scrollView.contentSize.height
            - Assembly.bottomPadding
            - controller.scrollView.contentOffset.y
    }

    /// 舱顶（视图坐标）＝舱顶窗口实测−承载帧顶窗口
    /// 实测（本装配帧顶＝0，仍按两实测相减取，不写
    /// 死）
    private var composerTopInView: CGFloat {
        composerTopInWindow
            - controller.view.convert(
                controller.view.bounds, to: window
            ).minY
    }

    private func assertMeasuredGeometry(
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let expectedInset = measuredSpace
            + Assembly.bottomMargin
        XCTAssertEqual(
            controller.scrollView.contentInset.bottom,
            expectedInset, accuracy: 0.6,
            "施工 inset 应＝实测留位＋边距（两实测相减）",
            file: file, line: line
        )
        XCTAssertEqual(
            handle.bottomInset, expectedInset,
            accuracy: 0.6,
            "回报口径与施工值恒等",
            file: file, line: line
        )
        let gap = composerTopInView - lastRowBottomInView
        XCTAssertEqual(
            gap, Assembly.targetGap, accuracy: 0.6,
            "静止位末条→舱顶总量应＝24（Muse 实测口径）",
            file: file, line: line
        )
        XCTAssertEqual(
            handle.latestDistance, 0, accuracy: 1,
            "贴底时距底读数应≈0",
            file: file, line: line
        )
        XCTAssertTrue(
            handle.contentEndVisible,
            "贴底时末端事实应为真",
            file: file, line: line
        )
    }

    // MARK: 用例

    /// 静息态：派生喂入比实测多 83——施工与静止总
    /// 量必须按实测走（旧公式下本条红：inset 多 83、
    /// 空距 107）
    func testRestStateUsesMeasuredSpaceNotDerivedFeed() {
        installShell(skew: Assembly.chainSkew)
        applyDerived(keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        controller.scrollToBottom(animated: false)
        drainRunLoop()

        XCTAssertEqual(
            derivedBottomSpace(keyboard: false),
            measuredSpace + Assembly.chainSkew,
            accuracy: 0.6,
            "装配前提：派生喂入应比实测留位多一份链偏差"
        )
        assertMeasuredGeometry()
        // 回底钮：底缘贴舱顶上方 8（实测落位）
        let arrow = controller.view.subviews.first {
            $0.frame.width == 44 && $0.frame.height == 44
                && $0 !== controller.scrollView
        }
        let arrowView = try? XCTUnwrap(
            arrow, "回底钮 overlay 应在场"
        )
        if let arrowView {
            XCTAssertEqual(
                arrowView.frame.maxY,
                composerTopInView - 8,
                accuracy: 0.6,
                "回底钮底缘应贴实测舱顶上方 8"
            )
        }
    }

    /// 键盘态：舱改钉键盘锚线、喂入换键盘派生值，
    /// 同口径恒 24（旧公式下本条红：同多 83）
    func testKeyboardStateUsesMeasuredSpaceNotDerivedFeed() {
        installShell(skew: Assembly.chainSkew)
        applyDerived(keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()

        seatComposerOnKeyboard()
        applyDerived(keyboard: true)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        controller.scrollToBottom(animated: false)
        drainRunLoop()

        XCTAssertEqual(
            derivedBottomSpace(keyboard: true),
            measuredSpace + Assembly.chainSkew,
            accuracy: 0.6,
            "装配前提：键盘态派生喂入同样多一份链偏差"
        )
        assertMeasuredGeometry()
    }

    /// 对照：落座与锚模型一致（无链偏差）时实测与
    /// 派生同值——新口径不得过校正，总量仍 24
    func testZeroSkewAssemblyStillMatchesTarget() {
        installShell(skew: 0)
        applyDerived(keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        controller.scrollToBottom(animated: false)
        drainRunLoop()

        XCTAssertEqual(
            derivedBottomSpace(keyboard: false),
            measuredSpace, accuracy: 0.6,
            "装配前提：无偏差时派生与实测同值"
        )
        assertMeasuredGeometry()
    }

    /// 距底读数回归：离底 200 时读数应≈200、末端
    /// 事实为假（回底箭头显隐的输入面）；回底后归
    /// 零、事实转真
    func testDistanceReadingTracksMeasuredBottom() {
        installShell(skew: Assembly.chainSkew)
        applyDerived(keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        controller.scrollToBottom(animated: false)
        drainRunLoop()

        let scrollView = controller.scrollView
        let maxOffset = scrollView.contentSize.height
            + scrollView.contentInset.bottom
            - scrollView.bounds.height
        scrollView.setContentOffset(
            CGPoint(x: 0, y: maxOffset - 200),
            animated: false
        )
        drainRunLoop()
        XCTAssertEqual(
            handle.latestDistance, 200, accuracy: 1.5,
            "离底 200 的读数应≈200（箭头显隐标尺）"
        )
        XCTAssertFalse(
            handle.contentEndVisible,
            "离底 200 时末端不应判在屏"
        )

        controller.scrollToBottom(animated: false)
        drainRunLoop()
        XCTAssertEqual(
            handle.latestDistance, 0, accuracy: 1,
            "回底后读数归零"
        )
        XCTAssertTrue(
            handle.contentEndVisible,
            "回底后末端事实转真"
        )
    }
}
