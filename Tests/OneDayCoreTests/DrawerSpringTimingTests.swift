import OneDayCore
import OneDayDesign
import XCTest

/// 抽屉弹簧定版单源（§313）：DrawerSpringTiming 是
/// 唯一事实源——定版值（response 1.4、ζ 1.2，第 78
/// 条 D3 慢阻尼档）逐项钉死、刚度/阻尼回算恒等；
/// MotionTokens.drawerSpring 只以同字面值镜像、两
/// 处对钉（§313 前的双口径换算层已退役）
final class DrawerSpringTimingTests: XCTestCase {

    func testTimingConstantsAreSlowDampedSpec() {
        XCTAssertEqual(DrawerSpringTiming.response, 1.4, accuracy: 0.0001)
        XCTAssertEqual(DrawerSpringTiming.dampingFraction, 1.2, accuracy: 0.0001)
        XCTAssertGreaterThan(DrawerSpringTiming.settleProjectionInterval, 0)
    }

    /// SwiftUI 镜像同值对钉：DesignTokens 的字面值与
    /// Core 定版逐项相等（改一处、另一处不对钉即红）
    func testMotionTokenMirrorMatchesSpec() {
        XCTAssertEqual(
            MotionTokens.drawerSpring,
            .interactiveSpring(
                response: DrawerSpringTiming.response,
                dampingFraction: DrawerSpringTiming.dampingFraction
            )
        )
    }

    func testStiffnessBackComputesToResponse() {
        // k＝(2π/1.4)²≈20.1；由 k 回算 response 恒等
        XCTAssertEqual(DrawerSpringTiming.stiffness, 20.1, accuracy: 0.5)
        let response = 2 * CGFloat.pi / sqrt(DrawerSpringTiming.stiffness)
        XCTAssertEqual(response, DrawerSpringTiming.response, accuracy: 0.0001)
    }

    func testDampingBackComputesToDampingFraction() {
        // c＝2×1.2×(2π/1.4)≈10.8；由 c、k 回算 ζ 恒等
        XCTAssertEqual(DrawerSpringTiming.damping, 10.8, accuracy: 0.2)
        let zeta = DrawerSpringTiming.damping
            / (2 * sqrt(DrawerSpringTiming.stiffness))
        XCTAssertEqual(zeta, DrawerSpringTiming.dampingFraction, accuracy: 0.0001)
        // ζ>1 过阻尼：Muse 点按开实测 ζ≈1.13 同档
        // （prep §2.5）——慢落位、无过冲，不许改回欠
        // 阻尼快档把手感带回 0.7.1 时代
        XCTAssertGreaterThan(zeta, 1)
    }
}
