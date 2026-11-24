import OneDayCore
import SwiftUI
import UIKit
import XCTest

@testable import OneDayApp

/// §480 渲染/托管探针（改前无此件）：
/// ①演示模式下动态页无帖数据（未连接态），行内新件
/// FeedLinkPreviewCard 无法在整机面上验——以 Image-
/// Renderer 离屏渲染两形态（带路径/根路径）落 PNG。
/// ②页头滚动收起同理无真列表可滚——以托管副本验机
/// 制：真 ContentPageHeader＋与 FeedView 同式的几何
/// 归一化公式（offset＋顶 inset）＋同阈值 24，断言
/// 静止偏移≈0、滚后 collapsed 置位，并落两帧 PNG。
final class FeedIdeasRenderProbeTests: XCTestCase {

    @MainActor
    func testRenderLinkPreviewCards() throws {
        let cases: [(String, BridgeFeedLink)] = [
            ("linkcard-path", BridgeFeedLink(
                title: "GitHub trending this week",
                url: "https://githubtrending.today/weekly"
            )),
            ("linkcard-root", BridgeFeedLink(
                title: "octo/hello：打招呼仓库",
                url: "https://github.com/octo/hello"
            )),
        ]
        for (name, link) in cases {
            let view = FeedLinkPreviewCard(link: link)
                .frame(width: 310)
                .padding(20)
                .background(Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            let data = try XCTUnwrap(image.pngData())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name).png")
            try data.write(to: url)
            print("RENDERED \(name) size=\(image.size) -> \(url.path)")
        }
    }

    // MARK: - 页头收起托管副本

    private final class CollapseFlag {
        var collapsed = false
        var restOffset: CGFloat?
        var maxOffset: CGFloat = 0
    }

    private struct CollapseReplica: View {
        let flag: CollapseFlag
        @State private var collapsed = false

        var body: some View {
            VStack(spacing: 0) {
                ContentPageHeader(
                    collapsed: collapsed,
                    onOpenHub: {}
                ) {
                    PageHeaderCircleButton(
                        symbol: "slider.horizontal.3",
                        label: "编辑简报"
                    ) {}
                }
                ScrollViewReader { proxy in
                    List {
                        ForEach(0..<40, id: \.self) { i in
                            Text("行 \(i)").id(i)
                        }
                    }
                    .listStyle(.plain)
                    .onScrollGeometryChange(
                        for: CGFloat.self
                    ) { geometry in
                        geometry.contentOffset.y
                            + geometry.contentInsets.top
                    } action: { _, newValue in
                        if flag.restOffset == nil {
                            flag.restOffset = newValue
                        }
                        flag.maxOffset = max(flag.maxOffset, newValue)
                        let next = newValue > 24
                        if next != collapsed {
                            collapsed = next
                            flag.collapsed = next
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 1.2
                        ) {
                            proxy.scrollTo(39, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testHeaderCollapseReplica() async throws {
        let flag = CollapseFlag()
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(
            rootView: CollapseReplica(flag: flag)
                .environment(AppState())
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await Task.sleep(for: .milliseconds(700))
        try capture(host.view, name: "header-rest")
        // 等滚动发生并收起（上限 6 秒轮询）
        var waited = 0
        while !flag.collapsed, waited < 60 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        try await Task.sleep(for: .milliseconds(600))
        try capture(host.view, name: "header-scrolled")
        print(
            "COLLAPSE restOffset=\(flag.restOffset ?? -999) "
                + "maxOffset=\(flag.maxOffset) "
                + "collapsed=\(flag.collapsed)"
        )
        XCTAssertTrue(flag.collapsed, "滚动后页头应收起")
        if let rest = flag.restOffset {
            XCTAssertLessThan(
                abs(rest), 1.5,
                "静止归一化偏移应≈0，实得 \(rest)"
            )
        }
    }

    @MainActor
    private func capture(_ view: UIView, name: String) throws {
        let renderer = UIGraphicsImageRenderer(
            bounds: view.bounds
        )
        let image = renderer.image { _ in
            view.drawHierarchy(
                in: view.bounds, afterScreenUpdates: true
            )
        }
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("CAPTURED \(name) -> \(url.path)")
    }
}
