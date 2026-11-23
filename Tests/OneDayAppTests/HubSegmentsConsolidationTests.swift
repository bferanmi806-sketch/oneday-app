import Combine
import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §434 枢纽五格注册表＋全页 push 呈现的装配门
/// （本文件前身为 §217 收段＋sheet 卡片式门，呈现
/// 与格集口径均由 §434 覆盖，逐项改写如下）：
/// ①格集由注册表裁决：裸装配（无回读、无 Box
///   钥）时可见段恒为锚格序首工作＋含身份、恒不
///   含邮箱（mail 位未广告）；格集全量裁决矩阵
///   在 Core HubSegmentRegistryTests 钉死；
/// ②通知落点改道：原指向任务/审核/监测三撤段的
///   落点全部落工作段（AgentHubView.segment
///   (for:) 纯映射）；
/// ③分段条量测钉（§222 值不变）；
/// ④呈现探针：中枢经 NavigationStack push 呈现
///   ——机制面硬断言（栈深 2、非 sheet、全页高、
///   关闭回栈深 1）；zoom 帧级形态在无场景裸窗
///   口里会退化，终验归真 App 回归门与真机录屏
///   并排比（本仓 rig≠真机的一贯口径）。
final class HubSegmentsConsolidationTests: XCTestCase {

    // MARK: - ① 注册表锚格

    func testAvailableSegmentsStartWithAnchors() {
        let segments = AgentHubView().availableSegments
        XCTAssertEqual(
            segments.first, .work,
            "格集序首恒为工作格（参照胶囊序）：\(segments)"
        )
        XCTAssertTrue(
            segments.contains(.identity),
            "身份锚格恒在：\(segments)"
        )
        XCTAssertFalse(
            segments.contains(.mail),
            "邮箱格在 mail 位未广告时不许长出：\(segments)"
        )
        XCTAssertFalse(
            segments.contains(.audit),
            "无回读活证时审核格不长（注册表纪律）：\(segments)"
        )
    }

    /// 注册表初值输入：Box 在位只认钥匙串真状态、
    /// 其余回读旗恒 false（回读后由 refreshSeg-
    /// mentInputs 刷新）
    func testInitialSegmentInputsAreHonest() {
        let inputs = AgentHubView.initialSegmentInputs()
        XCTAssertTrue(inputs.connected)
        XCTAssertFalse(inputs.grantsReadbackOK)
        XCTAssertFalse(inputs.approvalsReadbackOK)
        XCTAssertFalse(inputs.mailAdvertised)
        XCTAssertEqual(
            inputs.boxConfigured,
            KeychainStore.read(account: "box.mcp.key") != nil
        )
    }

    // MARK: - §222 分段条量测钉

    /// §222（枢纽页对 Muse 重建）：自绘胶囊条的三
    /// 个量测值钉死（对基准真机图：条高 48／选中胶
    /// 囊 36／图标 22），且条高不低于命中下限、胶囊
    /// 恒纳于条内——防后续顺手改值把对齐量测改没
    func testHubSegmentBarMetricsMatchParitySpec() {
        XCTAssertEqual(OneDayMetrics.hubSegBarHeight, 48)
        XCTAssertEqual(OneDayMetrics.hubSegCapsuleHeight, 36)
        XCTAssertEqual(OneDayMetrics.hubSegGlyphSize, 22)
        XCTAssertGreaterThanOrEqual(
            OneDayMetrics.hubSegBarHeight,
            OneDayMetrics.minTapTarget
        )
        XCTAssertLessThan(
            OneDayMetrics.hubSegCapsuleHeight,
            OneDayMetrics.hubSegBarHeight
        )
    }

    // MARK: - ② 落点改道

    func testRetiredSegmentDestinationsRerouteToWork() {
        XCTAssertEqual(
            AgentHubView.segment(for: .approvalDecision(id: "rec-1")),
            .work
        )
        XCTAssertEqual(
            AgentHubView.segment(for: .approvalHome),
            .work
        )
        XCTAssertEqual(
            AgentHubView.segment(
                for: .monitorChange(monitorID: "mon-1", changeID: "chg-1")
            ),
            .work
        )
        XCTAssertEqual(
            AgentHubView.segment(for: .monitorsHome),
            .work
        )
    }

    // MARK: - ④ push 全页呈现探针

    /// 呈现装配台：与 ChatView 同一目的地构造
    /// （navigationDestination＋hubFullPageChrome
    /// ＋zoom 转场，源为一枚占位源视图）
    private struct HubPushHarness: View {
        @ObservedObject var box: HubPresentationProbeBox
        @Namespace private var zoomNamespace

        var body: some View {
            NavigationStack {
                Color.clear
                    .overlay {
                        Color.gray
                            .frame(width: 67, height: 67)
                            .matchedTransitionSource(
                                id: "hubHero", in: zoomNamespace
                            )
                    }
                    .navigationDestination(isPresented: $box.presented) {
                        AgentHubView()
                            .hubFullPageChrome()
                            .navigationTransition(
                                .zoom(
                                    sourceID: "hubHero",
                                    in: zoomNamespace
                                )
                            )
                    }
            }
        }
    }

    @MainActor
    func testHubPushPresentationIsFullPageNotSheet() throws {
        let appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let box = HubPresentationProbeBox()
        let host = UIHostingController(
            rootView: HubPushHarness(box: box)
                .environment(appState)
                .modelContainer(container)
        )
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        spin(seconds: 0.6)

        // 导航控制器随栈渲染才进层级——轮询等它出现
        var navFound: UINavigationController?
        let navDeadline = Date().addingTimeInterval(8)
        while Date() < navDeadline {
            if let found = findNavigationController(in: host) {
                navFound = found
                break
            }
            spin(seconds: 0.016)
        }
        let nav = try XCTUnwrap(
            navFound,
            "装配台内应存在 NavigationStack 的导航控制器"
        )
        XCTAssertEqual(
            nav.viewControllers.count, 1,
            "呈现前栈深应为 1（根页）"
        )

        // 打开：等栈深变 2（中枢被 push）
        box.presented = true
        let presentDeadline = Date().addingTimeInterval(8)
        while Date() < presentDeadline {
            if nav.viewControllers.count == 2 { break }
            spin(seconds: 0.016)
        }
        XCTAssertEqual(
            nav.viewControllers.count, 2,
            "中枢应以 push 进入（栈深 2），实测 \(nav.viewControllers.count)"
        )
        let pushed = try XCTUnwrap(nav.topViewController)
        XCTAssertNil(
            pushed.sheetPresentationController,
            "中枢不许再走 sheet 呈现"
        )
        XCTAssertNil(
            host.presentedViewController,
            "push 呈现不产生 presentedViewController（非模态）"
        )
        // 全页：被推视图落定高应近整窗（sheet 卡式
        // 的留边/不满高在此不成立）
        spin(seconds: 0.6)
        let pushedFrame = pushed.view.convert(
            pushed.view.bounds, to: window
        )
        XCTAssertGreaterThan(
            pushedFrame.height, window.bounds.height - 1,
            "中枢页应满高全页：\(pushedFrame)"
        )

        // 关闭：回栈深 1
        box.presented = false
        let dismissDeadline = Date().addingTimeInterval(8)
        while Date() < dismissDeadline {
            if nav.viewControllers.count == 1 { break }
            spin(seconds: 0.016)
        }
        XCTAssertEqual(
            nav.viewControllers.count, 1,
            "关闭后应 pop 回根页（栈深 1），实测 \(nav.viewControllers.count)"
        )
    }

    /// 定位 SwiftUI NavigationStack 的内部导航控制
    /// 器：它不在 hosting 控制器的 children 链上
    /// （首轮探针实测），改走视图层级——先找
    /// UINavigationBar，再沿响应链上溯到拥有它的
    /// UINavigationController
    private func findNavigationController(
        in viewController: UIViewController
    ) -> UINavigationController? {
        if let nav = viewController as? UINavigationController {
            return nav
        }
        for child in viewController.children {
            if let found = findNavigationController(in: child) {
                return found
            }
        }
        guard let bar = findNavigationBar(in: viewController.view)
        else { return nil }
        var responder: UIResponder? = bar
        while let current = responder {
            if let nav = current as? UINavigationController {
                return nav
            }
            responder = current.next
        }
        return nil
    }

    private func findNavigationBar(in view: UIView) -> UIView? {
        if view is UINavigationBar { return view }
        for subview in view.subviews {
            if let found = findNavigationBar(in: subview) {
                return found
            }
        }
        return nil
    }

    private func spin(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }
}

/// 呈现开关探针盒（测试与装配台之间传呈现意图）
final class HubPresentationProbeBox: ObservableObject {
    @Published var presented = false
}
