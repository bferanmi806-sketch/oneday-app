import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §327（小修批②）顶簇不透明背板装配断言：改前
/// 结构（git 基线）＝顶簇宿主视图背景 .clear、无
/// 任何背板子视图，滚动态正文隔半透明胶囊与柔
/// 边可读（同根审计 §3.4）；改后断言——
/// ①背板在席且恒在顶簇宿主之下（子视图序）；
/// ②背板色＝Palette.chatSurface 按当前 trait 解
/// 析值、alpha＝1（与页面底同令牌同值：静止不
/// 可见、滚动全遮蔽）；
/// ③背板窗口系帧覆盖全带：顶抵窗口顶（y＝0）、
/// 底贴顶簇底、宽＝窗宽；
/// ④宿主帧被下移（SwiftUI 挪帧的补偿场景）时背
/// 板仍抵窗口顶、顶簇落点仍为窗口顶安全区（§195
/// 几何不退）。
@MainActor
final class TopBarBackingPlateTests: XCTestCase {

    /// 设备窗口（与 EdgeEffectRegistrationTests
    /// 同式：覆写真机安全区顶 62／底 34）
    private final class PlateDeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        }
    }

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// barHeight 传 nil＝不喂实测高：模拟内容链
    /// 缺席帧（空根停留/量测未达），供闸门断言用
    private func mountTopHost(
        topOffset: CGFloat, barHeight: CGFloat?
    ) -> (PlateDeviceWindow, TopBarGuideHostController) {
        let window = PlateDeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        windows.append(window)
        let wrapper = UIViewController()
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints =
            false
        wrapper.view.addSubview(container)
        let host = TopBarGuideHostController()
        wrapper.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints =
            false
        container.addSubview(host.view)
        host.didMove(toParent: wrapper)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(
                equalTo: wrapper.view.leadingAnchor),
            container.trailingAnchor.constraint(
                equalTo: wrapper.view.trailingAnchor),
            container.topAnchor.constraint(
                equalTo: wrapper.view.topAnchor,
                constant: topOffset),
            container.bottomAnchor.constraint(
                equalTo: wrapper.view.bottomAnchor),
            host.view.leadingAnchor.constraint(
                equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(
                equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(
                equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(
                equalTo: container.bottomAnchor),
        ])
        window.rootViewController = wrapper
        window.makeKeyAndVisible()
        if let barHeight {
            host.updateBarContentHeight(barHeight)
        }
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        window.layoutIfNeeded()
        return (window, host)
    }

    private func assertColor(
        _ actual: UIColor?, equalsChatSurfaceIn window: UIWindow,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let traits = window.traitCollection
        let expected = UIColor(Palette.chatSurface)
            .resolvedColor(with: traits)
        let resolved = actual?.resolvedColor(with: traits)
        var er: CGFloat = 0, eg: CGFloat = 0
        var eb: CGFloat = 0, ea: CGFloat = 0
        var ar: CGFloat = 0, ag: CGFloat = 0
        var ab: CGFloat = 0, aa: CGFloat = 0
        expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        XCTAssertNotNil(resolved, "背板无背景色", file: file, line: line)
        resolved?.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        XCTAssertEqual(ar, er, accuracy: 0.01, "背板 R 与 chatSurface 脱钩", file: file, line: line)
        XCTAssertEqual(ag, eg, accuracy: 0.01, "背板 G 与 chatSurface 脱钩", file: file, line: line)
        XCTAssertEqual(ab, eb, accuracy: 0.01, "背板 B 与 chatSurface 脱钩", file: file, line: line)
        XCTAssertEqual(aa, 1, accuracy: 0.01, "背板须不透明（alpha＝1），实得 \(aa)", file: file, line: line)
    }

    // MARK: - ①②③ 静止装配：背板在席、实色、全带覆盖

    func testBackingPlateCoversBandWithChatSurface() throws {
        let (window, host) = mountTopHost(
            topOffset: 0, barHeight: 52
        )
        let backing = host.traceBackingView
        let bar = host.traceBarView

        // ① 在席且在顶簇宿主之下
        let subviews = host.view.subviews
        let backingIndex = try XCTUnwrap(
            subviews.firstIndex(of: backing),
            "背板不在宿主子视图内"
        )
        let barIndex = try XCTUnwrap(
            subviews.firstIndex(of: bar),
            "顶簇宿主不在子视图内"
        )
        XCTAssertLessThan(
            backingIndex, barIndex,
            "背板须在顶簇宿主之下（序 \(backingIndex) vs \(barIndex)）"
        )

        // ② 实色＝chatSurface、alpha＝1
        assertColor(
            backing.backgroundColor, equalsChatSurfaceIn: window
        )

        // ③ 窗口系全带覆盖：顶 0、底＝顶簇底、宽＝窗宽
        let backingFrame = backing.convert(backing.bounds, to: window)
        let barFrame = bar.convert(bar.bounds, to: window)
        print(
            "TOPBAR-PLATE backing=\(backingFrame) bar=\(barFrame)"
        )
        XCTAssertEqual(
            backingFrame.minY, 0, accuracy: 1,
            "背板顶须抵窗口顶，实得 \(backingFrame.minY)"
        )
        XCTAssertEqual(
            backingFrame.maxY, barFrame.maxY, accuracy: 1,
            "背板底须贴顶簇底，\(backingFrame.maxY) vs \(barFrame.maxY)"
        )
        XCTAssertEqual(
            backingFrame.width, 402, accuracy: 1,
            "背板宽须满窗，实得 \(backingFrame.width)"
        )
        // 顶簇落点不退（§195）：顶＝窗口顶安全区 62
        XCTAssertEqual(
            barFrame.minY, 62, accuracy: 1,
            "顶簇顶须为窗口顶安全区 62，实得 \(barFrame.minY)"
        )
    }

    // MARK: - ④ 宿主帧下移：背板补偿抵窗口顶

    func testBackingPlateCompensatesShiftedHostFrame() throws {
        let (window, host) = mountTopHost(
            topOffset: 49, barHeight: 52
        )
        let backing = host.traceBackingView
        let bar = host.traceBarView
        let backingFrame = backing.convert(backing.bounds, to: window)
        let barFrame = bar.convert(bar.bounds, to: window)
        print(
            "TOPBAR-PLATE-SHIFTED backing=\(backingFrame) "
                + "bar=\(barFrame)"
        )
        XCTAssertEqual(
            barFrame.minY, 62, accuracy: 1,
            "宿主下移 49 时顶簇须补偿回安全区 62，实得 \(barFrame.minY)"
        )
        XCTAssertEqual(
            backingFrame.minY, 0, accuracy: 1,
            "宿主下移时背板顶须仍抵窗口顶，实得 \(backingFrame.minY)"
        )
        XCTAssertEqual(
            backingFrame.maxY, barFrame.maxY, accuracy: 1,
            "背板底须贴顶簇底，\(backingFrame.maxY) vs \(barFrame.maxY)"
        )
        assertColor(
            backing.backgroundColor, equalsChatSurfaceIn: window
        )
    }

    // MARK: - ⑤ 内容链缺席：背板不入席（2026-11-20 白块兜底）

    /// 故障帧复刻：控制器已装配、内容链未交付
    /// （未报任何实测高——空根停留/量测未达同形）
    /// ——背板须 hidden，带内退回透明形态，物理上
    /// 不再可能「只剩实心白块」；序位不因闸门变
    /// （仍在顶簇宿主之下在席，§213 注册序位断言
    /// 的前提不变）
    func testBackingStaysHiddenUntilFirstMeasuredHeight() throws {
        let (_, host) = mountTopHost(
            topOffset: 0, barHeight: nil
        )
        let backing = host.traceBackingView
        XCTAssertTrue(
            backing.isHidden,
            "未报实测高时背板须 hidden，实得 isHidden="
                + "\(backing.isHidden)"
        )
        let subviews = host.view.subviews
        XCTAssertEqual(
            subviews.count, 2,
            "闸门不许改子视图构成，实得 \(subviews.count) 层"
        )
        XCTAssertTrue(subviews.first === backing)
        XCTAssertTrue(subviews.last === host.traceBarView)
    }

    /// 另一向：首个实测高到达后背板入席，§327 的
    /// 在席/实色/全带覆盖语义原样恢复；且闸门是
    /// 单向闩——其后量测变化（进展胶囊生长）不许
    /// 把它翻回 hidden
    func testBackingJoinsAfterFirstMeasuredHeight() throws {
        let (window, host) = mountTopHost(
            topOffset: 0, barHeight: nil
        )
        let backing = host.traceBackingView
        XCTAssertTrue(backing.isHidden)

        host.updateBarContentHeight(52)
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.3)
        window.layoutIfNeeded()

        XCTAssertFalse(
            backing.isHidden,
            "报出首个实测高后背板须入席"
        )
        let backingFrame = backing.convert(
            backing.bounds, to: window
        )
        let barFrame = host.traceBarView.convert(
            host.traceBarView.bounds, to: window
        )
        XCTAssertEqual(
            backingFrame.minY, 0, accuracy: 1,
            "入席后背板顶须抵窗口顶，实得 \(backingFrame.minY)"
        )
        XCTAssertEqual(
            backingFrame.maxY, barFrame.maxY, accuracy: 1,
            "入席后背板底须贴顶簇底，\(backingFrame.maxY) vs \(barFrame.maxY)"
        )
        assertColor(
            backing.backgroundColor, equalsChatSurfaceIn: window
        )

        host.updateBarContentHeight(104)
        XCTAssertFalse(
            backing.isHidden,
            "闸门单向：后续量测变化不许翻回 hidden"
        )
    }

    // MARK: - ⑥ 树内契约（2026-11-20 结构归位·对话页）

    /// 契约在内容缺席态成立：覆盖序/闸门初态/安全
    /// 区纪律三条全过——「内容缺席时背板不可见」
    /// 自此是装配不变量、不是单点行为巧合
    func testAssemblyContractHoldsWhenContentAbsent() {
        let (_, host) = mountTopHost(
            topOffset: 0, barHeight: nil
        )
        XCTAssertEqual(
            host.assemblyContractViolations(), [],
            "内容缺席态装配契约须成立"
        )
    }

    /// 契约在内容入席后仍成立：闸门翻转不破契约
    /// （宿主下移补偿场景同验）
    func testAssemblyContractHoldsAfterFirstMeasure() {
        let (_, host) = mountTopHost(
            topOffset: 49, barHeight: 52
        )
        XCTAssertEqual(
            host.assemblyContractViolations(), [],
            "内容入席后装配契约须成立"
        )
    }
}
