import OneDayCore
import SwiftUI
import UIKit

/// 会话页原生重建 R1（DESIGN §291，施工图
/// chat-native-rebuild-blueprint-20261115 §五 R1）：
/// ChatRootViewController＋UICollectionView（正
/// 向、不倒置）＋UICollectionViewDiffableDataSource
/// ＋compositional 单列布局。落定行全集以
/// UIHostingConfiguration 托管现有 SwiftUI 行内容
/// 进 cell（内容本体一字不动）；直播区在 R1 不开
/// 流式行——ChatView 以旧面 liveZone 整段一块不透
/// 明 item 喂入（R2 收编为快照直播 item）。
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
///   Handle）与同一批喂入（舱顶实测/
///   回落种子/单点边距/键盘动画参数，§263 口径逐
///   值同源）；ChatView 跟随/锚链只认句柄、不为
///   本面再抄一份。键盘换代（keyboardLayoutGuide）
///   是 R2 的事，本面沿 §194 快照喂入不变。

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

    init(
        key: String, entryID: UUID?, version: Int,
        estimatedHeight: CGFloat,
        makeView: @escaping () -> AnyView
    ) {
        self.key = key
        self.entryID = entryID
        self.version = version
        self.estimatedHeight = estimatedHeight
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

    /// 喂入记账（与 gen3 逐值同源，§263）：顶 inset
    /// 喂入值／舱顶窗口实测／未量得回落／单点边距
    private var fedTopInset: CGFloat = 0
    private var composerTopInWindow: CGFloat = 0
    private var fallbackBottomSpace: CGFloat = 0
    private var bottomMargin: CGFloat = 0
    /// 实测留位（帧底−舱顶，两实测同在窗口系相
    /// 减）；nil＝尚未入窗量得（施工走回落种子）
    private var measuredBottomSpace: CGFloat?

    private struct PendingInset {
        let animationDuration: TimeInterval
        let animationCurveRaw: Int
    }

    private var pendingInset: PendingInset?
    /// 落定拍调度账（与 gen3 §259 同式：滚动回调
    /// 只记账、施工与读数产出统一在落定拍）
    private var settleScheduled = false
    /// 落点意图（H6）：冷开/命令贴底置真；收敛后
    /// 距底 ≤0.5 或用户拖动接管即消
    private var landingIntent = false
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
        installBlankTapDismiss()
        ChatDiagTrace.record(
            "原生重建 R1 新面装配（开关开）："
                + "UICollectionView＋diffable 就绪"
        )
    }

    private func makeDataSource() {
        dataSource =
            UICollectionViewDiffableDataSource<Int, String>(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, key in
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
        composerTopInWindow newComposerTop: CGFloat,
        fallbackBottomSpace newFallback: CGFloat,
        bottomMargin newMargin: CGFloat,
        keyboardAnimationDuration: TimeInterval,
        keyboardAnimationCurveRaw: Int,
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
            || composerTopInWindow != newComposerTop
            || fallbackBottomSpace != newFallback
            || bottomMargin != newMargin
        composerTopInWindow = newComposerTop
        fallbackBottomSpace = newFallback
        bottomMargin = newMargin
        if insetChanged {
            // 与 gen3 §259 同式：apply 只记账，inset
            // 施工归落定拍在布局落定后同拍执行
            fedTopInset = topInset
            measureBottomSpace()
            handle?.bottomInset = effectiveBottomInset
            pendingInset = PendingInset(
                animationDuration:
                    keyboardAnimationDuration,
                animationCurveRaw: keyboardAnimationCurveRaw
            )
        }
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

    private func scheduleSettle() {
        guard !settleScheduled else { return }
        settleScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            settleScheduled = false
            performSettleBeat()
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
        if let pending = pendingInset {
            pendingInset = nil
            constructInsets(pending)
        } else {
            reconcileInsets()
        }
        if let anchor = pendingAnchor {
            pendingAnchor = nil
            executeRestore(anchor)
        } else if landingIntent && !userInteracting {
            pinToBottom()
            if currentDistance() <= 0.5 {
                landingIntent = false
            }
        }
        layoutArrow()
        report()
    }

    /// inset 施工（键盘动画参数在场时与 gen3 同式
    /// 走系统曲线动画）：顶＝喂入值＋短内容派生顶
    /// inset（H3），底＝实测留位＋单点边距（§263）
    private func constructInsets(
        _ pending: PendingInset
    ) {
        let target = UIEdgeInsets(
            top: fedTopInset + derivedTopInset(),
            left: 0,
            bottom: effectiveBottomInset, right: 0
        )
        let construct = { [self] in
            collectionView.contentInset = target
            collectionView
                .verticalScrollIndicatorInsets = target
            handle?.bottomInset = effectiveBottomInset
        }
        if pending.animationDuration > 0,
           collectionView.window != nil {
            UIView.animate(
                withDuration: pending.animationDuration,
                delay: 0,
                options: UIView.AnimationOptions(
                    rawValue: UInt(
                        pending.animationCurveRaw
                    ) << 16
                ).union([.beginFromCurrentState]),
                animations: construct
            )
        } else {
            construct()
        }
    }

    /// 实测对账（与 gen3 同式）：未施工拍把已应用
    /// inset 拉回当拍实测恒等值——顶随派生量、底
    /// 随实测留位，施工值与量测一旦分叉即如实显形
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

    /// 实测留位量测（§263，与 gen3 逐字同式）：帧
    /// 底由本视图 convert 实帧、舱顶为 ChatView 喂
    /// 入的舱帧实测顶，两实测同在窗口系相减
    private func measureBottomSpace() {
        guard let window = view.window else { return }
        let frameInWindow = view.convert(
            view.bounds, to: window
        )
        measuredBottomSpace = max(
            0, frameInWindow.maxY - composerTopInWindow
        )
    }

    private var effectiveBottomSpace: CGFloat {
        measuredBottomSpace ?? fallbackBottomSpace
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
    /// 与 gen3 面同一批喂入（§263：舱顶窗口实测＋
    /// 未量得回落＋单点边距）
    var composerTopInWindow: CGFloat
    var fallbackBottomSpace: CGFloat
    var bottomMargin: CGFloat
    var keyboardAnimationDuration: TimeInterval
    var keyboardAnimationCurveRaw: Int
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
        controller.apply(
            rows: rows,
            layout: layout,
            topInset: topInset,
            composerTopInWindow: composerTopInWindow,
            fallbackBottomSpace: fallbackBottomSpace,
            bottomMargin: bottomMargin,
            keyboardAnimationDuration:
                keyboardAnimationDuration,
            keyboardAnimationCurveRaw:
                keyboardAnimationCurveRaw,
            arrowView: arrowView
        )
    }
}
