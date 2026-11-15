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
        static let topInset: CGFloat = 122
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

    /// §263 喂入：舱顶窗口实测（convert，与生产
    /// barFrameInWindow 同法同拍）＋回落种子＋单点
    /// 边距。回落种子恒取静息派生值——量得实测后
    /// 它永不参与施工，落座追随用例据此判读（种子
    /// 不变、留位随实测变）
    private func applyDerived(keyboard: Bool) {
        applyRows(count: 30, keyboard: keyboard)
    }

    /// 行数可变版喂入（§274 短内容用例用）：其余喂
    /// 入口径与 applyDerived 逐值一致
    private func applyRows(count: Int, keyboard: Bool) {
        controller.apply(
            rows: makeRows(count: count),
            layout: testLayout,
            topInset: Assembly.topInset,
            composerTopInWindow: composerTopInWindow,
            fallbackBottomSpace: derivedBottomSpace(
                keyboard: false
            ),
            bottomMargin: Assembly.bottomMargin,
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

    /// 托管行实际帧底（视图坐标）：内容视图（滚动
    /// 视图内高＝contentSize 的那块）里托管子视图的
    /// 帧是 materialize 落的真帧——取其最大 maxY
    /// 换算到视图坐标，不经 contentSize 反推
    private var hostedLastRowBottomInView: CGFloat? {
        let scrollView = controller.scrollView
        guard let content = scrollView.subviews.max(
            by: { $0.frame.height < $1.frame.height }
        ), content.frame.height > 0 else { return nil }
        let bottoms = content.subviews.map { $0.frame.maxY }
        guard let maxBottom = bottoms.max() else { return nil }
        return maxBottom - scrollView.contentOffset.y
    }

    /// §274 短内容断言组：不手动调 scrollToBottom
    /// ——落位必须由 apply 链自产（审计 §3：验收不
    /// 许先手动滚底）。四数同帧：静止 offset 恰为
    /// −顶 inset（物理底点）、内容高恰＝有效视口高
    /// （V−T−B，三量全实测）、托管真帧末行底→舱顶
    /// 24±1、§263 既有断言组不退
    private func assertShortContentAnchored(
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let scrollView = controller.scrollView
        XCTAssertEqual(
            scrollView.contentOffset.y,
            -Assembly.topInset, accuracy: 0.6,
            "短内容静止 offset 应恰为 −顶 inset（物理底点）",
            file: file, line: line
        )
        let effectiveViewport = scrollView.bounds.height
            - scrollView.contentInset.top
            - scrollView.contentInset.bottom
        XCTAssertEqual(
            scrollView.contentSize.height,
            effectiveViewport, accuracy: 0.6,
            "短内容内容高应恰＝有效视口高（底锚定填充）",
            file: file, line: line
        )
        let hostedBottom = hostedLastRowBottomInView
        XCTAssertNotNil(
            hostedBottom, "短内容行应已托管在场",
            file: file, line: line
        )
        if let hostedBottom {
            XCTAssertEqual(
                composerTopInView - hostedBottom,
                Assembly.targetGap, accuracy: 1,
                "托管真帧末行底→舱顶应＝24±1",
                file: file, line: line
            )
        }
        assertMeasuredGeometry(file: file, line: line)
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

    /// 落座追随：舱改钉键盘锚线（落座变化）后，回
    /// 落种子（静息派生值）一字不变、只喂新的舱顶
    /// 实测——施工留位必须随实测迁移、总量恒 24
    /// （派生口径下种子不变即留位不变、空距随落座
    /// 漂移 83）
    func testInsetTracksSeatingChangeViaMeasuredFeed() {
        installShell(skew: Assembly.chainSkew)
        applyDerived(keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        controller.scrollToBottom(animated: false)
        drainRunLoop()
        assertMeasuredGeometry()

        seatComposerOnKeyboard()
        applyDerived(keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        controller.scrollToBottom(animated: false)
        drainRunLoop()
        assertMeasuredGeometry()
    }

    /// §274 短内容·单行·静息：内容自然高 84 ≪ 有
    /// 效视口——二修下末行贴顶、末行底→舱顶空距
    /// ＝24＋填充缺口（本条红：空距数百、距底读数
    /// 为负、内容高＝自然高）；底锚定后四数闭合
    func testShortContentSingleRowRestAnchorsToBottom() {
        installShell(skew: Assembly.chainSkew)
        applyRows(count: 1, keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()

        assertShortContentAnchored()
    }

    /// §274 短内容·三行·静息：.50 真机失败的同形
    /// 场景（3 条消息短会话、末条到舱 ≈148 空白的
    /// 装配复刻）——落位由 apply 链自产、不手动滚底
    func testShortContentThreeRowsRestAnchorsToBottom() {
        installShell(skew: Assembly.chainSkew)
        applyRows(count: 3, keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()

        assertShortContentAnchored()
    }

    /// §274 短内容·三行·键盘态：舱改钉键盘锚线后
    /// 重新喂入——有效视口随 B 变小、填充随之收，
    /// 末行底→舱顶仍 24±1（偏移落点由锚恢复钳制
    /// 与底点重合，全程不手动滚底）
    func testShortContentThreeRowsKeyboardAnchorsToBottom() {
        installShell(skew: Assembly.chainSkew)
        applyRows(count: 3, keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        assertShortContentAnchored()

        seatComposerOnKeyboard()
        applyRows(count: 3, keyboard: true)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        assertShortContentAnchored()
    }

    /// §274 短内容·单行·键盘态：填充缺口最大的一
    /// 档在键盘态同样闭合
    func testShortContentSingleRowKeyboardAnchorsToBottom() {
        installShell(skew: Assembly.chainSkew)
        applyRows(count: 1, keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()

        seatComposerOnKeyboard()
        applyRows(count: 1, keyboard: true)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        assertShortContentAnchored()
    }

    /// §274 填充边界穿越：3 行（填充在场）→30 行
    /// （填充归零、长内容二修路径）→3 行，两向穿
    /// 越后落点与空距逐值不变、全程不手动滚底
    func testContentGrowthAcrossAnchorBoundaryStaysGlued() {
        installShell(skew: Assembly.chainSkew)
        applyRows(count: 3, keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        assertShortContentAnchored()

        applyRows(count: 30, keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        XCTAssertGreaterThan(
            controller.scrollView.contentSize.height,
            controller.scrollView.bounds.height,
            "30 行应为长内容（内容高超视口）"
        )
        assertMeasuredGeometry()

        applyRows(count: 3, keyboard: false)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        assertShortContentAnchored()
    }

    /// 无窗口装配（§259 既有测试形态）：量测不落
    /// 地、施工走回落种子＋边距——种子即旧派生喂
    /// 入口径，行为与 §260 无窗口回落逐值一致
    func testWindowlessAssemblyUsesFallbackSeed() {
        controller.loadViewIfNeeded()
        controller.apply(
            rows: makeRows(count: 30),
            layout: testLayout,
            topInset: 122,
            composerTopInWindow: 0,
            fallbackBottomSpace: derivedRestSeed,
            bottomMargin: Assembly.bottomMargin,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0,
            arrowView: nil
        )
        controller.view.frame = CGRect(
            x: 0, y: 0, width: Assembly.windowWidth,
            height: Assembly.pageHeight
        )
        controller.view.layoutIfNeeded()
        drainRunLoop()

        let expected = derivedRestSeed
            + Assembly.bottomMargin
        XCTAssertEqual(
            controller.scrollView.contentInset.bottom,
            expected, accuracy: 0.6,
            "无窗口时施工值＝回落种子＋边距"
        )
        XCTAssertEqual(
            handle.bottomInset, expected, accuracy: 0.6
        )
    }

    /// 静息派生种子（窗口高−坞顶＋栈高，公式直算
    /// ——无窗口装配下没有探针可 convert，取装配常
    /// 量口径：(874−791)＋54＝137）
    private var derivedRestSeed: CGFloat {
        Assembly.windowHeight
            - (Assembly.windowHeight - Assembly.dockHeight)
            + Assembly.pocketHeight
    }
}
