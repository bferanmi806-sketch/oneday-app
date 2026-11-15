import OneDayCore
import SwiftUI
import UIKit

/// 会话页原生重建 R1＋R2（DESIGN §291/§293，施工
/// 图 chat-native-rebuild-blueprint-20261115 §五）：
/// ChatRootViewController＋UICollectionView（正
/// 向、不倒置）＋UICollectionViewDiffableDataSource
/// ＋compositional 单列布局。落定行全集以
/// UIHostingConfiguration 托管现有 SwiftUI 行内容
/// 进 cell（内容本体一字不动）；直播区自 R2 起逐
/// 项入快照（ChatView nativeLiveRow，§293）；输入
/// 舱自 R2 起收编为本容器子托管——落位原钉本视图
/// keyboardLayoutGuide（H8），§299 起改回 §194
/// 通知帧顶单常量形态（见下 H8 沿革）。
///
/// 几何纪律（施工图 §四硬约束）：
/// - H1 间距单源：相邻消息纵向间距只由 section
///   的 interGroupSpacing 一处声明（spacingL 24）；
///   cell 内容不带任何泡外纵 padding，时间分隔仍
///   长在条目 cell 内（ChatView 行内容自带）。
/// - H2/H10 行高单权威、无帧表：本类没有任何帧
///   表、任何量实回填——行高预量只出 ChatView 的
///   产物层估算（喂 compositional 的 .estimated 占
///   位），物化后由集合视图自适应收敛，contentSize
///   只由集合视图自己持有；托管拟合高永不回写。
/// - H3 短内容底锚定：内容高＜有效视口时，按系
///   统实测 contentSize 派生一笔顶 inset（单点记
///   账、随实测重算），末行底→舱顶与长内容同值。
/// - H6 落点＝真实布局后的最大 offset：落定拍在
///   layoutIfNeeded 后按系统 contentSize 钉底；收
///   敛（自适应行高修正）后落点意图未消则同拍重
///   钉；用户接管（拖动）即消意图。
/// - H7 距底永远现测：全部判定在决策时刻现读
///   contentSize／contentOffset／adjusted 标尺计
///   算，不缓存事实位。
/// - 与 gen3 容器的关系：本面与 gen3 面共用同一
///   句柄形态（同形不同型，见 ChatNativeList-
///   Handle）；ChatView 跟随/锚链只认句柄、不为
///   本面再抄一份。喂入只剩顶 inset 与单点边距两
///   笔（§263 口径同源）；底几何自 R2 起全由本容
///   器内实测派生（见 H8）。
/// - H8 键盘跟随（R2 换代→§299 回 §194 形态）：
///   R2 曾定「只走 keyboardLayoutGuide」——舱底
///   钉本视图引导线顶、引导线逐帧驱动。2026-
///   11-16 用户 .59 真机录屏证伪（定因报告 key-
///   board-rise-diagnosis-20261116）：引导线在本
///   层级（SwiftUI 托管内嵌控制器）真机不追踪真
///   键盘、舱全程钉坞位被键盘盖住，与 §193→
///   §194 病史同族；其真机门 A2/A3 从未回填即
///   随 .59 转默认。§299 落位回 §194 形态：舱底
///   恒钉自有位置引导线 bottomGuide，其 top 常
///   量只由 syncBottomConstant 一个函数算——键
///   盘态＝通知广播的结束帧顶（窗口坐标）、静息
///   态＝坞实测顶、无坞回落窗口安全区底；状态翻
///   转与帧变化以通知动画参数原值推进布局（时
///   长 0 的逐帧事件直接布局）。keyboardLayout-
///   Guide 自此退出驱动位、只在事件拍作采样对
///   照记入自述（预期仍停静息值、即根因本人）。
///   列表底 inset 仍每拍由舱子托管实测帧一处派
///   生（量测→对账→在底同拍钉底，全在布局拍/
///   落定拍内），此半边 R2 口径不变。ChatView
///   侧键盘锚定挂账链在本面仍不消费（gen3/旧面
///   照旧）；但 kbSnapshot 供数自 §299 起同源
///   收口：同一通知解析点在驱动舱常量的同拍组
///   装 KeyboardFrameUpdate 经 onKeyboardFrame-
///   Change 喂 ChatView 的 kbFrameUpdate（与旧
///   面 ComposerGuideHost 同一口径、同一快照，
///   不许第二套）——isKeyboardUp／聚焦藏坞在
///   新面恢复触发（定因 K2 的修法）。

// MARK: - 行描述（ChatView 喂入）

/// 原生面行：身份键（diffable 条目身份，与 gen3
/// 行键同名同源）＋条目 id（锚/顶可见用，非条目
/// 行为 nil）＋内容版本（变→reconfigure 原位更
/// 新）＋产物层估算高（只供 .estimated 占位聚合，
/// 不是行高记账）＋视图构建闭包（只在（重）配置
/// cell 时调用）
struct ChatNativeRow {
    let key: String
    let entryID: UUID?
    let version: Int
    let estimatedHeight: CGFloat
    let makeView: () -> AnyView
    /// R3（§295）：落定散文原生规格——非 nil 时
    /// 本行走原生散文 cell（ChatNativeProseCell、
    /// 不经 SwiftUI 托管）；makeView 保留为同行
    /// 的托管形态（双形态对拍与回退口，cell 分
    /// 发以 proseSpec 在场为准）
    let proseSpec: ChatNativeProseSpec?

    init(
        key: String, entryID: UUID?, version: Int,
        estimatedHeight: CGFloat,
        proseSpec: ChatNativeProseSpec? = nil,
        makeView: @escaping () -> AnyView
    ) {
        self.key = key
        self.entryID = entryID
        self.version = version
        self.estimatedHeight = estimatedHeight
        self.proseSpec = proseSpec
        self.makeView = makeView
    }
}

// MARK: - 布局参数匣（compositional 布局提供者只认本匣、不认控制器本体）

private final class ChatNativeLayoutBox {
    var horizontalPadding: CGFloat = 20
    var topPadding: CGFloat = 16
    var bottomPadding: CGFloat = 8
    var rowSpacing: CGFloat = 24
    var estimatedPlaceholder: CGFloat = 120
}

// MARK: - 托管 cell

/// 托管 cell：UIHostingConfiguration 只渲染——
/// 内容以行键为 SwiftUI 身份（复用时状态不跨条
/// 目串行，施工图 §七风险 2）；拟合尺寸由集合视
/// 图布局自己消费，本类不读、不记（H10）
private final class ChatNativeHostingCell: UICollectionViewCell {
    static let reuseID = "ChatNativeHostingCell"

    func configure(with row: ChatNativeRow) {
        var config = UIHostingConfiguration {
            row.makeView()
                .id(row.key)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
        config = config.margins(.all, 0)
        contentConfiguration = config
        backgroundConfiguration = .clear()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
    }
}

// MARK: - 根容器

/// 原生面句柄（§291）：与 gen3 句柄（ChatList-
/// CarrierHandle）同形态——四读数＋四命令转发，
/// 控制器为本面具体类型。两面句柄同形不同型：
/// 抽协议存在类型曾试、CI 两轮实证与本仓 Swift 6
/// 隔离形态冲突（协议标 @MainActor 则非隔离句柄
/// 调用成错误、不标则两容器 witness 隔离不一致），
/// 故 ChatView 链以四个分发器按当前面派发、链本
/// 体仍只一份（见 ChatView surface* 分发器）
final class ChatNativeListHandle {
    var latestDistance: CGFloat = 0
    var contentEndVisible = false
    var containerHeight: CGFloat = 0
    var bottomInset: CGFloat = 0

    weak var controller: ChatRootViewController?

    func scrollToBottom(animated: Bool) {
        controller?.scrollToBottom(animated: animated)
    }

    func scrollToEntry(_ id: UUID, animated: Bool) {
        controller?.scrollToEntry(id, animated: animated)
    }

    func captureAnchor() -> ChatListAnchor? {
        controller?.captureAnchor()
    }

    func restore(_ anchor: ChatListAnchor) {
        controller?.restore(anchor)
    }
}

final class ChatRootViewController: UIViewController,
    UICollectionViewDelegate
{
    let collectionView: UICollectionView
    /// 与布局提供者闭包捕获的是同一个实例（init
    /// 里以本地实例回填本属性——提供者只认匣、不
    /// 认控制器本体，控制器初始化完成前不许自引）
    private let layoutBox: ChatNativeLayoutBox
    private var dataSource:
        UICollectionViewDiffableDataSource<Int, String>!

    var handle: ChatNativeListHandle?
    var callbacks: ChatListCarrierCallbacks?

    /// 与 gen3 容器同口：两宿主的滚动边缘注册经共
    /// 享句柄绑本面本体（§260）
    var edgeScrollHandle: ChatListScrollViewHandle? {
        didSet { edgeScrollHandle?.register(collectionView) }
    }

    private var layoutParams = ChatCarrierLayout(
        horizontalPadding: 20, topPadding: 16,
        bottomPadding: 8, rowSpacing: 24,
        arrowTrailing: 16, arrowSize: 44
    )
    private var rows: [ChatNativeRow] = []
    private var rowsByKey: [String: ChatNativeRow] = [:]
    private var versionsByKey: [String: Int] = [:]
    /// 非条目行的锚占位 id（与 gen3 同式：捕获命中
    /// 时顺延到下一条目行）
    private var frameIDByKey: [String: UUID] = [:]

    /// 喂入记账：顶 inset 喂入值／单点边距（§263
    /// 口径与 gen3 同源）。底侧自 R2 起无喂入——
    /// 舱在本容器内、留位全由其实测帧派生
    private var fedTopInset: CGFloat = 0
    private var bottomMargin: CGFloat = 0
    /// 实测留位（列表帧底−舱顶，两实测同在窗口系
    /// 相减）；nil＝尚未入窗量得（量得前底侧按 0
    /// 记账：首个布局拍即量得，先于任何可见帧）
    private var measuredBottomSpace: CGFloat?

    /// 输入舱子托管（R2 收编）：内容由 ChatView
    /// 以 AnyView 喂入（bottomBar 本体），底边钉
    /// 自有位置引导线 bottomGuide——其 top 常量
    /// 是舱落位的唯一数（§299 回 §194 形态：键
    /// 盘态＝通知帧顶、静息态＝坞实测顶，sync-
    /// BottomConstant 唯一计算点）。装配测试经
    /// internal 读口取其帧
    private(set) var composerHost:
        UIHostingController<AnyView>?
    /// §299：键盘帧更新回调（representable 桥接
    /// 回 ChatView 的 kbFrameUpdate 绑定）——与
    /// 舱常量同一通知解析点同拍组装（reportKey-
    /// boardFrame），帧顶已转窗口坐标、动画参数
    /// 原值；快照本体仍是 ChatView 的 kbSnapshot
    /// 一份，本容器不另持快照
    var onKeyboardFrameChange: ((KeyboardFrameUpdate) -> Void)?
    /// §299 位置引导线：top 由 bottomGuideTop-
    /// Constraint 的常量定位（布局空间换算，见
    /// syncBottomConstant）；舱底恒钉其 topAnchor、
    /// 约束永不切换激活态（§194「模式即病灶」）
    private let bottomGuide = UILayoutGuide()
    private var bottomGuideTopConstraint: NSLayoutConstraint!
    /// §299 坞锚当前参照（UITabBar 本体或类名兜
    /// 底命中；回落态为 nil 且 dockIsFallback＝
    /// true，参照＝窗口安全区底）——与 §194 同
    /// 式：只读其实帧、永不被约束直接引用
    private weak var dockBarView: UIView?
    private var dockIsFallback = false
    private weak var anchorWindow: UIWindow?
    /// §299.1 续作：回落态布局拍重解析的上次尝试
    /// 时刻——回落壳内恒无坞时每拍全窗遍历找坞会
    /// 扰动落定收敛时序，布局拍自愈加 0.3s 节流
    /// （窗口变化与离散触发点不经此闸，见
    /// viewDidLayoutSubviews／resolveAnchors）
    private var lastFallbackResolveAt: CFTimeInterval = 0
    private var keyboardUp = false
    /// §299 键盘顶存账（窗口坐标）：willShow/
    /// willChangeFrame 通知的结束帧顶——键盘本
    /// 人广播的真值，常量换算的唯一键盘输入；
    /// 收起即清
    private var keyboardTopInWindow: CGFloat?
    /// 视图未装载时到达的舱内容（装载拍补装）
    private var pendingComposerView: AnyView?
    /// 落定拍调度账（与 gen3 §259 同式：滚动回调
    /// 只记账、施工与读数产出统一在落定拍）
    private var settleScheduled = false
    /// 落点意图（H6）：冷开/命令贴底置真；收敛后
    /// 距底 ≤0.5 或用户拖动接管即消
    private var landingIntent = false
    /// 落点意图置真时刻（收敛重拍的时间窗预算起
    /// 点，见 performSettleBeat 的尾差处理）
    private var landingIntentSince: CFTimeInterval = 0
    private var userInteracting = false
    /// 布局未就绪时到达的恢复命令（先记账、落定
    /// 拍执行——与 gen3 restore 的等拍口径同义）
    private var pendingAnchor: ChatListAnchor?
    private var lastReportedTopVisible: UUID??

    private var arrowHost: UIHostingController<AnyView>?
    private var arrowVisible = false
    private var blankTapDelegate: ChatCarrierBlankTapDelegate?

    // MARK: 生命周期

    override init(
        nibName nibNameOrNil: String?,
        bundle nibBundleOrNil: Bundle?
    ) {
        let box = ChatNativeLayoutBox()
        layoutBox = box
        let layout = UICollectionViewCompositionalLayout {
            _, _ in
            ChatRootViewController.makeSection(box: box)
        }
        collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: layout
        )
        super.init(
            nibName: nibNameOrNil, bundle: nibBundleOrNil
        )
        setUpCollectionView()
    }

    required init?(coder: NSCoder) {
        let box = ChatNativeLayoutBox()
        layoutBox = box
        let layout = UICollectionViewCompositionalLayout {
            _, _ in
            ChatRootViewController.makeSection(box: box)
        }
        collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: layout
        )
        super.init(coder: coder)
        setUpCollectionView()
    }

    /// 集合视图装配（init 期即完成：representable
    /// 的 update 可能先于 viewDidLoad 到达，cell 注
    /// 册与数据源不许等装载拍）
    private func setUpCollectionView() {
        collectionView.delegate = self
        // 自适应行高失效口径（iOS 16+ UICollection-
        // View 属性、非 layout 属性）：cell 内约束
        // 变化即自动重测——托管内容（SwiftUI 拟合）
        // 的高变化靠本口收敛，不手算不回填（H9/H10）
        collectionView.selfSizingInvalidation =
            .enabledIncludingConstraints
        collectionView.register(
            ChatNativeHostingCell.self,
            forCellWithReuseIdentifier:
                ChatNativeHostingCell.reuseID
        )
        collectionView.register(
            ChatNativeProseCell.self,
            forCellWithReuseIdentifier:
                ChatNativeProseCell.reuseID
        )
        makeDataSource()
    }

    /// compositional 单列 section：item 宽全幅、
    /// 高 .estimated（产物层聚合占位）；间距只此
    /// 一处声明（interGroupSpacing＝spacingL，H1）；
    /// section 内边距与 gen3 帧表记账逐值同源（顶
    /// spacingM／左右 pageGutter／底 spacingS）
    private static func makeSection(
        box: ChatNativeLayoutBox
    ) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(
                box.estimatedPlaceholder
            )
        )
        let item = NSCollectionLayoutItem(
            layoutSize: itemSize
        )
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(
                box.estimatedPlaceholder
            )
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize, subitems: [item]
        )
        let section = NSCollectionLayoutSection(
            group: group
        )
        section.interGroupSpacing = box.rowSpacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: box.topPadding,
            leading: box.horizontalPadding,
            bottom: box.bottomPadding,
            trailing: box.horizontalPadding
        )
        return section
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 句柄回指（representable 的 make/update 已
        // 立、本处为脱离 representable 装配时的兜底）
        handle?.controller = self
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
        // 记账全手动（与 gen3 同口：inset 只认喂入
        // 记账＋实测派生，不许系统再叠安全区）
        collectionView.contentInsetAdjustmentBehavior =
            .never
        collectionView.keyboardDismissMode = .interactive
        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        // 边缘效果样式的 UIKit 直设（与 gen3 §260
        // 同义同值：样式挂滚动视图本体的 edge
        // effect、不自绘渐变——§173 红线）
        collectionView.topEdgeEffect.style = .soft
        collectionView.bottomEdgeEffect.style = .soft
        view.addSubview(collectionView)
        // §299：位置引导线入本视图（top 常量待
        // syncBottomConstant 按当前输入填，初始 0
        // ＝未解析前舱贴顶、无害瞬态，锚解析在入
        // 窗/显形拍即补）；舱装配（installComposer-
        // IfNeeded）把舱底钉其 topAnchor
        view.addLayoutGuide(bottomGuide)
        bottomGuideTopConstraint = bottomGuide.topAnchor
            .constraint(equalTo: view.topAnchor, constant: 0)
        NSLayoutConstraint.activate([
            bottomGuide.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            bottomGuide.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            bottomGuide.heightAnchor.constraint(
                equalToConstant: 0),
            bottomGuideTopConstraint,
        ])
        // §299 键盘信号（与 §194 同式）：willShow/
        // willHide 定状态翻转、willChangeFrame 供
        // 逐帧跟随，三者的结束帧都是位置常量的键
        // 盘输入；动画参数随通知取。selector 式观
        // 察者（不存 token，与 ComposerGuideHost-
        // Controller 同纪律：块式 token 在 Swift 6
        // 下 deinit/跨闭包发送有实证坑）
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        center.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        installComposerIfNeeded()
        installBlankTapDismiss()
        ChatDiagTrace.record(
            "原生重建 R1 新面装配（开关开）："
                + "UICollectionView＋diffable 就绪"
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // §299 锚解析触发点之一（入窗后窗口已定）：
        // 与 §194 的入窗/显形重解析同式——切格往返
        // 期间标签栏实例若被换过，在此换新参照
        resolveAnchors()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveAnchors()
    }

    // MARK: 键盘跟随（§299 回 §194 形态）

    @objc private func keyboardWillShow(
        _ note: Notification
    ) {
        setKeyboardUp(true, note: note)
    }

    @objc private func keyboardWillHide(
        _ note: Notification
    ) {
        setKeyboardUp(false, note: note)
    }

    /// §299 帧变化跟进（交互式下滑收键盘/候选条
    /// 高度变化）：键盘态内逐事件刷新存账帧顶并重
    /// 算常量——通知帧是键盘本人的广播，不经任何
    /// 引导线转译；时长 0 的逐帧事件直接布局、不
    /// 包动画（与 §194 willChangeFrame 同式）
    @objc private func keyboardWillChangeFrame(
        _ note: Notification
    ) {
        guard keyboardUp else { return }
        updateKeyboardTop(from: note)
        syncBottomConstant()
        animateLayout(with: note, immediateIfZero: true)
        reportKeyboardFrame(from: note)
    }

    /// §299 键盘帧顶存账：通知的结束帧是屏幕坐
    /// 标，经本窗换算成窗口坐标存下；常量换算在
    /// syncBottomConstant 里逐布局拍按本视图当前
    /// 布局空间重算，本函数只存窗口真值（与
    /// §194 updateKeyboardTop 同式）
    private func updateKeyboardTop(from note: Notification) {
        guard let value = note.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
        ] as? NSValue else { return }
        let screenFrame = value.cgRectValue
        if let window = view.window {
            keyboardTopInWindow = window.convert(
                screenFrame, from: nil
            ).minY
        } else {
            keyboardTopInWindow = screenFrame.minY
        }
    }

    /// §299 键盘态翻转：升起先把通知帧顶存账（常
    /// 量的唯一键盘输入），收起先重解析坞参照（聚
    /// 焦藏坞期间标签栏可能换实例）；常量重算后与
    /// 键盘动画同参推进布局（与 §194 setKeyboardUp
    /// 同式）。翻转拍采样引导线顶记入自述作对照
    /// ——引导线只采样、不驱动（预期其仍停静息
    /// 值、即定因 K1 本人）
    private func setKeyboardUp(
        _ up: Bool, note: Notification
    ) {
        if up {
            updateKeyboardTop(from: note)
        } else {
            resolveAnchors()
        }
        guard up != keyboardUp else {
            // 同态重播（willShow 重发等）：按已存帧
            // 顶重同步常量即可，不重入记账
            if up {
                syncBottomConstant()
                view.layoutIfNeeded()
                reportKeyboardFrame(from: note)
            }
            return
        }
        keyboardUp = up
        if !up { keyboardTopInWindow = nil }
        syncBottomConstant()
        animateLayout(with: note, immediateIfZero: false)
        reportKeyboardFrame(from: note)
        sampleGuideForTrace(event: up ? "kbShow" : "kbHide")
    }

    /// 与键盘动画同参推进一次布局（时长/曲线取自
    /// 通知）；immediateIfZero 时时长为 0 直接布
    /// 局——交互式逐帧跟随不许包进动画系统再迟
    /// 一拍（与 §194 animateLayout 同式）
    private func animateLayout(
        with note: Notification, immediateIfZero: Bool
    ) {
        let userInfo = note.userInfo
        let duration = userInfo?[
            UIResponder.keyboardAnimationDurationUserInfoKey
        ] as? Double ?? 0.25
        let curveRaw = userInfo?[
            UIResponder.keyboardAnimationCurveUserInfoKey
        ] as? UInt ?? 7
        if immediateIfZero, duration <= 0 {
            view.layoutIfNeeded()
            return
        }
        UIView.animate(
            withDuration: duration, delay: 0,
            options: UIView.AnimationOptions(
                rawValue: curveRaw << 16
            )
        ) { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }

    /// §299 锚解析：在本视图所在窗口的层级里找坞
    /// 参照（UITabBar 本体或类名兜底），只登记引
    /// 用与命中模式——位置由 syncBottomConstant
    /// 逐拍换算进位置常量，参照本身不被任何约束
    /// 引用。触发点只在离散事件（入窗/显形/键盘
    /// 收起）与回落态布局拍自愈——后者经
    /// viewDidLayoutSubviews 的 0.3s 节流闸（§299.1
    /// 续作）、窗口变化仍立即触发；不在每拍布局
    /// 里无条件走层级（与 §194 resolveAnchors 同式）
    private func resolveAnchors() {
        guard let window = view.window else { return }
        let windowChanged = anchorWindow !== window
        anchorWindow = window
        let foundBar = Self.findDockAnchor(in: window)
        if let foundBar {
            if dockBarView !== foundBar || dockIsFallback
                || windowChanged {
                dockBarView = foundBar
                dockIsFallback = false
            }
        } else if !dockIsFallback || windowChanged {
            // 无坞环境回落（探针裸装配等非生产形
            // 态）：参照＝窗口安全区底——生产装配
            // 恒有坞，不走此路
            dockBarView = nil
            dockIsFallback = true
        }
        syncBottomConstant()
    }

    /// §299 位置常量唯一计算点：bottomGuide 的
    /// top 常量＝目标顶边－本视图布局空间顶边。
    /// 目标顶边按当前输入取实测真值：键盘升起态
    /// ＝通知广播的键盘帧顶（窗口坐标——键盘升
    /// 起时抽屉必闭、祖先链 transform 恒等，窗口
    /// 坐标与布局空间累加坐标同值；无帧存账时保
    /// 留上次常量、不许跌回坞值）；静息态＝坞参
    /// 照的布局空间顶边（沿 superview 链累加
    /// frame 原点——布局真值、忽略 transform，
    /// 抽屉平移不假补偿、舱随前景同移）。逐布局
    /// 拍调用（只读缓存值、无层级遍历），偏差
    /// >0.5 才写（与 §194 syncBottomConstant 同式）
    private func syncBottomConstant() {
        guard let window = view.window,
              let bottomGuideTopConstraint else { return }
        let targetTop: CGFloat
        if keyboardUp {
            guard let kbTop = keyboardTopInWindow
            else { return }
            targetTop = kbTop
        } else if let bar = dockBarView,
                  bar.window === window {
            targetTop = Self.layoutSpaceMinY(of: bar)
        } else if dockIsFallback {
            targetTop = window.bounds.height
                - window.safeAreaInsets.bottom
        } else {
            return
        }
        let constant = targetTop
            - Self.layoutSpaceMinY(of: view)
        if abs(bottomGuideTopConstraint.constant - constant)
            > 0.5 {
            bottomGuideTopConstraint.constant = constant
        }
    }

    /// 视图在窗口布局空间的顶边（frame 原点沿父
    /// 链累加；transform 不进布局帧、天然不计，
    /// 与 §194 同名近似同式）
    private static func layoutSpaceMinY(
        of view: UIView
    ) -> CGFloat {
        var y = view.frame.minY
        var ancestor = view.superview
        while let current = ancestor,
              !(current is UIWindow) {
            y += current.frame.minY
            ancestor = current.superview
        }
        return y
    }

    /// 窗口层级内找坞锚目标（深度优先两级）：先
    /// UITabBar 本体；无本体时取类名含 TabBar 且
    /// 宽度 >300 的视图（系统内部实现跨版本改名/
    /// 换类的兜底，与 §194 findDockAnchor 同式）
    private static func findDockAnchor(
        in window: UIWindow
    ) -> UIView? {
        func walk(_ view: UIView) -> UIView? {
            if let bar = view as? UITabBar { return bar }
            for sub in view.subviews {
                if let hit = walk(sub) { return hit }
            }
            return nil
        }
        if let bar = walk(window) {
            return bar
        }
        func walkByName(_ view: UIView) -> UIView? {
            let name = String(describing: type(of: view))
            if name.contains("TabBar"),
               view.frame.width > 300 {
                return view
            }
            for sub in view.subviews {
                if let hit = walkByName(sub) { return hit }
            }
            return nil
        }
        return walkByName(window)
    }

    /// §299 键盘帧更新包的组装点——与 updateKey-
    /// boardTop 同一解析（window.convert 转窗口
    /// 坐标）、同一通知；停靠判定在窗口坐标系内
    /// 做（满宽＋底边贴窗口底＋帧顶在窗口内），
    /// 浮动/分离键盘按不在场报（top＝nil）；键盘
    /// 不在场（willHide 后）恒报 nil。动画参数取
    /// userInfo 原值。喂 ChatView 的 kbFrameUpdate
    /// ——与舱常量同源同拍（定因 K2 收口；与
    /// §194 reportKeyboardFrame 同式）
    private func reportKeyboardFrame(
        from note: Notification
    ) {
        let info = note.userInfo
        let duration = (info?[
            UIResponder.keyboardAnimationDurationUserInfoKey
        ] as? NSNumber)?.doubleValue ?? 0
        let curve = (info?[
            UIResponder.keyboardAnimationCurveUserInfoKey
        ] as? NSNumber)?.intValue ?? 0
        var top: CGFloat? = nil
        if keyboardUp,
           let window = view.window,
           let value = info?[
               UIResponder.keyboardFrameEndUserInfoKey
           ] as? NSValue {
            let rect = window.convert(
                value.cgRectValue, from: nil
            )
            let docked = rect.width
                    >= window.bounds.width - 1
                && rect.maxY
                    >= window.bounds.height - 1
                && rect.minY
                    < window.bounds.height - 1
            top = docked ? rect.minY : nil
        }
        onKeyboardFrameChange?(
            KeyboardFrameUpdate(
                topInWindow: top,
                duration: duration,
                curveRawValue: curve
            )
        )
    }

    /// §299 引导线采样对照（只记自述、永不驱动）：
    /// 翻转拍记通知帧顶与本视图 keyboardLayout-
    /// Guide 顶的窗口值同帧对账——真机验收看数
    /// 字：舱底应＝通知帧顶；guide 若仍停静息值
    /// 即 K1 根因本人的持续留证
    private func sampleGuideForTrace(event: String) {
        guard let window = view.window else { return }
        let guideTopInWindow = view.convert(
            CGPoint(
                x: 0,
                y: view.keyboardLayoutGuide.layoutFrame.minY
            ),
            to: window
        ).y
        let kbText = keyboardTopInWindow.map {
            String(format: "%.1f", $0)
        } ?? "nil"
        ChatDiagTrace.record(
            "原生面 §299 [\(event)] kbTopWin=\(kbText) "
                + "guideTopWin="
                + String(format: "%.1f", guideTopInWindow)
        )
    }

    // MARK: 输入舱收编（R2／§299）

    /// 舱内容喂入（representable update 入口）：已
    /// 装配则原位换内容（rootView 替换、约束不
    /// 动）；未装配则记账待装载拍补装。nil＝本面
    /// 无舱（装配测试的裸列表形态），不装配
    func applyComposer(view newView: AnyView?) {
        pendingComposerView = newView
        guard isViewLoaded else { return }
        if newView == nil {
            if let host = composerHost {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
                composerHost = nil
            }
            return
        }
        installComposerIfNeeded()
        if let newView {
            composerHost?.rootView = newView
        }
    }

    /// 舱子托管装配：UIHostingController 收编为子
    /// 控制器（H2：safeAreaRegions 清零）；约束只
    /// 三条——左右贴本视图、底边恒钉自有位置引
    /// 导线 bottomGuide.topAnchor，高由内容固有
    /// 尺寸（舱栈自带定高口径）。键盘的一切运动
    /// （升起/候选条/交互消散）经通知帧顶常量逐
    /// 拍传到本约束（§299，见键盘跟随节），舱随
    /// 之同拍移动——本面不许有第二条键盘通道
    private func installComposerIfNeeded() {
        guard composerHost == nil,
              let content = pendingComposerView
        else { return }
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints =
            false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            host.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            host.view.bottomAnchor.constraint(
                equalTo: bottomGuide.topAnchor
            ),
        ])
        composerHost = host
        // 回底钮浮层恒在舱之上（装配序兜底）
        if let arrowHost {
            view.bringSubviewToFront(arrowHost.view)
        }
    }

    private func makeDataSource() {
        dataSource =
            UICollectionViewDiffableDataSource<Int, String>(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, key in
                // R3（§295）：散文规格在场的行走原生
                // cell（文本本体直嵌、不经托管）；
                // 其余行维持托管 cell。行键的形态由
                // 内容资格决定、同键内恒定（落定映射
                // 在席的条目不下沉，见 ChatNative-
                // ProseCell 头注），reconfigure 不跨
                // 形态换 cell 类
                if let row = self?.rowsByKey[key],
                   let spec = row.proseSpec {
                    let cell = collectionView
                        .dequeueReusableCell(
                            withReuseIdentifier:
                                ChatNativeProseCell.reuseID,
                            for: indexPath
                        ) as! ChatNativeProseCell
                    cell.configure(with: spec)
                    return cell
                }
                let cell = collectionView
                    .dequeueReusableCell(
                        withReuseIdentifier:
                            ChatNativeHostingCell.reuseID,
                        for: indexPath
                    ) as! ChatNativeHostingCell
                if let row = self?.rowsByKey[key] {
                    cell.configure(with: row)
                }
                return cell
            }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // §299：本拍先做位置常量同步——窗口未解
        // 析（入窗前）或回落态（标签栏随呈现时序
        // 迟到）在此补解析、找到即退出回落；常量
        // 只读缓存的坞参照实帧/键盘存账帧顶（与
        // §194 布局拍纪律同式）。§299.1 续作：回
        // 落态重解析加节流——窗口变化立即走，否
        // 则距上次尝试 ≥0.3s 才走（回落壳内每拍
        // 全窗遍历扰动落定收敛，③⑯ 残差候选机制）；
        // 离散触发点（入窗/显形/键盘收起直调
        // resolveAnchors）不经此闸、行为不变
        if anchorWindow !== view.window {
            resolveAnchors()
        } else if dockIsFallback && !keyboardUp {
            let now = CACurrentMediaTime()
            if now - lastFallbackResolveAt >= 0.3 {
                lastFallbackResolveAt = now
                resolveAnchors()
            }
        }
        syncBottomConstant()
        // 布局前先记在底事实（旧帧口径）：布局变化
        // （旋转/壳层帧变）后在底者钉底、不在底者不
        // 动——与 gen3 layoutContent 的位置保全同式
        let wasAtBottom = collectionView.bounds.height > 0
            && currentDistance() <= 0.5
        collectionView.frame = view.bounds
        collectionView.layoutIfNeeded()
        measureBottomSpace()
        reconcileInsets()
        if (wasAtBottom || landingIntent)
            && !userInteracting {
            pinToBottom()
            if currentDistance() <= 0.5 {
                landingIntent = false
            }
        }
        layoutArrow()
    }

    // MARK: 参数应用（representable update 入口）

    func apply(
        rows newRows: [ChatNativeRow],
        layout: ChatCarrierLayout,
        topInset: CGFloat,
        bottomMargin newMargin: CGFloat,
        composerView: AnyView?,
        arrowView: AnyView?
    ) {
        // 布局参数同步进匣：间距/内边距/占位任一变
        // 即失效布局（compositional 声明式重算，不
        // 手算帧——H10）
        var paramsChanged = false
        if layoutBox.horizontalPadding
            != layout.horizontalPadding
            || layoutBox.topPadding != layout.topPadding
            || layoutBox.bottomPadding
                != layout.bottomPadding
            || layoutBox.rowSpacing != layout.rowSpacing {
            layoutBox.horizontalPadding =
                layout.horizontalPadding
            layoutBox.topPadding = layout.topPadding
            layoutBox.bottomPadding = layout.bottomPadding
            layoutBox.rowSpacing = layout.rowSpacing
            paramsChanged = true
        }
        layoutParams = layout
        // .estimated 占位只出产物层聚合（行估算的均
        // 值、钳制在合理带内）：它只服务未物化区的
        // 滚动几何，物化后系统自适应收敛——占位不
        // 是行高记账（H10）
        let placeholder = Self.placeholderEstimate(
            for: newRows
        )
        if abs(placeholder - layoutBox.estimatedPlaceholder)
            > 1 {
            layoutBox.estimatedPlaceholder = placeholder
            paramsChanged = true
        }
        if paramsChanged {
            collectionView.collectionViewLayout
                .invalidateLayout()
        }

        let newByKey = Dictionary(
            uniqueKeysWithValues: newRows.map {
                ($0.key, $0)
            }
        )
        let oldKeys = rows.map(\.key)
        let newKeys = newRows.map(\.key)
        let keysChanged = oldKeys != newKeys
        var reconfigureKeys: [String] = []
        if keysChanged {
            reconfigureKeys = newKeys.filter {
                versionsByKey[$0] != nil
                    && versionsByKey[$0]
                        != newByKey[$0]?.version
            }
        } else {
            reconfigureKeys = newKeys.filter {
                versionsByKey[$0] != newByKey[$0]?.version
            }
        }
        let wasEmpty = rows.isEmpty
        rows = newRows
        rowsByKey = newByKey
        if keysChanged {
            var snapshot =
                NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(newKeys, toSection: 0)
            if !reconfigureKeys.isEmpty {
                snapshot.reconfigureItems(reconfigureKeys)
            }
            dataSource.apply(
                snapshot, animatingDifferences: false
            )
            if wasEmpty && !newRows.isEmpty {
                // 冷开首装：落点意图置真，落定拍在真
                // 实布局后钉底（H6）；切线程的落位由
                // ChatView 恢复链经句柄命令驱动
                landingIntent = true
                landingIntentSince = CACurrentMediaTime()
            }
        } else if !reconfigureKeys.isEmpty {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(reconfigureKeys)
            dataSource.apply(
                snapshot, animatingDifferences: false
            )
        }
        versionsByKey = Dictionary(
            uniqueKeysWithValues: newRows.map {
                ($0.key, $0.version)
            }
        )

        let insetChanged = fedTopInset != topInset
            || bottomMargin != newMargin
        bottomMargin = newMargin
        if insetChanged {
            // apply 只记账，inset 施工归落定拍在布局
            // 落定后同拍执行。底侧恒由舱实测帧派生
            // （R2）：键盘动画不再经参数喂入——通知
            // 帧顶常量逐拍驱动舱帧、布局拍逐帧对账
            // inset，动画曲线即通知自带的那一条
            // （§299）
            fedTopInset = topInset
            measureBottomSpace()
            handle?.bottomInset = effectiveBottomInset
        }
        applyComposer(view: composerView)
        if keysChanged || !reconfigureKeys.isEmpty
            || insetChanged {
            scheduleSettle()
        }
        applyArrow(view: arrowView)
    }

    /// .estimated 占位聚合：行产物估算的均值（空集
    /// 回当前值不漂移），钳制 [56, 320] 防极端占位
    /// 把未物化区几何带偏；逐行真实高由系统物化
    /// 后收敛，与占位无关
    private static func placeholderEstimate(
        for rows: [ChatNativeRow]
    ) -> CGFloat {
        let estimates = rows
            .map(\.estimatedHeight)
            .filter { $0 > 0 }
        guard !estimates.isEmpty else { return 120 }
        let mean = estimates.reduce(0, +)
            / CGFloat(estimates.count)
        return min(320, max(56, mean))
    }

    // MARK: 落定拍（§259 合并调度，与 gen3 同式）

    private func scheduleSettle(delay: TimeInterval = 0) {
        guard !settleScheduled else { return }
        settleScheduled = true
        let work = { [weak self] in
            guard let self else { return }
            settleScheduled = false
            performSettleBeat()
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay, execute: work
            )
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// 落定拍本体：布局落定→量实测→inset 施工→落
    /// 位（恢复优先于落点意图）→读数产出。布局期
    /// 与滚动回调内一律不进（只记账排拍）
    private func performSettleBeat() {
        guard collectionView.bounds.width > 0
        else { return }
        collectionView.layoutIfNeeded()
        measureBottomSpace()
        reconcileInsets()
        if let anchor = pendingAnchor {
            pendingAnchor = nil
            executeRestore(anchor)
        } else if landingIntent && !userInteracting {
            pinToBottom()
            if currentDistance() <= 0.5 {
                landingIntent = false
            } else if CACurrentMediaTime()
                - landingIntentSince < 2.0 {
                // 收敛尾差（H6）：意图存续期内延迟
                // 重拍（与 gen3 §259 落定拍的
                // asyncAfter 同式）——真实迟到修正
                // （如图片落图改行高）落地后重钉、收
                // 敛即停；预算按时间窗不按次数。2 秒
                // 窗外仍未收敛则停拍、残差由现测读数
                // 如实呈报不假装在底：装配实证存在
                // ≤2pt 的布局 offset 调整残差（钉底
                // 触发的布局 pass 为保锚点位回调 off-
                // set，inset/contentSize/末行帧全自
                // 洽、末行完整可见，见装配测试④全状
                // 态打印与报告 §六定因）——那是布局
                // 的可达落点、非本拍能推翻的标尺分叉
                scheduleSettle(delay: 0.05)
            }
        }
        layoutArrow()
        report()
    }

    /// 实测对账（inset 唯一施工口，R2 收口）：每
    /// 拍把已应用 inset 拉回当拍实测恒等值——顶＝
    /// 喂入值＋短内容派生量、底＝舱实测留位＋单点
    /// 边距，施工值与量测一旦分叉即如实显形。R1
    /// 期另有「键盘动画参数驱动的施工」一路（con-
    /// structInsets），R2 起键盘运动经引导线逐帧
    /// 成本拍布局变化、对账逐帧跟进即同拍——动画
    /// 参数喂入与施工动画一并退役
    private func reconcileInsets() {
        let targetTop = fedTopInset + derivedTopInset()
        let targetBottom = effectiveBottomInset
        var inset = collectionView.contentInset
        var changed = false
        if abs(inset.top - targetTop) > 0.5 {
            inset.top = targetTop
            changed = true
        }
        if abs(inset.bottom - targetBottom) > 0.5 {
            inset.bottom = targetBottom
            changed = true
        }
        if changed {
            collectionView.contentInset = inset
            collectionView
                .verticalScrollIndicatorInsets = inset
            handle?.bottomInset = targetBottom
        }
    }

    /// 短内容派生顶 inset（H3）：内容高＜有效视口
    /// 高（帧高−顶 inset 喂入−底 inset）时差额整笔
    /// 作顶 inset——末行底在静止位恰落舱顶上 24
    /// （底 section 边距 spacingS＋单点边距
    /// spacingM）；只吃系统实测 contentSize，随内
    /// 容/落座每拍重算、一处记账。长内容恒 0
    private func derivedTopInset() -> CGFloat {
        let bounds = collectionView.bounds
        guard bounds.height > 0 else { return 0 }
        let effectiveViewport = bounds.height
            - fedTopInset - effectiveBottomInset
        return max(
            0, effectiveViewport
                - collectionView.contentSize.height
        )
    }

    // MARK: 几何读数（全部现测，H7）

    /// 实测留位量测（§263 同式、量测对象换代）：
    /// 帧底由本视图 convert 实帧、舱顶由舱子托管
    /// 的实帧 convert——两实测同在窗口系相减。R1
    /// 期舱在 ChatView 的 overlay 里、舱顶经绑定喂
    /// 入；R2 舱收编入本容器后量测不出容器、喂入
    /// 链退役（H8 的派生单源）
    private func measureBottomSpace() {
        guard let window = view.window,
              let host = composerHost
        else { return }
        let frameInWindow = view.convert(
            view.bounds, to: window
        )
        let hostInWindow = host.view.convert(
            host.view.bounds, to: window
        )
        measuredBottomSpace = max(
            0, frameInWindow.maxY - hostInWindow.minY
        )
    }

    private var effectiveBottomSpace: CGFloat {
        measuredBottomSpace ?? 0
    }

    private var effectiveBottomInset: CGFloat {
        effectiveBottomSpace + bottomMargin
    }

    /// 距底读数：以 effectiveBottomInset（实测派
    /// 生）为标尺（与 gen3 §263 同式，不读 adjusted
    /// 自证）；决策时刻现算（H7）
    private func currentDistance() -> CGFloat {
        CGFloat(
            ChatScrollSupply.uiKitDistance(
                contentHeight: Double(
                    collectionView.contentSize.height
                ),
                offsetY: Double(
                    collectionView.contentOffset.y
                ),
                viewportHeight: Double(
                    collectionView.bounds.height
                ),
                bottomInset: Double(effectiveBottomInset)
            )
        )
    }

    private func maxOffsetY() -> CGFloat {
        max(
            -collectionView.contentInset.top,
            collectionView.contentSize.height
                + effectiveBottomInset
                - collectionView.bounds.height
        )
    }

    private func pinToBottom() {
        collectionView.contentOffset = CGPoint(
            x: 0, y: maxOffsetY()
        )
    }

    private func report() {
        guard let handle,
              collectionView.bounds.height > 0
        else { return }
        handle.latestDistance = currentDistance()
        handle.containerHeight =
            collectionView.bounds.height
        handle.bottomInset = effectiveBottomInset
        // 末端事实：末 item 布局帧完整落在有效视口
        // 内（帧出布局属性实测、不经 contentSize 反
        // 推末行位置）
        if !rows.isEmpty,
           let attrs = collectionView
               .layoutAttributesForItem(
                   at: IndexPath(
                       item: rows.count - 1, section: 0
                   )
               ) {
            let visibleTop = collectionView
                .contentOffset.y
                + collectionView.contentInset.top
            let effectiveBottom = collectionView
                .contentOffset.y
                + collectionView.bounds.height
                - effectiveBottomInset
            handle.contentEndVisible =
                attrs.frame.minY >= visibleTop - 1
                && attrs.frame.maxY
                    <= effectiveBottom + 1
        } else {
            handle.contentEndVisible = false
        }
        // 顶可见条目：帧序首个与有效视口顶相交的
        // 条目行（非条目行跳过、继续向下找条目行）
        let visibleTop = collectionView.contentOffset.y
            + collectionView.contentInset.top
        var topEntry: UUID?
        for (index, row) in rows.enumerated() {
            guard let entryID = row.entryID,
                  let attrs = collectionView
                    .layoutAttributesForItem(
                        at: IndexPath(item: index, section: 0)
                    )
            else { continue }
            if attrs.frame.maxY > visibleTop {
                topEntry = entryID
                break
            }
        }
        if lastReportedTopVisible == nil
            || lastReportedTopVisible! != topEntry {
            lastReportedTopVisible = topEntry
            callbacks?.onTopVisibleEntry(topEntry)
        }
        callbacks?.onScrollGeometry()
    }

    // MARK: 滚动回调（只记账不施工，§259）

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        scheduleSettle()
    }

    func scrollViewWillBeginDragging(
        _ scrollView: UIScrollView
    ) {
        // 用户接管：落点意图即消（H6 的意图边界）
        userInteracting = true
        landingIntent = false
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate { userInteracting = false }
    }

    func scrollViewDidEndDecelerating(
        _ scrollView: UIScrollView
    ) {
        userInteracting = false
    }

    // MARK: 命令口（句柄转发目标，与 gen3 容器同名同义）

    func scrollToBottom(animated: Bool) {
        landingIntent = true
        landingIntentSince = CACurrentMediaTime()
        collectionView.layoutIfNeeded()
        let target = maxOffsetY()
        if animated {
            // 人发起的回底走 Core 回底弹簧参数（与
            // gen3 同参：ζ＝1.0、响应按距缩放），用
            // 户手势可接管
            let distance = currentDistance()
            UIView.animate(
                withDuration: TimeInterval(
                    BottomScrollSpring.response(
                        forDistance: distance
                    )
                ),
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState,
                          .allowUserInteraction]
            ) { [self] in
                collectionView.contentOffset = CGPoint(
                    x: 0, y: target
                )
            }
        } else {
            collectionView.contentOffset = CGPoint(
                x: 0, y: target
            )
        }
        scheduleSettle()
    }

    func scrollToEntry(_ id: UUID, animated: Bool) {
        guard let index = rows.firstIndex(
            where: { $0.entryID == id }
        ) else { return }
        collectionView.layoutIfNeeded()
        guard let attrs = collectionView
            .layoutAttributesForItem(
                at: IndexPath(item: index, section: 0)
            )
        else { return }
        let target = min(
            max(
                attrs.frame.minY
                    - collectionView.contentInset.top,
                -collectionView.contentInset.top
            ),
            maxOffsetY()
        )
        collectionView.setContentOffset(
            CGPoint(x: 0, y: target), animated: animated
        )
    }

    func captureAnchor() -> ChatListAnchor? {
        guard !rows.isEmpty else { return nil }
        if currentDistance() <= 0.5 {
            return .bottom
        }
        let visibleTop = collectionView.contentOffset.y
            + collectionView.contentInset.top
        for (index, row) in rows.enumerated() {
            guard let attrs = collectionView
                .layoutAttributesForItem(
                    at: IndexPath(item: index, section: 0)
                )
            else { continue }
            guard attrs.frame.maxY > visibleTop
            else { continue }
            if let entryID = row.entryID {
                return ChatListAnchor(
                    entryID: entryID,
                    intraEntryOffset: Double(
                        max(
                            0, visibleTop - attrs.frame.minY
                        )
                    ),
                    atBottom: false
                )
            }
            // 命中非条目行：顺延到其后第一个条目行
            // （与 gen3 同式）；其后无条目行则不存锚
            for next in index..<rows.count {
                if let entryID = rows[next].entryID {
                    return ChatListAnchor(
                        entryID: entryID,
                        intraEntryOffset: 0,
                        atBottom: false
                    )
                }
            }
            return nil
        }
        return nil
    }

    func restore(_ anchor: ChatListAnchor) {
        // 布局未就绪（零宽/无行）时先记账，落定拍
        // 在行集与布局落定后执行（与 ChatView 恢复
        // 链的等拍口径同义）
        guard collectionView.bounds.width > 0,
              !rows.isEmpty
        else {
            pendingAnchor = anchor
            scheduleSettle()
            return
        }
        executeRestore(anchor)
    }

    private func executeRestore(
        _ anchor: ChatListAnchor
    ) {
        collectionView.layoutIfNeeded()
        if anchor.atBottom {
            scrollToBottom(animated: false)
            return
        }
        if let offset = ChatListAnchor.restoredOffsetY(
            frames: pureFrames(),
            anchor: anchor,
            contentOriginY: Double(
                layoutParams.topPadding
            ),
            topInset: Double(
                collectionView.contentInset.top
            ),
            bottomInset: Double(effectiveBottomInset),
            contentHeight: Double(
                collectionView.contentSize.height
            ),
            viewportHeight: Double(
                collectionView.bounds.height
            )
        ) {
            collectionView.contentOffset = CGPoint(
                x: 0, y: CGFloat(offset)
            )
        }
        ChatDiagTrace.record(
            "原生重建 R1 锚恢复：条目 "
                + "\(anchor.entryID?.uuidString ?? "nil")"
                + " 条内偏移 "
                + "\(Int(anchor.intraEntryOffset))pt"
        )
    }

    /// 纯内容系帧表（首行顶边 y＝0，Core 锚模型口
    /// 径）：帧出布局属性（未物化 item 为布局估算
    /// 帧——锚恢复的近似源，恢复后距底由现测校验，
    /// H7）
    private func pureFrames() -> [ChatListAnchor.RowFrame] {
        rows.enumerated().map { index, row in
            let frame = collectionView
                .layoutAttributesForItem(
                    at: IndexPath(item: index, section: 0)
                )?.frame ?? .zero
            return ChatListAnchor.RowFrame(
                id: frameID(for: row),
                y: Double(
                    frame.minY - layoutParams.topPadding
                ),
                height: Double(frame.height)
            )
        }
    }

    private func frameID(
        for row: ChatNativeRow
    ) -> UUID {
        if let entryID = row.entryID { return entryID }
        if let existing = frameIDByKey[row.key] {
            return existing
        }
        let generated = UUID()
        frameIDByKey[row.key] = generated
        return generated
    }

    // MARK: 回底钮浮层（容器 overlay，与 gen3 同式）

    private func applyArrow(view newView: AnyView?) {
        if let newView {
            let host: UIHostingController<AnyView>
            if let existing = arrowHost {
                host = existing
                host.rootView = newView
            } else {
                host = UIHostingController(
                    rootView: newView
                )
                // H2：托管宿主 safeAreaRegions 清零
                host.safeAreaRegions = []
                host.view.backgroundColor = .clear
                arrowHost = host
                addChild(host)
                view.addSubview(host.view)
                host.didMove(toParent: self)
            }
            layoutArrow()
            if !arrowVisible {
                arrowVisible = true
                host.view.isHidden = false
                host.view.alpha = 0
                host.view.transform = CGAffineTransform(
                    scaleX: 0.9, y: 0.9
                )
                UIView.animate(withDuration: 0.2) {
                    host.view.alpha = 1
                    host.view.transform = .identity
                }
            }
        } else if let host = arrowHost, arrowVisible {
            arrowVisible = false
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    host.view.alpha = 0
                    host.view.transform =
                        CGAffineTransform(
                            scaleX: 0.9, y: 0.9
                        )
                },
                completion: { [weak self] _ in
                    if self?.arrowVisible == false {
                        host.view.isHidden = true
                    }
                }
            )
        }
    }

    /// 钮落位（与 gen3 §263 同源）：底缘＝帧底−实
    /// 测留位−gap；钮是 overlay 子视图，只改自身
    /// 帧、不触任何滚动记账
    private func layoutArrow() {
        guard let host = arrowHost else { return }
        measureBottomSpace()
        let size = layoutParams.arrowSize
        host.view.frame = CGRect(
            x: view.bounds.width
                - layoutParams.arrowTrailing - size,
            y: view.bounds.height
                - effectiveBottomSpace
                - layoutParams.arrowGapAboveComposer
                - size,
            width: size,
            height: size
        )
        view.bringSubviewToFront(host.view)
    }

    // MARK: 点空白收键盘（delegate 与 gen3 共用定版）

    private func installBlankTapDismiss() {
        let delegate = ChatCarrierBlankTapDelegate {
            [weak self] in
            self?.callbacks?.onBlankTap()
        }
        let tap = UITapGestureRecognizer(
            target: delegate,
            action: #selector(
                ChatCarrierBlankTapDelegate.handleTap
            )
        )
        tap.name = "OneDayBlankTapDismissNative"
        tap.cancelsTouchesInView = false
        tap.delegate = delegate
        collectionView.addGestureRecognizer(tap)
        blankTapDelegate = delegate
    }
}

// MARK: - Representable

struct ChatNativeListView: UIViewControllerRepresentable {
    var rows: [ChatNativeRow]
    var layout: ChatCarrierLayout
    var topInset: CGFloat
    var bottomMargin: CGFloat
    /// 输入舱内容（R2 收编）：由控制器子托管、底
    /// 边钉其位置引导线（§299 通知帧顶常量驱
    /// 动）；底几何的喂入自此只剩本内容本体，无
    /// 舱顶/动画参数喂入
    var composerView: AnyView
    /// §299：键盘帧更新收件槽（ChatView 的 kb-
    /// FrameUpdate 状态绑定）——控制器在键盘事
    /// 件拍直写（帧顶已转窗口坐标），与旧面
    /// ComposerGuideHost 的 keyboardFrame 绑定
    /// 同一口径、同一份快照
    var keyboardFrame: Binding<KeyboardFrameUpdate?>
    var arrowView: AnyView?
    var handle: ChatNativeListHandle
    var callbacks: ChatListCarrierCallbacks
    var edgeScrollHandle: ChatListScrollViewHandle

    func makeUIViewController(
        context: Context
    ) -> ChatRootViewController {
        let controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = callbacks
        controller.edgeScrollHandle = edgeScrollHandle
        handle.controller = controller
        wireKeyboardFeed(to: controller)
        return controller
    }

    func updateUIViewController(
        _ controller: ChatRootViewController,
        context: Context
    ) {
        controller.handle = handle
        controller.callbacks = callbacks
        controller.edgeScrollHandle = edgeScrollHandle
        handle.controller = controller
        wireKeyboardFeed(to: controller)
        controller.apply(
            rows: rows,
            layout: layout,
            topInset: topInset,
            bottomMargin: bottomMargin,
            composerView: composerView,
            arrowView: arrowView
        )
    }

    /// §299：把控制器的键盘帧回调接回 ChatView
    /// 的绑定——回调源自通知处理（非布局拍），
    /// 事件拍直写同步：快照与舱常量同拍翻转是
    /// 本收口的本意（与 ComposerGuideHost 桥的
    /// keyboardFrame 接线同一纪律）；等值守卫防
    /// 同值重播触发无谓重渲
    private func wireKeyboardFeed(
        to controller: ChatRootViewController
    ) {
        let keyboardFrame = keyboardFrame
        controller.onKeyboardFrameChange = { update in
            if keyboardFrame.wrappedValue != update {
                keyboardFrame.wrappedValue = update
            }
        }
    }
}
