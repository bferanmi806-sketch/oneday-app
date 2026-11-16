import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit

/// 抽屉容器（§156，用户 2026-11-11 20:58 亲递方案定
/// 调）：外层容器换 UIKit，现有 SwiftUI 页面与底栏
/// 一字不动。取代 0.17.0 的 SwiftUI 覆盖式 Drawer-
/// Shell——旧形态是抽屉自左滑入**盖在**静止内容之
/// 上（蒙层压暗）；新形态照用户方案与 Muse 本体
/// 形态：侧栏在后静止、**完整主页面整体右移**露出
/// 侧栏，右侧留一条明亮窄条，点窄条/左拖关闭，第
/// 一版不缩放。
/// §313（第 78 条＋横扫 A-01/A-02/A-21）在此形态上
/// 做变换对齐与内部收敛：抽屉层改与主面锁步同行、
/// travel 改宽×0.75、弹簧改慢阻尼定版、深色阴影归
/// 零；位移单源、阴影单写、几何/弹簧单源逐项见
/// 下结构注（宿主 safeAreaRegions 的 §313 清零已
/// 由 §317 订正为分界口径、见彼段）。
///
/// 结构（两个长期存在的 UIHostingController，开关
/// 抽屉从不重建——聊天滚动位/输入草稿/导航栈/生成
/// 中回复全靠它保住）：
/// - 底层 drawerHost：DrawerView，宽 travel；§313
///   起与前景锁步同行（第 78 条 D1）——关闭态整体
///   左移一个 travel 藏于主面之后（offset −travel），
///   开合时只写它自己的 transform.translationX＝
///   offset − travel，与前景构成同一刚性平移（Muse
///   录屏五帧拟合与 travel 全等，prep §2.3）。§156
///   初版「抽屉静止、前景右移露出（帘幕式）」就此
///   变更，抽屉根视图重建时机与帧口径（x 0/宽
///   travel）不变。
/// - 前景 wrapper → clip（圆角裁切层）→ contentHost
///   （现有 TabView）：主页面恒按容器全尺寸布局，
///   位移只写 wrapper.transform 的 translationX，
///   拖动期不改任何宽高约束、不逐帧动安全区
///   （0.6.1/0.17.0 两代「外层包裹扰动 TabView 安全
///   区、底栏下沉」的病根正是变换/量测加在 TabView
///   本人身上；本代变换只落在本容器自有的普通
///   UIView 上，TabView 在宿主内仍是零修饰根级
///   安放）。容器唯一位移事实源是 offset 一值：前景/
///   抽屉两层 transform 与全部呈现派生只在
///   applyOffset 一处写（A-01 收敛）。
/// - 阴影与裁切同层（§313 A-01 收敛）：柔影改挂
///   clip 本人（CALayer 语义：阴影按本层 alpha 形
///   状投射、clipsToBounds 只裁子层——阴影在裁切
///   区域之外、不被自裁），shadowPath 不再手写
///   （§182.2 的路径跟随圆角改由图层形状自动成
///   影，layout/applyOffset 双写点整删）；圆角仍走
///   DrawerMotion.cornerRadius 一步到位口径
///   （progress>0.02 即 54.5pt——§202 对 Muse 新参
///   照图量测拟合定值，出处见 DrawerCardGeometry
///   注；第 78 条录屏复测 ≈57pt 同档）；开态 clip
///   帧另按 DrawerMotion.verticalInset 纵向内嵌
///   （§202 K1）、整卡浮置。阴影 alpha 口径：第 78
///   条 D4——浅色按 §202 定值（峰值 0.22）、深色
///   归零（Muse 深色帧段无可量测阴影），派生走
///   DrawerMotion.shadowOpacity(progress:
///   appearance:) 单点。
/// - 宿主安全区（§317 分界口径，订正 §313 的
///   A-21 一刀切）：drawerHost/contentHost 两宿主
///   走默认 regions 派生、**不清零**——两宿主承载
///   的是常规安全区消费方（DrawerView 标题浮层与
///   .safeAreaBar 底条、其余四 Tab 页面），其安全
///   区只能由本层派生、没有下层真宿主自理；清零
///   纪律只适用于内容自管几何的宿主（聊天页内
///   ComposerGuideHost/TopBarGuideHost/列表行宿
///   主——它们各自手排几何、宿主派生只会叠成第二
///   份）。§313 曾把两宿主一并清零、.64 真机实证
///   误伤（身份行撞状态栏/底条进 Home 区），本口
///   径回到 .63 已验形态。
/// - 强黑蒙层整套退役（覆盖形态的分离手段）；分离
///   感由页卡圆角＋柔影＋窄条明亮承担。
///
/// 环境显式注入（方案点名）：宿主不继承桥的环境——
/// AppState、modelContext、locale、粗体映射在本桥
/// 读出后逐项写进两个宿主的根视图；.id(appLanguage)
/// 的整树重建在桥的上层（OneDayApp 根），切语言时
/// 本桥整体重建、宿主随之新建，口径与旧壳一致。
/// scenePhase/reduceTransparency/深色等走宿主 trait
/// 自动派生，不手工搬。
///
/// 手势（方案清单逐项）：
/// - 关闭态：左缘 24pt 热区（OneDayMetrics.drawer-
///   EdgeZone）UIPan 开抽屉；对系统返回手势让行——
///   本手势 require 系统边缘返回手势先失败（二级页
///   返回优先、根页返回手势即刻失败不拖开抽屉）。
/// - 打开态：前景窄条 UIPan 左拖跟手关＋点按关；
///   内容本体交互关闭（防穿透）；抽屉面上不挂横拖
///   手势，纵向滚动天然不被抢（旧壳抽屉面共用拖拽
///   手势的口径就此变更）。
/// - 跟手：DrawerMotion 方向锁定（10pt/1.5 倍）达
///   成前不写位移、纵向主导即取消本手势；写入走
///   followedOffset（扣锁定段＋橡皮筋），判定走
///   settleOpens（动量投影以速度×DrawerSpring-
///   Timing.settleProjectionInterval 近似）。
/// - 动画中再拖：停 animator 并从 presentation 层
///   当前 tx 接管，无跳变帧。
/// - 归位动画：UIViewPropertyAnimator＋UISpring-
///   TimingParameters（参数出 OneDayCore.Drawer-
///   SpringTiming 定版单源——§313 起 response 1.4/
///   ζ 1.2 慢阻尼档，MotionTokens.drawerSpring 只
///   以同字面值镜像、单测对钉；旧「双口径换算等
///   价」表述随换算层退役作废）；松手速度按相对位
///   移换算作初速交接；Reduce Motion 时瞬时归位。
/// - 打开先收键盘（旧纪律沿用）；VoiceOver：开态
///   抽屉出 a11y 树、内容退出，关态反之，切换时发
///   screenChanged（开→抽屉面、关→内容面；回触发
///   钮本体的精确落点真机验）。
///
/// 语义开合：AppState.router.drawerPresented 仍是各入口的
/// 写入面——ContentView 在 body 里读它并以 presented
/// 入参喂本桥（观察在 ContentView 层成立），桥在更
/// 新时与容器语义对账执行；容器侧手势/点按改变开
/// 合经 onPresentedChange 回写同一值， guard 防回环。
struct DrawerContainer<Content: View>: UIViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selection: ContentView.MainTab
    /// 语义开合（ContentView 以 appState.drawer-
    /// Presented 喂入；本桥据此与容器对账）
    var presented: Bool
    /// 抽屉频道行透传（0.36.29 沿用；2026-11-13 频
    /// 道一期起带频道 id——平台频道与 Hermes 频道
    /// 目的地不同，宿主按 id 分发）
    var onOpenChannel: (String) -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(
        context: Context
    ) -> DrawerContainerController {
        let controller = DrawerContainerController()
        let appState = appState
        controller.onPresentedChange = { newValue in
            if appState.router.drawerPresented != newValue {
                appState.router.drawerPresented = newValue
            }
        }
        apply(to: controller)
        controller.setDrawer(presented, animated: false)
        return controller
    }

    func updateUIViewController(
        _ controller: DrawerContainerController, context: Context
    ) {
        apply(to: controller)
        if controller.semanticPresented != presented {
            controller.setDrawer(presented, animated: true)
        }
    }

    /// 把当前 SwiftUI 侧状态（环境、回调、内容）刷进
    /// 容器：两个宿主的根视图以同型新值更新（SwiftUI
    /// 按身份 diff、宿主与页内 @State 不重建）；抽屉
    /// 宽随容器 travel 变时由容器回调本处 builder 重建
    private func apply(to controller: DrawerContainerController) {
        let appState = appState
        let modelContext = modelContext
        let locale = locale
        controller.reduceMotion = reduceMotion
        controller.drawerBuilder = { width in
            AnyView(
                DrawerView(
                    width: width,
                    currentTab: selection,
                    onSelectTab: { selection = $0 },
                    onClose: { controller.setDrawer(false, animated: true) },
                    onOpenChannel: onOpenChannel
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
                .environment(\.locale, locale)
                .boldTextMapping()
            )
        }
        controller.contentRoot = AnyView(
            content()
                .environment(appState)
                .environment(\.modelContext, modelContext)
                .environment(\.locale, locale)
                .boldTextMapping()
        )
    }
}

/// UIKit 抽屉容器本体（职责见 DrawerContainer 文件
/// 注）：只管两层宿主的安放、位移变换与手势/动画，
/// 不知道任何业务页面
final class DrawerContainerController: UIViewController,
    UIGestureRecognizerDelegate
{
    /// 开合语义（与 AppState.router.drawerPresented 对账的
    /// 容器侧副本；setDrawer 是唯一写口）
    private(set) var semanticPresented = false
    /// 推开量（§313：第 78 条 D2——容器宽×0.75、无
    /// cap，派生单源 DrawerCardGeometry.travel；旧
    /// 口径 min(宽×0.79, 400) 作废）
    private(set) var travel: CGFloat = 0
    /// Reduce Motion（桥注入；true 时归位瞬时）
    var reduceMotion = false
    /// 容器开合变化回写（桥接回 AppState）
    var onPresentedChange: ((Bool) -> Void)?
    /// 抽屉根视图 builder（桥注入；travel 变化时容器
    /// 以新宽重取根视图，闭包内回调恒取最新桥状态）
    var drawerBuilder: ((CGFloat) -> AnyView)? {
        didSet { rebuildDrawerRoot() }
    }
    /// 内容根视图（桥注入；赋值即刷进内容宿主）
    var contentRoot: AnyView? {
        didSet {
            if let contentRoot {
                contentHost.rootView = contentRoot
            }
        }
    }

    private let drawerHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    private let contentHost = UIHostingController<AnyView>(
        rootView: AnyView(EmptyView())
    )
    /// 前景变换层（只承 transform 与窄条手势；§313
    /// 起不再挂阴影——阴影已随裁切层同层收敛）
    private let foreground = UIView()
    /// 前景裁切层（圆角裁切＋柔影同层：阴影按本层
    /// alpha 形状自动投射、不被自裁，§313 A-01）
    private let clipView = UIView()
    /// 关闭态左缘热区（24pt；开态隐藏不挡抽屉）
    private let edgeView = UIView()

    /// 当前呈现位移（0…travel，橡皮筋段可越界；跟手
    /// 与动画的唯一事实源，与旧壳 S1 口径同构）——
    /// 前景/抽屉双层 transform 与圆角/阴影/命中/a11y
    /// 派生只许经 applyOffset 由本值写出（§313 A-01）
    private var offset: CGFloat = 0
    private var animator: UIViewPropertyAnimator?
    /// 手势会话：接管起点位移＋锁定段（nil＝未锁定）
    private var dragStartOffset: CGFloat = 0
    private var dragLockTranslation: CGFloat?

    private lazy var edgePan: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(
            target: self, action: #selector(handlePan(_:))
        )
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var stripPan: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(
            target: self, action: #selector(handlePan(_:))
        )
        recognizer.delegate = self
        recognizer.isEnabled = false
        return recognizer
    }()
    private lazy var stripTap: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self, action: #selector(handleStripTap)
        )
        recognizer.isEnabled = false
        return recognizer
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        // 容器底色＝页面底：抽屉材质（thinMaterial）
        // 向下采样到的就是它，取 Palette.pageBG 与旧
        // 覆盖形态下抽屉糊到的内容底色同族
        view.backgroundColor = UIColor(Palette.pageBG)

        // §317（A-21 分界订正）：两宿主安全区派生**不
        // 清零**、走默认 regions——.64 曾按 A-21 一刀
        // 切清零（原注称「内容安全区归 TabView 内真
        // 宿主自理」），但该立论只对聊天页成立：Drawer-
        // View 与其余四 Tab 都是常规安全区消费方（标
        // 题浮层靠安全区顶定位、底条是 .safeAreaBar），
        // 清零后身份行上移 59pt 撞状态栏、底条下沉
        // 34pt 进 Home 区（2026-11-17 真机定因，诊断
        // drawer-broken-diagnosis-20261117.md）。清零
        // 纪律自此按宿主性质分界：自管几何者（聊天页
        // 内 ComposerGuideHost/TopBarGuideHost/列表
        // 行宿主等）清零、常规消费方的承载宿主不列。
        // 本处恢复 .63 已验形态（默认派生、聊天页当
        // 时正常，无双份安全区）

        addChild(drawerHost)
        drawerHost.view.backgroundColor = .clear
        view.addSubview(drawerHost.view)
        drawerHost.didMove(toParent: self)
        drawerHost.view.isHidden = true

        view.addSubview(foreground)
        clipView.clipsToBounds = true
        clipView.layer.cornerCurve = .continuous
        // §313 A-01：柔影与裁切同层——阴影挂 clip 本
        // 人、按其 alpha 形状（圆角＋内嵌帧）自动投
        // 射，shadowPath 不设（手写路径双写点退役）；
        // radius/offset 定值出 DrawerCardGeometry 单
        // 源（经 DrawerMotion 转发），opacity 只在
        // applyOffset 随 progress 与外观派生
        clipView.layer.shadowColor = UIColor(Palette.shadowBase).cgColor
        clipView.layer.shadowRadius = DrawerMotion.shadowRadius
        clipView.layer.shadowOffset = CGSize(
            width: DrawerMotion.shadowX, height: 0
        )
        clipView.layer.shadowOpacity = 0
        foreground.addSubview(clipView)
        addChild(contentHost)
        contentHost.view.backgroundColor = .clear
        clipView.addSubview(contentHost.view)
        contentHost.didMove(toParent: self)
        foreground.addGestureRecognizer(stripPan)
        foreground.addGestureRecognizer(stripTap)

        edgeView.backgroundColor = .clear
        view.addSubview(edgeView)
        edgeView.addGestureRecognizer(edgePan)

        applyOffset(0)
    }

    /// 当前 progress 的前景裁切几何：圆角半径＋纵向内
    /// 嵌帧（§202 K1/K2）。layout 与 applyOffset 两写点
    /// 共用这一处派生——几何再多一个事实源就会打架：
    /// clip 帧＝前景 bounds 纵向内嵌 verticalInset(progress)
    /// （合态 0、开态满值、随 progress 线性行进）、半
    /// 径＝cornerRadius(progress)（一步到位、K4 不插值）。
    /// 内容宿主反向补偿：原点 −inset、高恒 bounds 高——
    /// 宿主在前景空间内的几何与 §202 之前逐值一致，浮
    /// 置只是裁切窗的事，内容布局/安全区/栏位冻结几何
    /// 一概不惊动（初版令宿主随 clip 同缩，CI
    /// run 43384697181 生产同构实测：抽屉关落定后输入
    /// 舱底 maxY −4pt 不复原，定因即宿主高被改写引发
    /// 托管树几何重排，故改补偿式）。§313：阴影不再
    /// 由本派生出手写路径——挂 clip 本人按其帧与半径
    /// 的 alpha 形状自动成影（§182.2 的「路径必须跟
    /// 随圆角」由图层语义结构性成立、双写点退役）
    private func clipGeometry(progress: CGFloat)
        -> (clipFrame: CGRect, contentFrame: CGRect, radius: CGFloat)
    {
        let radius = DrawerMotion.cornerRadius(progress: progress)
        let inset = DrawerMotion.verticalInset(progress: progress)
        let bounds = foreground.bounds
        let clipFrame = bounds.insetBy(dx: 0, dy: inset)
        let contentFrame = CGRect(
            x: 0, y: -inset,
            width: bounds.width, height: bounds.height
        )
        return (clipFrame, contentFrame, radius)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let newTravel = DrawerCardGeometry.travel(
            containerWidth: bounds.width
        )
        let travelChanged = newTravel != travel
        travel = newTravel
        // 抽屉未变换几何口径不变（原点 0/宽 travel/
        // 全高）：锁步靠 transform 承担（applyOffset
        // 写 offset−travel）。§313 起抽屉层同带
        // transform——与前景同一纪律：布局只准以
        // bounds＋center 写未变换几何，**不许写 frame**
        // （frame setter 会按当前 transform 反解
        // center：合态布局一趟就能把抽屉显示位补偿回
        // x=0、下次打开整体错位一个 travel）
        drawerHost.view.bounds = CGRect(
            origin: .zero,
            size: CGSize(width: travel, height: bounds.height)
        )
        drawerHost.view.center = CGPoint(
            x: travel / 2, y: bounds.midY
        )
        // 前景同纪律：transform 非 identity 时 frame
        // 未定义（Apple 文档明文），布局只准以 bounds
        // ＋center 写「未变换几何」、位移全部由
        // transform 承担。旧写法在此以 frame 重设——
        // animator 已把 model transform 承诺到目标
        // 值，frame setter 按当前 transform 反解 center，
        // 一次布局往返就把视觉位置补偿回原位（0.50.18
        // 真机抽屉打不开的定案主因：动画只剩布局触发前
        // 约 30pt 的呈现残移，见诊断报告与回归测试
        // testAnimatedOpenSurvivesMidFlightResize）
        foreground.bounds = CGRect(origin: .zero, size: bounds.size)
        foreground.center = CGPoint(x: bounds.midX, y: bounds.midY)
        // 帧派生同走 clipGeometry 单点（进度读当前
        // offset 实算，不读语义 presented——布局期可能
        // 先于手势/动画）。§313：本处不再写任何阴影
        // 路径——§182.2 的路径跟随圆角已由阴影挂 clip
        // 本人的图层语义结构性承担（帧/半径一变、影
        // 随形变），布局期只管帧
        let currentProgress = DrawerMotion.progress(
            offset: offset, travel: travel
        )
        let geometry = clipGeometry(progress: currentProgress)
        clipView.frame = geometry.clipFrame
        contentHost.view.frame = geometry.contentFrame
        edgeView.frame = CGRect(
            x: 0, y: 0,
            width: OneDayMetrics.drawerEdgeZone,
            height: bounds.height
        )
        if travelChanged {
            rebuildDrawerRoot()
            // 旋转/尺寸变：无拖无动画时按当前 offset 重
            // 派生一遍——开态位移跟到新 travel（主页面仍
            // 完整露出同一比例）；关态同理把抽屉锁步位
            // 钉到新 −travel（§313：合态抽屉恒藏于主面
            // 之后一个 travel、首次布局后即成立）
            if animator == nil, dragLockTranslation == nil {
                if semanticPresented {
                    offset = travel
                }
                applyOffset(offset)
            }
        }
    }

    private func rebuildDrawerRoot() {
        guard travel > 0, let drawerBuilder else { return }
        drawerHost.rootView = drawerBuilder(travel)
    }

    /// 外观（浅/深）切换：阴影口径随外观分叉（第 78
    /// 条 D4），以当前 offset 经唯一呈现口重派生一次
    /// （offset 不变、只换阴影口径；动画在途时 model
    /// 值已是目标值、重派生与飞行呈现同值不打架）
    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle
            != previousTraitCollection?.userInterfaceStyle {
            applyOffset(offset)
        }
    }

    // MARK: - 位移呈现

    /// 位移唯一呈现口：只写双层 transform（主页面布
    /// 局尺寸恒不变）＋圆角/阴影/命中/a11y 派生——全
    /// 容器不许有第二处写 transform 或阴影（§313
    /// A-01 单源收敛）
    private func applyOffset(_ newOffset: CGFloat) {
        offset = newOffset
        foreground.transform = CGAffineTransform(
            translationX: newOffset, y: 0
        )
        // 第 78 条 D1 锁步：抽屉层同刚体平移——位移＝
        // offset − travel（合态 −travel 藏于主面之后、
        // 开态 0 归位）；§317：越界段由 DrawerMotion
        // 钳制 [−travel, 0]（开向过冲不露容器底）；
        // travel 未量得（0）时恒 0 不动
        drawerHost.view.transform = CGAffineTransform(
            translationX: DrawerMotion.drawerOffset(
                offset: newOffset, travel: travel
            ),
            y: 0
        )
        let progress = DrawerMotion.progress(
            offset: newOffset, travel: travel
        )
        let geometry = clipGeometry(progress: progress)
        clipView.layer.cornerRadius = geometry.radius
        clipView.frame = geometry.clipFrame
        contentHost.view.frame = geometry.contentFrame
        // §313：阴影只在此写 opacity 一项——形状由
        // clip 本人的帧与半径自动成影（无手写路径）；
        // 外观口径第 78 条 D4：浅色走 §202 定值、深
        // 色归零，读容器当前 trait（随 trait 变化由
        // traitCollectionDidChange 以当前 offset 重派生）
        clipView.layer.shadowOpacity = Float(
            DrawerMotion.shadowOpacity(
                progress: progress,
                appearance: traitCollection.userInterfaceStyle == .dark
                    ? .dark : .light
            )
        )
        // 穿透防护：只要离开合位，内容本体不接触摸
        // （窄条的点/拖由前景手势承接）；全合位恢复。
        // §186.8 补修（Codex 异源复核）：归位动画在途
        // 时同样保持关闭——animator 的动画闭包在启动
        // 拍即以目标值调本函数（model 值同步落位），
        // 若只看 offset，关闭动画起始帧内容就已可点，
        // 而呈现层还在移动、舱的透传判定帧是布局快照
        // （transform 位移不触发 preference 更新）——
        // 点会落进正在移动的舱/列表。落定复位在
        // finishSettle（animator 已清零后按 offset
        // 终值重断言）；跟手拖动期 animator 恒为 nil
        // （接管时先停 animator），本条不改变拖动态
        // 语义（offset 本身即呈现事实）
        contentHost.view.isUserInteractionEnabled =
            newOffset <= 0 && animator == nil
        edgeView.isHidden = semanticPresented || newOffset > 0
    }

    // MARK: - 开合

    /// 开合统一走口：语义先行回写、动画随后；打开必
    /// 先收键盘（旧纪律）；Reduce Motion/无宽时瞬时
    func setDrawer(
        _ open: Bool, animated: Bool, velocityX: CGFloat = 0
    ) {
        if open {
            resignKeyboard()
            drawerHost.view.isHidden = false
        }
        semanticPresented = open
        onPresentedChange?(open)
        stripPan.isEnabled = open
        stripTap.isEnabled = open
        edgePan.isEnabled = !open
        let target = open ? travel : 0
        stopAnimatorCapturingPresentation()
        guard animated, !reduceMotion, travel > 0 else {
            applyOffset(target)
            finishSettle(open: open)
            return
        }
        let delta = target - offset
        var initialVelocity = CGVector.zero
        if abs(delta) > 1, abs(velocityX) > 1 {
            // UISpringTimingParameters 的初速以「每秒
            // 走完全程的比例」计：手势速度按相对位移
            // 换算，方向与目标同向才交接
            let relative = velocityX / delta
            if relative > 0 {
                initialVelocity = CGVector(dx: relative, dy: 0)
            }
        }
        let timing = UISpringTimingParameters(
            mass: 1,
            stiffness: DrawerSpringTiming.stiffness,
            damping: DrawerSpringTiming.damping,
            initialVelocity: initialVelocity
        )
        let animator = UIViewPropertyAnimator(
            duration: 0, timingParameters: timing
        )
        animator.addAnimations { [weak self] in
            self?.applyOffset(target)
        }
        animator.addCompletion { [weak self] position in
            guard let self, position == .end else { return }
            self.animator = nil
            self.finishSettle(open: open)
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func finishSettle(open: Bool) {
        if !open {
            drawerHost.view.isHidden = true
        }
        // §186.8：归位落定的交互复位——动画路径下
        // applyOffset 因 animator 在途恒置关闭，落定
        // （完成回调已先清 animator／瞬时路径本就无
        // animator）在此按 offset 终值放行；开态终值
        // >0、恒保持关闭
        contentHost.view.isUserInteractionEnabled = offset <= 0
        syncAccessibility(open: open)
    }

    /// VoiceOver 树切换：开态只留抽屉、关态只留内容；
    /// 焦点引导发 screenChanged（开→抽屉面、关→内容
    /// 面近似回触发侧，精确落点真机验）
    private func syncAccessibility(open: Bool) {
        drawerHost.view.accessibilityElementsHidden = !open
        contentHost.view.accessibilityElementsHidden = open
        UIAccessibility.post(
            notification: .screenChanged,
            argument: open ? drawerHost.view : contentHost.view
        )
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// 动画中再拖/再令：停 animator 并把 presentation
    /// 层的当前 tx 收回事实源——接管无跳变帧（S7 桥
    /// 接在 UIKit 侧的等价落法）
    private func stopAnimatorCapturingPresentation() {
        guard let animator, animator.isRunning else {
            self.animator = nil
            return
        }
        animator.pauseAnimation()
        if let presentation = foreground.layer.presentation() {
            offset = presentation.transform.m41
        }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
        self.animator = nil
        // 呈现位回写走唯一呈现口（§313：transform 不
        // 许有第二写点；animator 已清零、交互派生按
        // 捕获位成立，随后 setDrawer/手势流程再行对账）
        applyOffset(offset)
    }

    // MARK: - 手势

    @objc private func handleStripTap() {
        setDrawer(false, animated: true)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        switch recognizer.state {
        case .began:
            stopAnimatorCapturingPresentation()
            dragStartOffset = offset
            dragLockTranslation = nil
            if recognizer === edgePan {
                // 预挂载等价：抽屉树在锁定达成前先可见
                // （宿主本体恒在、此处只揭隐藏）
                drawerHost.view.isHidden = false
            }
        case .changed:
            if dragLockTranslation == nil {
                let dx = translation.x
                let dy = translation.y
                guard DrawerMotion.isDirectionLocked(dx: dx, dy: dy)
                else {
                    // 纵向主导过锁定距：本手势让行（其
                    // 下滚动面接不接得住这一下真机验，
                    // 与旧壳 SwiftUI 口径同界）
                    if abs(dy) >= DrawerMotion.directionLockDistance,
                       abs(dy) > abs(dx)
                    {
                        recognizer.state = .cancelled
                    }
                    return
                }
                dragLockTranslation = dx
                dragStartOffset = offset
            }
            let target = DrawerMotion.followedOffset(
                startOffset: dragStartOffset,
                translation: translation.x,
                lockTranslation: dragLockTranslation ?? 0,
                travel: travel
            )
            applyOffset(target)
        case .ended:
            let velocity = recognizer.velocity(in: view)
            let opens: Bool
            if dragLockTranslation != nil {
                opens = DrawerMotion.settleOpens(
                    currentOffset: offset,
                    startOffset: dragStartOffset,
                    predictedExtra: velocity.x
                        * DrawerSpringTiming.settleProjectionInterval,
                    velocityX: velocity.x,
                    travel: travel
                )
            } else {
                opens = semanticPresented
            }
            dragLockTranslation = nil
            // 触感矩阵条件项（体验三件规格 §2.3／表 D
            // 物理吸附）：手势拖拽吸附落位且状态真翻
            // 转才补 impact .light 一次；回弹原态不响、
            // 按钮开合不走本路（防腻清单：抽屉开合无
            // 触感，只给手势吸附这一处例外）
            if opens != semanticPresented {
                Haptics.impact(.light)
            }
            setDrawer(opens, animated: true, velocityX: velocity.x)
        case .cancelled, .failed:
            dragLockTranslation = nil
            setDrawer(semanticPresented, animated: true)
        default:
            break
        }
    }

    /// 手势仲裁：左缘手势须等系统边缘返回手势先失
    /// 败（二级页返回优先）；窄条手势与点按同属前景
    /// 时点按须等拖拽失败（拖动不误触发点按关）
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRequireFailureOf other: UIGestureRecognizer
    ) -> Bool {
        if recognizer === edgePan {
            return other is UIScreenEdgePanGestureRecognizer
        }
        if recognizer === stripTap {
            return other === stripPan
        }
        return false
    }

    /// 前景手势只在开态启用（stripPan/stripTap 的
    /// isEnabled 随语义切换）；左缘手势与内容滚动的
    /// 并行关系走系统默认（不声明 simultaneously，
    /// 保方向锁定语义）
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
