import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §260 回归：新承载静止位「末条→输入舱顶」空距。
/// 病根（0.50.46 真机反馈＋双截图量测）：喂入底
/// inset 以窗口底为锚（快照 bottomSpace＝舱顶→
/// 窗口底），承载帧底在生产装配里位于窗口底上方
/// 86pt（壳层页帧收于坞上方）——帧外段不在滚动
/// 视图内却被整段计入 inset，末条多停高 86pt，
/// 静止空距实测 102＝86＋边距 8＋底 padding 8
/// （双态同值）。修法：承载以自家窗口实帧量帧外
/// 段、施工与几何恒扣；喂入单点边距校准 spacingM
/// ——与底 padding（spacingS）合计 24pt＝Muse
/// 一手实测总量（gen3-bottom-gap 报告）。
///
/// 本套以 UIWindow 复刻生产装配几何（窗口 874、
/// 承载帧 402×788＝帧外段 86、坞顶 791、舱栈
/// 54），双态（静息 bottomSpace 137／键盘 383）
/// 断言静止总量恒 24；第三条钉无窗口装配的回落
/// （帧外段 0、施工值＝喂入值、旧行为不变——
/// §259 既有测试装配即此形态）
@MainActor
final class ChatListCarrierBottomGapTests: XCTestCase {

    /// 装配常量（生产同值，来源见文件头）
    private enum Assembly {
        static let windowHeight: CGFloat = 874
        static let viewHeight: CGFloat = 788
        static var overhang: CGFloat {
            windowHeight - viewHeight
        }
        /// 静息：坞顶 791、舱栈 54 → bottomSpace
        /// ＝(874−791)＋54＝137；喂入 inset＝137＋
        /// spacingM 16＝153
        static let restBottomSpace: CGFloat = 137
        /// 键盘：键盘顶 545 → bottomSpace＝(874−
        /// 545)＋54＝383；喂入 inset＝383＋16＝399
        static let keyboardBottomSpace: CGFloat = 383
        static let bottomPadding: CGFloat = 8
        static let targetGap: CGFloat = 24
    }

    private var window: UIWindow!
    private var container: UIViewController!
    private var controller: ChatListCarrierViewController!
    private var handle: ChatListCarrierHandle!

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
        container = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    /// 固定高 60 的占位行（与 §259 套同式：量实
    /// 与估算恒等、帧表可精确回算）
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

    private func applyState(
        bottomSpace: CGFloat, arrowView: AnyView? = nil
    ) {
        controller.apply(
            rows: makeRows(count: 30),
            layout: testLayout,
            topInset: 122,
            bottomInset: bottomSpace + OneDayMetrics.spacingM,
            bottomSpace: bottomSpace,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0,
            arrowView: arrowView
        )
    }

    private func drainRunLoop(
        seconds: TimeInterval = 0.3
    ) {
        RunLoop.main.run(
            until: Date().addingTimeInterval(seconds)
        )
    }

    /// 入窗装配：窗口 874、承载以子控制器形态嵌
    /// 入容器、帧底钉在 788（帧外段 86 与生产装
    /// 配同值；子控制器帧由父级给定后稳定，与生
    /// 产 SwiftUI representable 的给帧形态一致）
    private func installInWindow() {
        window = UIWindow(
            frame: CGRect(
                x: 0, y: 0, width: 402,
                height: Assembly.windowHeight
            )
        )
        container = UIViewController()
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 402,
            height: Assembly.viewHeight
        )
        controller.didMove(toParent: container)
        container.view.layoutIfNeeded()
    }

    /// 末行底边（视图坐标，量实回算：内容高−底
    /// padding−offset，不读施工公式的镜像值）
    private var lastRowBottomInView: CGFloat {
        controller.scrollView.contentSize.height
            - Assembly.bottomPadding
            - controller.scrollView.contentOffset.y
    }

    /// 舱顶（视图坐标）：帧底−（bottomSpace 扣帧
    /// 外段）——舱在本装配中的构造落点
    private func composerTopInView(
        bottomSpace: CGFloat
    ) -> CGFloat {
        Assembly.viewHeight - (bottomSpace - Assembly.overhang)
    }

    /// 静息态：施工 inset 扣帧外段、静止总量 24、
    /// 回底钮底缘贴舱顶上方 8
    func testRestStateGapMatchesTargetAfterOverhangDiscount() {
        installInWindow()
        applyState(
            bottomSpace: Assembly.restBottomSpace,
            arrowView: AnyView(Color.clear)
        )
        controller.view.layoutIfNeeded()
        drainRunLoop()
        controller.scrollToBottom(animated: false)
        drainRunLoop()

        let fed = Assembly.restBottomSpace
            + OneDayMetrics.spacingM
        XCTAssertEqual(
            controller.scrollView.contentInset.bottom,
            fed - Assembly.overhang, accuracy: 0.6,
            "施工 inset 应＝喂入 153−帧外段 86＝67"
        )
        XCTAssertEqual(
            handle.bottomInset,
            fed - Assembly.overhang, accuracy: 0.6,
            "回报口径与施工值恒等"
        )
        let gap = composerTopInView(
            bottomSpace: Assembly.restBottomSpace
        ) - lastRowBottomInView
        XCTAssertEqual(
            gap, Assembly.targetGap, accuracy: 0.6,
            "静止位末条→舱顶总量应＝24（Muse 实测口径）"
        )
        // 回底钮：底缘＝舱顶上方 8（同根修正前偏高
        // 86）——钮帧由 layoutArrow 以施工口径构造
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
                composerTopInView(
                    bottomSpace: Assembly.restBottomSpace
                ) - 8,
                accuracy: 0.6,
                "回底钮底缘应贴舱顶上方 8"
            )
        }
    }

    /// 键盘态：换喂入（bottomSpace 383）后同口径
    /// ——总量与状态无关、恒 24
    func testKeyboardStateGapMatchesTargetAfterOverhangDiscount() {
        installInWindow()
        applyState(bottomSpace: Assembly.restBottomSpace)
        controller.view.layoutIfNeeded()
        drainRunLoop()

        applyState(bottomSpace: Assembly.keyboardBottomSpace)
        controller.view.layoutIfNeeded()
        drainRunLoop()
        controller.scrollToBottom(animated: false)
        drainRunLoop()

        let fed = Assembly.keyboardBottomSpace
            + OneDayMetrics.spacingM
        XCTAssertEqual(
            controller.scrollView.contentInset.bottom,
            fed - Assembly.overhang, accuracy: 0.6,
            "施工 inset 应＝喂入 399−帧外段 86＝313"
        )
        let gap = composerTopInView(
            bottomSpace: Assembly.keyboardBottomSpace
        ) - lastRowBottomInView
        XCTAssertEqual(
            gap, Assembly.targetGap, accuracy: 0.6,
            "键盘态静止总量同样应＝24"
        )
    }

    /// 无窗口装配（§259 既有测试形态）：帧外段无
    /// 从量测、回落 0——施工值＝喂入值，旧行为不变
    func testWindowlessAssemblyKeepsFedInsetUnchanged() {
        controller.loadViewIfNeeded()
        applyState(bottomSpace: Assembly.restBottomSpace)
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 402,
            height: Assembly.viewHeight
        )
        controller.view.layoutIfNeeded()
        drainRunLoop()

        let fed = Assembly.restBottomSpace
            + OneDayMetrics.spacingM
        XCTAssertEqual(
            controller.scrollView.contentInset.bottom,
            fed, accuracy: 0.6,
            "无窗口时帧外段回落 0、施工值＝喂入值"
        )
        XCTAssertEqual(
            handle.bottomInset, fed, accuracy: 0.6
        )
    }
}
