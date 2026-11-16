import Foundation

/// 抽屉动效纯逻辑（0.7.1，chrome 裁决档 §3.5 S1–S8 的
/// 可测部分；档＝oneday-design-review/chrome-research-
/// 20261109.md，用户 2026-11-09 16:15 批准全案）：
/// 壳层只持一个 drawerOffset，本枚举管它的全部派生与
/// 判定——方向锁定（S2）、跟手位移换算（S2）、松手吸附
/// （S6）、圆角/阴影的白名单值（S3/§3.4）。弹簧本体在
/// OneDayDesign.MotionTokens.drawerSpring（S7）；挂载
/// 时机（S5）与呈现层接管（S7）在壳层 DrawerShell。
/// 0.17.0：抽屉改覆盖形态（调研报告 Q1/Q4 定案——被
/// 整体变换的页卡承载 TabView 是底栏下沉的病根），页
/// 卡退役，cornerRadius/shadowOpacity 自此无呈现层调
/// 用、保留作数据与回归钉；新增 scrimOpacity 承担覆
/// 盖形态的蒙层派生。位移三件（锁定/跟手/吸附）不变。
/// §313（第 78 条＋横扫 A-01/A-02）：几何定值单源迁
/// DrawerCardGeometry（本枚举同名白名单改转发）、新
/// 增 drawerOffset 锁步派生与深色阴影归零口径；位移
/// 三件与 scrim 化石保留不变。
public enum DrawerMotion {
    /// S2 方向锁定：累计横向位移达到此值前手势不接管、
    /// 不写任何位移状态（纵滚零干扰）
    public static let directionLockDistance: CGFloat = 10
    /// S2 方向锁定：横纵比门槛（|dx| ≥ 1.5×|dy| 才算横拖）
    public static let directionLockRatio: CGFloat = 1.5
    /// S6 fling 直通：松手速度朝目标向超此值不看位置
    /// 直接吸附（pt/s）
    public static let flingVelocity: CGFloat = 800
    /// S6 预测位移吸附阈值：动量投影相对手势起点的偏
    /// 移过 travel 的三成即吸附到对岸（现行阈值沿用，
    /// 已合 momentum 语义——裁决档 §3.5 S6）
    public static let settleFraction: CGFloat = 0.3
    /// S3 圆角一步到位阈值：progress 过此值圆角直接到
    /// 定值、拖动期不插值（逐帧改裁切半径＝整卡离屏
    /// 重合成，是 0.6.1 拖动卡顿主因之一，§1.5-2）。
    /// §313 起定值单源在 DrawerCardGeometry、本处只转发
    public static let cornerStepProgress: CGFloat =
        DrawerCardGeometry.cornerStepProgress
    /// 前景卡圆角定值（§202 对 Muse 新参照图重新拟
    /// 合定版：量测脚本 docs/drawer-edge-measurements/
    /// fit_corners.py——沿前景/底层亮度突变点采样做圆
    /// 拟合；参照图 5C33CA29…jpg 1206×2622、402 逻辑
    /// 宽 @3.0，顶弧 r＝158.5px、底弧 168.5px，四组独
    /// 立估计 156–174px，取池化中心 54.5pt；与纵向内
    /// 嵌走同心口径：r＋inset＝56.5pt，落在社区设备角
    /// 半径表 55–62pt 内。此前 43pt 是 §182.2 旧世代参
    /// 照（127d193a…jpg、393 逻辑宽、上角 132px）的拟
    /// 合值，随参照换代作废）。§313 起定值单源在
    /// DrawerCardGeometry、本处只转发
    public static let cardCornerRadius: CGFloat =
        DrawerCardGeometry.cornerRadius
    /// 纵向内嵌定值（§202 K1）：开态前景卡上/下各内嵌
    /// 此值、整卡浮置于抽屉面上，两弧连同顶/底短边完整
    /// 露出。参照图拟合顶 2.7pt/底 1.7pt（同上脚本），
    /// 对称取 2.0pt。§313 起定值单源在 DrawerCard-
    /// Geometry、本处只转发
    public static let cardVerticalInset: CGFloat =
        DrawerCardGeometry.verticalInset
    /// 柔影定值（§202 回宽）：§3.4 灰柱处方（radius 10
    /// /x −4、总宽约 20pt）的前提是平色近色面＋单条直
    /// 边、强阴影会摊成灰柱；K1/K2 后接缝主体是 54.5pt
    /// 大弧、要浮置必须有阴影绕角包裹，前提消失故回
    /// 宽——radius 18（定版区间 16–20，取中值偏上给大
    /// 弧留包裹宽度）。§313 起定值单源在 DrawerCard-
    /// Geometry、本处只转发
    public static let shadowRadius: CGFloat =
        DrawerCardGeometry.shadowRadius
    public static let shadowX: CGFloat =
        DrawerCardGeometry.shadowX
    /// 柔影峰值 alpha（progress=1 时）：§202 定 0.22
    /// （区间 0.18–0.25；开源同形态实现 eos 的 0.35×
    /// progress 是深底面参照，本 App 抽屉面浅色、取偏
    /// 低档）。拖动期 radius 与 x 冻结、只有 opacity 随
    /// progress 变（S3）。§313 起定值单源在 DrawerCard-
    /// Geometry、本处只转发
    public static let shadowMaxOpacity: Double =
        DrawerCardGeometry.shadowMaxOpacity
    /// 蒙层峰值 alpha（0.17.0 覆盖式抽屉）：页卡退役
    /// 后内容层静止不动，抽屉与内容的分离感改由滑入
    /// 抽屉下方的整屏蒙层承担（调研报告 Q4 结构 A）
    public static let scrimMaxOpacity: Double = 0.32

    /// S2 方向锁定判定：累计位移达标且横向主导才接管
    public static func isDirectionLocked(dx: CGFloat, dy: CGFloat) -> Bool {
        let ax = abs(dx)
        return ax >= directionLockDistance
            && ax >= directionLockRatio * abs(dy)
    }

    /// S1 派生语义：offset 过半记为开（供语义对账与命
    /// 中层开关；位移计算不读它——0.6.1 的 bool＋delta
    /// 双状态自此退役）
    public static func isOpen(offset: CGFloat, travel: CGFloat) -> Bool {
        travel > 0 && offset > travel / 2
    }

    /// S1 派生进度：钳制 0…1（橡皮筋越界段不放大进
    /// 度，缩放/阴影不被越界量带偏）
    public static func progress(offset: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        return min(max(offset / travel, 0), 1)
    }

    /// 抽屉层锁步位移（第 78 条 D1/§313；越界钳制
    /// §317）：抽屉层与主面是同一个刚性平移——关闭
    /// 态抽屉整体左移恰好一个 travel 藏于主面之后，
    /// 开合全程抽屉位移＝主面位移 − travel（Muse
    /// 录屏五帧拟合 D(p)＝−travel·(1−p)，与 travel
    /// 全等，drawer-transform-prep-20261114.md
    /// §2.3）。**界内公式一字不变**；越界段（橡皮筋
    /// 段）§317 起钳制到 [−travel, 0]：§313 的「不钳
    /// 制、双层同量越界」在真机录屏实证露底——开向
    /// 过冲时抽屉层被带过 0、左缘离屏左约 52pt 露
    /// 出容器底色（诊断 drawer-broken-diagnosis-
    /// 20261117.md F2），Muse 基准全程无露底。钳
    /// 制后开向过冲抽屉钉死 0（面板左缘恒贴屏左、
    /// 前景独走橡皮筋）、关向过冲抽屉停在 −travel
    /// （整份藏好不深追）；前景橡皮筋手感与界内锁
    /// 步刚性均不受影响。travel 未量得（0）时恒 0
    public static func drawerOffset(
        offset: CGFloat, travel: CGFloat
    ) -> CGFloat {
        guard travel > 0 else { return 0 }
        return min(max(offset - travel, -travel), 0)
    }

    /// S2 跟手位移：接管后写入值扣除锁定段（消除旧实
    /// 现「含判定段全量写入」的起步跳，§1.5-5）；界内
    /// 1:1，越界段走 DrawerGeometry 橡皮筋（c＝0.55，
    /// §3.5 S2 维持不动）
    /// - startOffset: 接管瞬间的呈现位移
    /// - translation: 手势当前全量横向位移（自手势起点）
    /// - lockTranslation: 接管瞬间的手势横向位移（锁定段）
    public static func followedOffset(
        startOffset: CGFloat,
        translation: CGFloat,
        lockTranslation: CGFloat,
        travel: CGFloat
    ) -> CGFloat {
        let target = startOffset + (translation - lockTranslation)
        if target > travel {
            return travel + DrawerGeometry.rubberBand(
                overshoot: target - travel, containerWidth: travel
            )
        }
        if target < 0 {
            return -DrawerGeometry.rubberBand(
                overshoot: -target, containerWidth: travel
            )
        }
        return target
    }

    /// S6 松手吸附：fling 直通优先；否则以动量预测增
    /// 量外推——相对手势接管起点的总偏移过 30% travel
    /// 吸附到对岸（开向/合向同阈，沿现行口径）
    /// - currentOffset: 松手瞬间位移
    /// - startOffset: 本次手势接管时的位移（定开/合向）
    /// - predictedExtra: predictedEndTranslation − translation（动量外推增量）
    /// - velocityX: 松手速度（pt/s，右为正）
    public static func settleOpens(
        currentOffset: CGFloat,
        startOffset: CGFloat,
        predictedExtra: CGFloat,
        velocityX: CGFloat,
        travel: CGFloat
    ) -> Bool {
        guard travel > 0 else { return false }
        if velocityX > flingVelocity { return true }
        if velocityX < -flingVelocity { return false }
        let relative = (currentOffset - startOffset) + predictedExtra
        if startOffset < travel / 2 {
            return relative > travel * settleFraction
        }
        return relative > -travel * settleFraction
    }

    /// S3 圆角：progress 过阈一步到定值（拖动期冻结）
    public static func cornerRadius(progress: CGFloat) -> CGFloat {
        progress > cornerStepProgress ? cardCornerRadius : 0
    }

    /// 内嵌随 progress 线性行进（§202 K1）：合态 0、开
    /// 态满值。帧写与 transform 同拍；与 K4「半径不逐
    /// 帧插值」不冲突——防卡顿定案管的是裁切路径重建，
    /// 内嵌只是帧位移、无路径重算
    public static func verticalInset(progress: CGFloat) -> CGFloat {
        cardVerticalInset * min(max(progress, 0), 1)
    }

    /// S3/§3.4 阴影不透明度：白名单内唯一随 progress
    /// 变的阴影属性（浅色口径；深色见下方带外观参数
    /// 的重载）
    public static func shadowOpacity(progress: CGFloat) -> Double {
        shadowMaxOpacity * Double(min(max(progress, 0), 1))
    }

    /// 阴影外观（第 78 条 D4）：Muse 录屏深色帧段无
    /// 可量测阴影（缘口 1–2px 抗锯齿内完成亮度跳变、
    /// 无柔影带），深色口径归零；浅色保留 §202 定值
    /// （双口径各待一次真机对账）
    public enum ShadowAppearance {
        case light
        case dark
    }

    /// 带外观的阴影不透明度：深色恒 0、浅色走 S3 口径
    public static func shadowOpacity(
        progress: CGFloat, appearance: ShadowAppearance
    ) -> Double {
        switch appearance {
        case .dark:
            return 0
        case .light:
            return shadowOpacity(progress: progress)
        }
    }

    /// 蒙层不透明度（0.17.0）：随 progress 线性、两端
    /// 钳制——橡皮筋越界段不放大蒙层（与 progress 的
    /// 钳制口径一致，越界只动抽屉本体）
    public static func scrimOpacity(progress: CGFloat) -> Double {
        scrimMaxOpacity * Double(min(max(progress, 0), 1))
    }
}
