import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §89 临时探针（诊断用、非回归钉）：新承载相邻气泡
/// 间距真机实测 107pt（声明行距 24）——定因「行帧高
/// 比行内容理想高恒定多出 ~83」出在哪一环。装配＝
/// 生产同式壳层（UIWindow 402×874、承载填满窗口、
/// 顶 inset 122／底喂入 153／bottomSpace 137），行
/// 内容为 ChatView entryRowContent／bubble／
/// assistantBubble 的高保真复刻（用户行三变体＋助手
/// 行＋固定高对照）。全部只 print（PROBE89 前缀）、
/// 不断言；另独立量各复刻在窗口外／窗口内 hosting
/// controller 的 sizeThatFits 作对照。
@MainActor
final class ChatCarrierSpacingProbeTests: XCTestCase {

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

    // MARK: - 行内容复刻（与生产同构同值）

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

    private func userRowView(withSwipe: Bool) -> some View {
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
                        isEnabled: withSwipe, onReply: {}
                    )
                )
            }
        }
    }

    private func userRowPlainTextView() -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack {
                Spacer(minLength: OneDayMetrics.bubbleSideInset)
                VStack(
                    alignment: .trailing,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    Text("测试一下")
                        .font(.callout)
                        .padding(
                            .horizontal, OneDayMetrics.bubblePaddingH
                        )
                        .padding(
                            .vertical, OneDayMetrics.bubblePaddingV
                        )
                        .background(
                            Palette.userBubbleFill,
                            in: RoundedRectangle(
                                cornerRadius: OneDayMetrics.bubbleCorner
                            )
                        )
                }
            }
        }
    }

    private func assistantRowView() -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingS
            ) {
                HStack(alignment: .top) {
                    SelectableInlineText(
                        paragraphs: [.plain(
                            "在。要测哪个？\n"
                            + "· 引用长文本（看上限）\n"
                            + "· 发图片给我看（测 vision）\n"
                            + "· 发文件给我处理\n"
                            + "· 调手机功能（通讯录、日历、照片、"
                            + "拍照、发短信）\n"
                            + "· 搜索、写代码、跑命令\n"
                            + "· 还是别的"
                        )],
                        textStyle: .callout,
                        foreground: Palette.bodyInk,
                        onSelectionChange: { _ in }
                    )
                    .padding(
                        .horizontal, OneDayMetrics.bubblePaddingH
                    )
                    .padding(
                        .vertical, OneDayMetrics.bubblePaddingV
                    )
                    .background(
                        Palette.bubbleFill,
                        in: RoundedRectangle(
                            cornerRadius:
                                OneDayMetrics.assistantBubbleCorner
                        )
                    )
                    Spacer(minLength: OneDayMetrics.bubbleSideInset)
                }
            }
            .modifier(
                SwipeReplyModifier(isEnabled: true, onReply: {})
            )
        }
    }

    // MARK: - 装配

    private func installInWindow() {
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        container = UIViewController()
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 402, height: 874
        )
        controller.didMove(toParent: container)
    }

    private func drainRunLoop(seconds: TimeInterval) {
        RunLoop.main.run(
            until: Date().addingTimeInterval(seconds)
        )
    }

    private func probeRows() -> [ChatCarrierRow] {
        [
            ChatCarrierRow(
                key: "probe-user-swipe", entryID: UUID(),
                version: 1, estimatedHeight: 47,
                makeView: {
                    AnyView(self.userRowView(withSwipe: true))
                }
            ),
            ChatCarrierRow(
                key: "probe-user-noswipe", entryID: UUID(),
                version: 1, estimatedHeight: 47,
                makeView: {
                    AnyView(self.userRowView(withSwipe: false))
                }
            ),
            ChatCarrierRow(
                key: "probe-user-plaintext", entryID: UUID(),
                version: 1, estimatedHeight: 47,
                makeView: {
                    AnyView(self.userRowPlainTextView())
                }
            ),
            ChatCarrierRow(
                key: "probe-assistant", entryID: UUID(),
                version: 1, estimatedHeight: 230,
                makeView: { AnyView(self.assistantRowView()) }
            ),
            ChatCarrierRow(
                key: "probe-control", entryID: UUID(),
                version: 1, estimatedHeight: 60,
                makeView: {
                    AnyView(Color.clear.frame(height: 60))
                }
            ),
        ]
    }

    // MARK: - 探针 1：承载装配内的最终帧

    func testProbeCarrierFrames() {
        installInWindow()
        controller.apply(
            rows: probeRows(),
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
        drainRunLoop(seconds: 1.5)
        let sv = controller.scrollView
        print(
            "PROBE89 carrier contentSize=\(sv.contentSize) "
            + "contentInset=\(sv.contentInset) "
            + "offset=\(sv.contentOffset)"
        )
        guard let contentView = sv.subviews.first else {
            print("PROBE89 carrier NO contentView")
            return
        }
        let hosts = contentView.subviews.sorted {
            $0.frame.minY < $1.frame.minY
        }
        for (index, v) in hosts.enumerated() {
            print(
                "PROBE89 host[\(index)] frame=\(v.frame) "
                + "safeArea=\(v.safeAreaInsets)"
            )
            for sub in v.subviews {
                print(
                    "PROBE89 host[\(index)] sub frame=\(sub.frame)"
                )
            }
        }
    }

    // MARK: - 探针 2：独立 hosting controller 量测

    func testProbeStandaloneSizes() {
        let proposal = CGSize(
            width: 362, height: CGFloat.greatestFiniteMagnitude
        )
        let cases: [(String, AnyView)] = [
            ("user-swipe", AnyView(userRowView(withSwipe: true))),
            ("user-noswipe", AnyView(userRowView(withSwipe: false))),
            ("user-plaintext", AnyView(userRowPlainTextView())),
            ("assistant", AnyView(assistantRowView())),
        ]
        for (name, view) in cases {
            let hc = UIHostingController(rootView: view)
            let size = hc.sizeThatFits(in: proposal)
            print(
                "PROBE89 standalone \(name) outWindow "
                + "sizeThatFits=\(size)"
            )
        }
        // 窗口内：plain VC 子控制器、帧 (0,100,362,47)
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        container = UIViewController()
        window.rootViewController = container
        window.makeKeyAndVisible()
        for (name, view) in cases {
            let hc = UIHostingController(rootView: view)
            container.addChild(hc)
            container.view.addSubview(hc.view)
            hc.view.frame = CGRect(
                x: 20, y: 100, width: 362, height: 47
            )
            hc.didMove(toParent: container)
            drainRunLoop(seconds: 0.3)
            let size = hc.sizeThatFits(in: proposal)
            print(
                "PROBE89 standalone \(name) inWindow "
                + "sizeThatFits=\(size) "
                + "viewSafeArea=\(hc.view.safeAreaInsets)"
            )
            hc.willMove(toParent: nil)
            hc.view.removeFromSuperview()
            hc.removeFromParent()
        }
    }
}
