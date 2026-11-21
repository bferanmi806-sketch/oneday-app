import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 连接页引导小包（2026-11-21，§335）的设备条件帧：
/// 分叉首屏（ConnectView 欢迎面）与通知权限段
/// （NotificationGuideView）在深色＋最大字号
/// （AX5＋粗体）两态下装配取帧。断言口径与既有装
/// 配探针同族：关键控件经无障碍标签在场；内容高在
/// AX 态实际生长（动态字号真到达版面、不被钉死字
/// 号吞掉——本包两面全部走文本样式档、无写死字号）。
@MainActor
final class ConnectGuideDeviceConditionTests: XCTestCase {

    /// 与既有组装探针同款设备窗（安全区覆写 59/34）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: UIWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    // MARK: - 装配

    private func assemble<V: View>(
        _ view: V, dark: Bool, boldAX: Bool
    ) -> UIHostingController<AnyView> {
        window?.rootViewController = nil
        window?.isHidden = true
        let host = UIHostingController(rootView: AnyView(view))
        let win = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        if dark {
            win.overrideUserInterfaceStyle = .dark
            host.overrideUserInterfaceStyle = .dark
        }
        if boldAX {
            host.traitOverrides.legibilityWeight = .bold
            host.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraLarge
            win.traitOverrides.legibilityWeight = .bold
            win.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraLarge
        }
        window = win
        win.rootViewController = host
        win.makeKeyAndVisible()
        win.layoutIfNeeded()
        spinRunLoop(seconds: 2)
        win.layoutIfNeeded()
        return host
    }

    private func assembleConnectView(
        dark: Bool, boldAX: Bool
    ) {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        _ = assemble(
            ConnectView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container),
            dark: dark, boldAX: boldAX
        )
    }

    private func assembleNotificationSegment(
        dark: Bool, boldAX: Bool
    ) -> UIHostingController<AnyView> {
        assemble(
            NotificationGuideView(
                state: .notDetermined,
                onRequest: {}, onOpenSettings: {}, onAdvance: {}
            )
            .environment(\.locale, AppLocale.uiLocale),
            dark: dark, boldAX: boldAX
        )
    }

    // MARK: - 取数（与组装探针同口径）

    private func collectAccessibilityLabels(
        in view: UIView
    ) -> [String] {
        var out: [String] = []
        if let label = view.accessibilityLabel {
            out.append(label)
        }
        if let elements = view.accessibilityElements {
            for element in elements {
                if let elementView = element as? UIView {
                    out.append(
                        contentsOf: collectAccessibilityLabels(
                            in: elementView
                        )
                    )
                } else if let object = element as? NSObject,
                          let label = object.accessibilityLabel {
                    out.append(label)
                }
            }
        }
        for sub in view.subviews {
            out.append(contentsOf: collectAccessibilityLabels(in: sub))
        }
        return out
    }

    private func windowLabels() -> [String] {
        guard let window else { return [] }
        return collectAccessibilityLabels(in: window)
    }

    /// 连接页滚动内容高（HostingScrollView 的
    /// contentSize；AX 生长断言的读数点）
    private func scrollContentHeight() -> CGFloat? {
        guard let window else { return nil }
        var found: UIScrollView?
        func walk(_ view: UIView) {
            if found != nil { return }
            if view is UIScrollView,
               String(describing: type(of: view))
                   .contains("HostingScrollView"),
               view.frame.width > 400 {
                found = view as? UIScrollView
                return
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        return found?.contentSize.height
    }

    // MARK: - 分叉首屏两帧

    /// 深色帧：分叉两路都在场（主按钮＋次按钮标签）
    func testWelcomeForkDarkFrame() {
        assembleConnectView(dark: true, boldAX: false)
        let labels = windowLabels()
        XCTAssertTrue(
            labels.contains("连接已有服务器"),
            "深色帧主路按钮缺席：\(labels)"
        )
        XCTAssertTrue(
            labels.contains("还没有服务器？了解部署"),
            "深色帧备路按钮缺席：\(labels)"
        )
        let height = scrollContentHeight() ?? 0
        XCTAssertGreaterThan(height, 0, "深色帧滚动内容高缺席")
        add(XCTAttachment(string:
            "forkDark labels=\(labels.count) contentH=\(height)"))
    }

    /// 最大字号帧：AX5＋粗体下内容高实际生长（分叉
    /// 两钮与细字全走文本样式档的回归守卫）
    func testWelcomeForkAccessibilitySizeFrame() {
        assembleConnectView(dark: false, boldAX: false)
        let baseHeight = scrollContentHeight() ?? 0
        XCTAssertGreaterThan(baseHeight, 0, "基线帧滚动内容高缺席")
        assembleConnectView(dark: false, boldAX: true)
        let axHeight = scrollContentHeight() ?? 0
        XCTAssertGreaterThan(
            axHeight, baseHeight,
            "AX 帧内容未生长：\(baseHeight)→\(axHeight)"
                + "（动态字号未到达分叉版面）"
        )
        let labels = windowLabels()
        XCTAssertTrue(
            labels.contains("连接已有服务器"),
            "AX 帧主路按钮缺席：\(labels)"
        )
        add(XCTAttachment(string:
            "forkAX baseH=\(baseHeight) axH=\(axHeight)"))
    }

    // MARK: - 通知权限段两帧

    /// 深色帧：未决定态的段面全件在场（主按钮＋跳
    /// 过＋两条用途标题）
    func testNotificationSegmentDarkFrame() {
        let host = assembleNotificationSegment(dark: true, boldAX: false)
        let labels = windowLabels()
        for expected in ["允许通知", "暂时跳过", "定时任务到点", "长任务完成"] {
            XCTAssertTrue(
                labels.contains(expected),
                "深色帧通知段缺「\(expected)」：\(labels)"
            )
        }
        let fit = host.sizeThatFits(
            in: CGSize(
                width: 402, height: CGFloat.greatestFiniteMagnitude
            )
        )
        XCTAssertGreaterThan(fit.height, 0, "深色帧通知段拟合高缺席")
        add(XCTAttachment(string:
            "notifDark labels=\(labels.count) fitH=\(fit.height)"))
    }

    /// 最大字号帧：段面拟合高实际生长
    func testNotificationSegmentAccessibilitySizeFrame() {
        let baseHost = assembleNotificationSegment(
            dark: false, boldAX: false
        )
        let baseFit = baseHost.sizeThatFits(
            in: CGSize(
                width: 402, height: CGFloat.greatestFiniteMagnitude
            )
        )
        XCTAssertGreaterThan(baseFit.height, 0, "基线帧通知段拟合高缺席")
        let axHost = assembleNotificationSegment(
            dark: false, boldAX: true
        )
        let axFit = axHost.sizeThatFits(
            in: CGSize(
                width: 402, height: CGFloat.greatestFiniteMagnitude
            )
        )
        XCTAssertGreaterThan(
            axFit.height, baseFit.height,
            "AX 帧通知段未生长：\(baseFit.height)→\(axFit.height)"
                + "（动态字号未到达权限段版面）"
        )
        add(XCTAttachment(string:
            "notifAX baseH=\(baseFit.height) axH=\(axFit.height)"))
    }
}
