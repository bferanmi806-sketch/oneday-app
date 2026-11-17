import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §321（助手回复呈现与大厂对齐）装配断言：
/// ①原生散文 cell：助手行气泡面无填充（文本直
/// 落背景）、用户行填充逐值不变；助手行高与撤
/// 填充前同源公式一致（几何零改动＝高度产物不
/// 失效）；
/// ②顶簇底缘回报：TopBarGuideHostController 以
/// 活帧 convert 报顶簇在窗口里的真实底边（安全
/// 区＋实高），新面列表顶 inset 的单源供数成立。
@MainActor
final class ReplyRenderingAlignmentTests: XCTestCase {

    private final class RigWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func assembleWindow() {
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    private func makeSpec(
        isUser: Bool, content: String
    ) -> ChatNativeProseSpec {
        let traits = window.traitCollection
        let category = traits.preferredContentSizeCategory
        let boldText = traits.legibilityWeight == .bold
        var env = EnvironmentValues()
        env.colorScheme = traits.userInterfaceStyle == .dark
            ? .dark : .light
        func resolve(_ color: Color) -> UIColor {
            UIColor(cgColor: color.resolve(in: env).cgColor)
        }
        func components(_ color: Color) -> String {
            color.resolve(in: env).cgColor.components?
                .map { "\($0)" }.joined(separator: ",") ?? ""
        }
        let styleKey = [
            category.rawValue, boldText ? "b" : "r",
            components(Palette.bodyInk),
            components(Palette.inkSecondaryOnFill),
            components(Palette.userBubbleText),
        ].joined(separator: "|")
        let segments = ChatNativeProseAssembly.segments(
            isUser: isUser,
            content: content,
            styleKey: styleKey,
            baseFont: InlineTextFonts.baseFont(
                textStyle: .body, category: category,
                boldText: boldText
            ),
            overrideFont: { style in
                InlineTextFonts.baseFont(
                    textStyle: style, category: category,
                    boldText: boldText
                )
            },
            textColor: resolve(
                isUser ? Palette.userBubbleText : Palette.bodyInk
            ),
            dimmedColor: resolve(Palette.inkSecondaryOnFill),
            quoteTextColor: resolve(Palette.inkSecondaryOnFill)
        )
        return ChatNativeProseSpec(
            dividerText: nil,
            isUser: isUser,
            segments: segments ?? [],
            linkColor: resolve(Palette.primary),
            bubbleFill: resolve(
                isUser ? Palette.userBubbleFill : Palette.bubbleFill
            ),
            dividerColor: resolve(Palette.inkSecondary),
            quoteBarColor: resolve(Palette.inkMuted),
            highlightColor: resolve(Palette.primaryTint),
            highlighted: false,
            arrowIdleFill: resolve(Palette.fieldFill),
            arrowArmedFill: resolve(Palette.primaryPale),
            arrowIdleTint: resolve(Palette.inkSecondary),
            arrowArmedTint: resolve(Palette.onPrimary),
            menuPlainText: content,
            onMenuReply: {},
            onMenuFork: {},
            onMenuSelect: {},
            swipeEnabled: true,
            onSwipeReply: {},
            onSelectionChange: { _ in },
            openURL: { _ in }
        )
    }

    // MARK: - ① 助手无气泡填充／用户泡不变

    func testAssistantProseRowHasNoBubbleFillUserKeepsFill() {
        assembleWindow()
        let content = "这是一段助手回复正文，用来装配原生散文行。"

        let assistantRow = ChatNativeProseRowView(
            frame: CGRect(x: 0, y: 0, width: 362, height: 200)
        )
        assistantRow.configure(
            makeSpec(isUser: false, content: content)
        )
        assistantRow.layoutIfNeeded()
        let assistantFill = assistantRow.testBubbleView
            .backgroundColor
        XCTAssertTrue(
            assistantFill == nil
                || assistantFill!.cgColor.alpha == 0,
            "§321：助手行气泡面须无填充（文本直落背景），实得 \(String(describing: assistantFill))"
        )
        XCTAssertFalse(
            assistantRow.testTextViews.isEmpty,
            "助手行仍须承载正文本体"
        )

        let userRow = ChatNativeProseRowView(
            frame: CGRect(x: 0, y: 0, width: 362, height: 200)
        )
        let userSpec = makeSpec(isUser: true, content: content)
        userRow.configure(userSpec)
        userRow.layoutIfNeeded()
        XCTAssertEqual(
            userRow.testBubbleView.backgroundColor?.cgColor,
            userSpec.bubbleFill.cgColor,
            "用户泡填充须逐值不变"
        )
    }

    // MARK: - ② 顶簇底缘单源回报

    func testTopClusterBottomReportMatchesWindowFrame() throws {
        let rig = RigWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window = rig
        let root = UIViewController()
        rig.rootViewController = root
        rig.makeKeyAndVisible()

        let host = TopBarGuideHostController()
        var reported: [CGFloat] = []
        host.onBarBottomChange = { reported.append($0) }
        root.addChild(host)
        host.view.frame = root.view.bounds
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        host.updateBarContentHeight(52)
        rig.layoutIfNeeded()

        // 顶簇顶＝窗口安全区 59、高 52 → 底缘 111
        let last = try XCTUnwrap(
            reported.last,
            "§321：顶簇底缘须有回报（实报 \(reported))"
        )
        XCTAssertEqual(
            last, 111, accuracy: 1.5,
            "§321：顶簇底缘回报须＝安全区＋实高的活帧实测"
        )
        // 与活帧本体对账（同一帧、同一值）
        let liveBottom = host.traceBarView.convert(
            host.traceBarView.bounds, to: rig
        ).maxY
        XCTAssertEqual(
            last, liveBottom, accuracy: 0.6,
            "回报值须与顶簇宿主活帧底边逐值一致"
        )
    }
}
