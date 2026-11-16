import Foundation

/// 抽屉几何（0.3.6，DESIGN-V4 §21）：拖拽越界橡皮
/// 筋——界内 1:1 跟手由调用方钳制，本函数只处理越
/// 界量：按 Apple 材质口径的常用橡皮筋公式渐进衰
/// 减 effective = (x · W · c) / (W + c · x)，c =
/// 0.55；x→∞ 时趋近 W（永不超过一个容器宽），x→0
/// 时斜率趋近 c。审查备忘录 E-3 立项、0.3.6 落地
/// 于抽屉开合拖拽（此前为硬钳制、边界撞墙感）。
public enum DrawerGeometry {
    public static let rubberBandConstant: CGFloat = 0.55

    public static func rubberBand(
        overshoot: CGFloat, containerWidth: CGFloat
    ) -> CGFloat {
        let x = max(overshoot, 0)
        guard containerWidth > 0, x > 0 else { return 0 }
        return (x * containerWidth * rubberBandConstant)
            / (containerWidth + rubberBandConstant * x)
    }

    // MARK: - 底条钉底（0.3.8 第 22 条）

    /// 底条行高（圆钮 44 与搜索胶囊同高带，行盒 52）
    public static let bottomBarRowHeight: CGFloat = 52
    /// 底条下边距＝安全区底 inset＋4：底条落进原底栏
    /// 坑位（第 3 条抽屉开时底栏隐藏，坑位空出）
    public static func bottomBarBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom + 4
    }

    /// 底条中心距屏幕顶部的比例（量测口径）：852pt 屏、
    /// 安全区 34 时＝(852 − 34 − 4 − 26) / 852 ≈ 92.5%，
    /// 与 Muse 实测条中心 92.5% 对齐（0.3.7 实测旧值
    /// 77.5%、条下约 170pt 死白，本轮主犯）
    public static func bottomBarCenterFraction(
        screenHeight: CGFloat, safeAreaBottom: CGFloat
    ) -> Double {
        guard screenHeight > 0 else { return 0 }
        let fromBottom = bottomBarBottomPadding(safeAreaBottom: safeAreaBottom)
            + bottomBarRowHeight / 2
        return Double((screenHeight - fromBottom) / screenHeight)
    }
}

/// 抽屉卡几何定值单源（§313，横扫 A-02 收口）：圆角/
/// 纵向内嵌/柔影/推开量四组值此前散在容器现算与
/// DrawerMotion 白名单里逐代拟合追加，自此只许出自
/// 本结构体一处，出处逐项注明；DrawerMotion 的同名
/// 白名单改为转发本处、容器 travel 改走 travel(
/// containerWidth:) 派生，不再有第二写点。
public enum DrawerCardGeometry {
    /// 推开量占容器宽比例（第 78 条 D2）：Muse 录屏
    /// 逐帧实测 travel 301pt／402pt 屏宽＝75.0%±0.3%
    /// （drawer-transform-prep-20261114.md §2.2，四地
    /// 标 NCC 跟踪）。旧口径 min(宽×0.79, 400) 作废：
    /// 0.79 为 Muse 旧版抽屉宽占比化石、400 cap 在
    /// 402pt 屏上从未生效
    public static let travelWidthFraction: CGFloat = 0.75
    /// 前景卡圆角定值：§202 对 Muse 参照图拟合 54.5pt
    /// （出处见 DrawerMotion.cardCornerRadius 注）；
    /// 第 78 条录屏复测等效 ≈57pt、同档不改
    public static let cornerRadius: CGFloat = 54.5
    /// 圆角一步到位阈值（S3）：progress 过此值半径直
    /// 接到定值、拖动期不插值
    public static let cornerStepProgress: CGFloat = 0.02
    /// 纵向内嵌定值（§202 K1）：开态前景卡上/下各内
    /// 嵌此值、整卡浮置
    public static let verticalInset: CGFloat = 2
    /// 柔影定值（§202 回宽）：radius 18（定版区间
    /// 16–20 取中值偏上）/x −4
    public static let shadowRadius: CGFloat = 18
    public static let shadowX: CGFloat = -4
    /// 柔影峰值 alpha（progress=1、浅色）：§202 定
    /// 0.22（区间 0.18–0.25）；深色归零（第 78 条
    /// D4：Muse 录屏深色帧段无可量测阴影）
    public static let shadowMaxOpacity: Double = 0.22

    /// 推开量派生：容器宽 × 0.75、无 cap（量测口径见
    /// travelWidthFraction 注）
    public static func travel(containerWidth: CGFloat) -> CGFloat {
        containerWidth * travelWidthFraction
    }
}
