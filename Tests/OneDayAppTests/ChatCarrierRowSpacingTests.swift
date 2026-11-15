import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §89 回归门：新承载相邻行间距实测。
///
/// 定因（gen3-bubble-spacing-20261115.md）：行宿主
/// UIHostingController.sizeThatFits 会把宿主视图当
/// 时的 safeAreaInsets 折进量实高；滚动内容深处（贴
/// 底区）的行宿主带页面底部安全区（真机 83＝标签栏
/// 49＋小横条 34），量实被 +83 污染、帧高虚高、视
/// 觉行距＝24＋83＝107。修法＝行宿主
/// safeAreaRegions 清零（行是滚动内容、不消费安全
/// 区），量实回归纯内容高。
///
/// 本门装配含真实壳层链：窗口＋父 VC 注入真机安全
/// 区（additionalSafeAreaInsets 上 59/下 83）＋真实
/// 承载控制器＋生产同值布局；行内容为 ChatView 用
/// 户行同构复刻（探针实证：宽 362 时纯内容高
/// 45.33）。另设环境自检：同层级裸宿主（不清零）
/// 在内容深处必须量出 128.33（45.33＋83）——证明
/// 本装配的安全区污染在场，承载断言非空转。
@MainActor
final class ChatCarrierRowSpacingTests: XCTestCase {

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
            onScrollGeometry: {}, onTopVisibleEntry: { _ in },
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

    private func drainRunLoop(seconds: TimeInterval) {
        RunLoop.main.run(
            until: Date().addingTimeInterval(seconds)
        )
    }

    // MARK: - 行内容复刻（与生产同构同值，探针实证）

    private func userBubbleText() -> some View {
        SelectableInlineText(
            paragraphs: [.plain("测试一下")],
            textStyle: .callout,
            foreground: Palette.userBubbleText,
            onSelectionChange: { _ in }
        )
        .padding(.horizontal, OneDayMetrics.bubblePaddingH)
        .padding(.vertical, OneDayMetrics.bubblePaddingV)
        .background(
            Palette.userBubbleFill,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.bubbleCorner
            )
        )
    }

    private func userRowView() -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack {
                Spacer(minLength: OneDayMetrics.bubbleSideInset)
                VStack(
                    alignment: .trailing,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    userBubbleText()
                }
                .modifier(
                    SwipeReplyModifier(
                        isEnabled: true, onReply: {}
                    )
                )
            }
        }
    }

    private func installInWindow() {
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        container = UIViewController()
        window.rootViewController = container
        window.makeKeyAndVisible()
        // 真机壳层：页面安全区上 59／下 83（§186 冻结
        // 几何）——测试宿主窗口本身恒 0，必须注入，
        // 否则量实污染不复现（探针 1–3 的教训）
        container.additionalSafeAreaInsets = UIEdgeInsets(
            top: 59, left: 0, bottom: 83, right: 0
        )
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 402, height: 874
        )
        controller.didMove(toParent: container)
        container.view.layoutIfNeeded()
    }

    /// 环境自检：同层级裸宿主在内容深处量实必须被
    /// 底部安全区 +83 污染（不清零时 128.33）；清零
    /// 后必须回 45.33。本自检不过则本门装配无效。
    func testEnvironmentReproducesSafeAreaPollution() {
        installInWindow()
        let scrollView = UIScrollView(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: 122, left: 0, bottom: 153, right: 0
        )
        scrollView.contentSize = CGSize(width: 402, height: 2000)
        container.view.addSubview(scrollView)
        let contentView = UIView(
            frame: CGRect(x: 0, y: 0, width: 402, height: 2000)
        )
        scrollView.addSubview(contentView)
        container.view.layoutIfNeeded()

        let bare = UIHostingController(
            rootView: AnyView(userRowView())
        )
        container.addChild(bare)
        contentView.addSubview(bare.view)
        bare.view.frame = CGRect(
            x: 20, y: 1800, width: 362, height: 47
        )
        bare.didMove(toParent: container)
        drainRunLoop(seconds: 0.3)
        container.view.layoutIfNeeded()

        let proposal = CGSize(
            width: 362, height: CGFloat.greatestFiniteMagnitude
        )
        XCTAssertEqual(
            bare.view.safeAreaInsets.bottom, 83, accuracy: 0.6,
            "装配自检：内容深处宿主应带底部安全区 83"
        )
        XCTAssertEqual(
            bare.sizeThatFits(in: proposal).height,
            45.33 + 83, accuracy: 1.0,
            "装配自检：裸宿主量实应被安全区污染为 128.33"
        )
        bare.safeAreaRegions = []
        drainRunLoop(seconds: 0.3)
        XCTAssertEqual(
            bare.sizeThatFits(in: proposal).height,
            45.33, accuracy: 1.0,
            "修法自检：safeAreaRegions 清零后量实应回纯内容高"
        )
    }

    /// 主门：30 行长会话贴底静息后，全部已物化行帧
    /// 高＝纯内容高、相邻行帧间隙＝行距令牌 24。
    func testRowSpacingAtBottomWithDeviceSafeArea() {
        installInWindow()
        let rows: [ChatCarrierRow] = (0..<30).map { index in
            ChatCarrierRow(
                key: "spacing-row-\(index)",
                entryID: UUID(),
                version: 1,
                estimatedHeight: 47,
                makeView: { AnyView(self.userRowView()) }
            )
        }
        controller.apply(
            rows: rows,
            layout: ChatCarrierLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: OneDayMetrics.spacingS,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: 122,
            bottomInset: 153,
            bottomSpace: 137,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0,
            arrowView: nil
        )
        controller.view.layoutIfNeeded()
        drainRunLoop(seconds: 1.0)
        controller.scrollToBottom(animated: false)
        drainRunLoop(seconds: 1.0)
        controller.view.layoutIfNeeded()

        let sv = controller.scrollView
        // 内容总高＝上 padding 16＋30×45.33＋29×24＋
        // 下 padding 8（任一行被 +83 污染都会胀大）
        let expectedContent = 16.0 + 30.0 * 45.33 + 29.0 * 24.0 + 8.0
        XCTAssertEqual(
            sv.contentSize.height, expectedContent, accuracy: 1.0,
            "内容总高应为纯内容高＋行距 24×29，无安全区污染"
        )
        guard let contentView = sv.subviews.first else {
            XCTFail("承载内容视图缺席")
            return
        }
        let hosts = contentView.subviews.sorted {
            $0.frame.minY < $1.frame.minY
        }
        XCTAssertGreaterThanOrEqual(
            hosts.count, 10, "贴底后应有足量行已物化"
        )
        for host in hosts {
            XCTAssertEqual(
                host.frame.height, 45.33, accuracy: 1.0,
                "行帧高应为纯内容高 45.33，实测 \(host.frame.height)"
            )
        }
        if hosts.count > 1 {
            for index in 1..<hosts.count {
                let gap = hosts[index].frame.minY
                    - hosts[index - 1].frame.maxY
                XCTAssertEqual(
                    gap, 24, accuracy: 1.0,
                    "相邻行帧间隙应＝行距令牌 24，实测 \(gap)"
                )
            }
        }
    }
}
