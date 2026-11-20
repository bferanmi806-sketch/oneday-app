import UIKit
import XCTest
@testable import OneDayApp

/// ComposerGuideHost 树内契约（2026-11-20 结构
/// 归位·对话页，纲要原则 3/4、D3-2）：本件的隐
/// 形层＝舱带——与顶簇背板同法：未喂入任何实测
/// 舱帧前带高恒 0（不入席）、帧到才按 A2 卡段公
/// 式成高；舱带恒在舱宿主之下；舱宿主 safeArea-
/// Regions 恒空。契约自检口＝控制器本体 assem-
/// blyContractViolations()，与生产装配同一判据
/// （区别于 ComposerGuideHostTests 的整壳几何
/// 验收：本文件只钉装配不变量、直挂控制器）。
@MainActor
final class ComposerAssemblyContractTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private func mountComposer() -> (
        UIWindow, ComposerGuideHostController
    ) {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        windows.append(window)
        let wrapper = UIViewController()
        let host = ComposerGuideHostController()
        wrapper.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints =
            false
        wrapper.view.addSubview(host.view)
        host.didMove(toParent: wrapper)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(
                equalTo: wrapper.view.leadingAnchor),
            host.view.trailingAnchor.constraint(
                equalTo: wrapper.view.trailingAnchor),
            host.view.topAnchor.constraint(
                equalTo: wrapper.view.topAnchor),
            host.view.bottomAnchor.constraint(
                equalTo: wrapper.view.bottomAnchor),
        ])
        window.rootViewController = wrapper
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return (window, host)
    }

    /// 装配初态：契约成立且舱带未入席（带高 0）
    /// ——隐形层不许在可见兄弟（舱本体）实测到
    /// 达之前独立存在
    func testContractHoldsAtAssemblyAndBandStaysOut() {
        let (window, host) = mountComposer()
        XCTAssertEqual(
            host.assemblyContractViolations(), [],
            "装配初态契约须成立"
        )
        window.layoutIfNeeded()
        XCTAssertEqual(
            host.traceBandView.frame.height, 0, accuracy: 1,
            "未喂实测帧时舱带高须为 0，实得 "
                + "\(host.traceBandView.frame.height)"
        )
    }

    /// 首帧到达后舱带入席（带高＝整栈帧底−卡帧
    /// 顶，A2 卡段公式），契约仍成立
    func testBandJoinsAfterFirstFrameAndContractHolds() {
        let (window, host) = mountComposer()
        host.updateBarFrame(
            CGRect(x: 0, y: 640, width: 402, height: 140)
        )
        host.updateCardFrame(
            CGRect(x: 0, y: 660, width: 402, height: 120)
        )
        window.layoutIfNeeded()
        XCTAssertEqual(
            host.traceBandView.frame.height, 120, accuracy: 1,
            "舱带高须＝栈底 780 −卡顶 660＝120，实得 "
                + "\(host.traceBandView.frame.height)"
        )
        XCTAssertEqual(
            host.assemblyContractViolations(), [],
            "舱带入席后契约须仍成立"
        )
    }
}
