import Foundation

/// 抽屉弹簧定版（§313 换代；UIKit 容器专用）：本枚
/// 举是全仓唯一弹簧事实源——response/ζ 只在此处定
/// 版，UIKit 刚度/阻尼由此派生（单位质量：ω＝2π/
/// response、k＝ω²、c＝2ζω；回算 ζ＝c/(2√k)、
/// response＝2π/√k 恒等，单测钉死）。SwiftUI 侧
/// MotionTokens.drawerSpring 是同值镜像（新壳层无
/// SwiftUI 消费方、只供令牌册完整性），两处字面值由
/// 单测逐项对钉——§313 前「DrawerSpringTiming 换算
/// MotionTokens」的双口径换算层就此退役，不再有第
/// 三处弹簧参数。
///
/// 定版值（第 78 条 D3）：response 1.4／ζ 1.2——
/// Muse 录屏点按开弹簧段以 iOS 26 UISpringTiming-
/// Parameters 同构时序实测 ζ≈1.13、可见时长 ≈1.51s
/// （snappy 预设同级；drawer-transform-prep-
/// 20261114.md §2.5），首版取此档：过阻尼、无过冲、
/// 慢落位。旧值 response 0.34/ζ 0.86（0.7.1 S7 跟手
/// 位移档）作废。
public enum DrawerSpringTiming {
    /// 弹簧定版 response（秒；与 MotionTokens.
    /// drawerSpring 镜像同值，单测对钉）
    public static let response: CGFloat = 1.4
    /// 弹簧定版阻尼比 ζ（过阻尼、无过冲；与
    /// MotionTokens.drawerSpring 镜像同值，单测对钉）
    public static let dampingFraction: CGFloat = 1.2
    /// 松手吸附的动量投影时长：UIKit 手势无 SwiftUI
    /// 的 predictedEndTranslation，以「速度 × 本时长」
    /// 近似其外推增量后仍走 DrawerMotion.settleOpens
    /// 同一判定（判定口径不分家）
    public static let settleProjectionInterval: CGFloat = 0.22

    /// 弹簧刚度 k（质量恒 1）
    public static var stiffness: CGFloat {
        let omega = 2 * CGFloat.pi / response
        return omega * omega
    }

    /// 弹簧阻尼 c（质量恒 1）
    public static var damping: CGFloat {
        let omega = 2 * CGFloat.pi / response
        return 2 * dampingFraction * omega
    }
}
