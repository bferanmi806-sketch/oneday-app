import OneDayCore
import SwiftUI
import UIKit

/// 会话页换代包 3·新承载（DESIGN §257，蓝图 §1.1/
/// §1.2/§2 包 3）：UIViewControllerRepresentable＋
/// UIScrollView 语义的容器承载——行高消费包 2 的排
/// 版产物（组合模型在 Core ChatRowHeightModel）、
/// 几何供数经 Core ChatScrollSupply 适配后喂回既有
/// 跟随判定（BottomArrowVisibility／BottomStick-
/// Coordinator／StreamFollowGate 零改）、锚点按蓝
/// 图 §1.2「条目 id＋条内偏移」存取。
///
/// 与旧承载的关系：特性开关（Core ChatCarrier-
/// Feature，默认关）开时 ChatView 以本承载替换
/// SwiftUI ScrollView＋LazyVStack；关时旧承载一字
/// 未动。两宿主（ComposerGuideHost／TopBarGuide-
/// Host）与 §194 键盘机制、冻结几何数值（62/729/
/// 122/145）在两承载下同源同值——本承载只换列表
/// 与回底钮的承载，不动输入舱托管。
///
/// 回底钮（本包头号用户面）：钮改由本容器以
/// overlay 子视图承载，锚输入舱顶上方约 8pt（落位
/// 由容器按实测留位在自身坐标系内构造——留位＝
/// 承载帧底与舱顶两实测相减，§263；§260 的窗口
/// 锚派生喂入＋帧外段扣减已退役，见 §263 注记）；
/// 钮的显隐只改 overlay 的
/// alpha/transform，**不进滚动内容、不改 content-
/// Inset、不改任何行帧**——出现/消失时末条消息纹
/// 丝不动（旧形态钮在布局流内占一行、出现即把整
/// 栈与末条顶上 52pt，见 interaction-feel-audit
/// 题一）。

/// §259 热修（0.50.45 首帧闪退，.ips 定案）：滚
/// 动回调只记账不施工——materialize 与几何读数
/// 产出统一由合并调度「落定拍」在帧表与行集同
/// 源同长时执行；apply 只记账、inset 施工归
/// layoutContent 帧表重建后同拍。详见 DESIGN
/// §259 与 gen3-reentrancy-fix 报告。

// MARK: - 行描述（ChatView 喂入）

/// 承载行：身份键＋条目 id（锚/顶可见用，非条目行
/// 为 nil）＋内容版本（变→重托管＋重量实）＋估算
/// 高（Core 组合模型产出或暂定值）＋视图构建闭包
/// （只在（重）托管时调用）
struct ChatCarrierRow {
    let key: String
    let entryID: UUID?
    let version: Int
    let estimatedHeight: CGFloat
    /// §247（包 4）：版本变化时保留本行既有量实
    /// 高（不回落估算）——只给「流式行→落定条
    /// 目行」的同键换代行用：落定帧先按流式期量
    /// 实连续呈现，托管重测后由量实回填自行纠偏
    /// （主线裁定口径：量实回填覆盖同 key 估
    /// 算）。缺省 false，其余行版本变即弃量实
    /// （包 3 既有口径不变）
    let keepsMeasuredHeightOnVersionChange: Bool
    let makeView: () -> AnyView

    init(
        key: String, entryID: UUID?, version: Int,
        estimatedHeight: CGFloat,
        keepsMeasuredHeightOnVersionChange: Bool = false,
        makeView: @escaping () -> AnyView
    ) {
        self.key = key
        self.entryID = entryID
        self.version = version
        self.estimatedHeight = estimatedHeight
        self.keepsMeasuredHeightOnVersionChange =
            keepsMeasuredHeightOnVersionChange
        self.makeView = makeView
    }
}

/// 承载布局参数（值源＝OneDayMetrics，ChatView 喂
/// 入，承载内不写第二套数）
struct ChatCarrierLayout {
    var horizontalPadding: CGFloat
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    var rowSpacing: CGFloat
    /// 回底钮右距（与旧钮行 .padding(.trailing) 同值）
    var arrowTrailing: CGFloat
    /// 回底钮底缘距输入舱顶（蓝图/简报口径约 8pt）
    var arrowGapAboveComposer: CGFloat = 8
    /// 回底钮命中边（与旧钮 OneDayMetrics.minTap-
    /// Target 同值）
    var arrowSize: CGFloat
}

/// 承载回调（ChatView 注入；几何回调只报「变了」，
/// 读数经句柄引用匣取——与 BottomDistanceRecorder
/// 的 §199 纪律同式：写不失效任何视图）
struct ChatListCarrierCallbacks {
    var onScrollGeometry: () -> Void
    var onTopVisibleEntry: (UUID?) -> Void
    var onBlankTap: () -> Void
}

// MARK: - 句柄（ChatView 的命令口与读数匣）

/// 列表面控制口（§291 原生重建 R1 抽出）：gen3 容
/// 器与原生容器（ChatRootViewController）共用同一
/// 句柄形态——ChatView 的跟随/锚恢复链只认本口，
/// 当前面由 ChatView 的 listHandle 派生决定，链本
/// 体不为每个承载再抄一份（§257 的执行双胞胎到
/// 本口收口）
protocol ChatListSurfaceControlling: AnyObject {
    func scrollToBottom(animated: Bool)
    func scrollToEntry(_ id: UUID, animated: Bool)
    func captureAnchor() -> ChatListAnchor?
    func restore(_ anchor: ChatListAnchor)
}

/// 与 ChatListScrollViewHandle／ComposerFocus-
/// Handle 同式的被动句柄：ChatView 持一份，命令
/// （贴底/锚恢复）经它下达、几何读数经它回读
final class ChatListCarrierHandle {
    /// 距底读数（Core ChatScrollSupply 新式，与旧
    /// 承载 bottomDistanceRecorder.latest 同义同源）
    var latestDistance: CGFloat = 0
    /// 内容末端是否完整落在有效视口内（事实信号，
    /// 与旧承载尾锚回调同义）
    var contentEndVisible = false
    /// 列表容器高（滚动视图帧高）
    var containerHeight: CGFloat = 0
    /// 底 inset 实值（本承载手动记账，与设定值恒等）
    var bottomInset: CGFloat = 0

    weak var controller: (any ChatListSurfaceControlling)?

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

// MARK: - 扩展锚存取（条目 id＋条内偏移）

/// 扩展锚的落盘口：旧 SideChatScrollAnchor 只有
/// （entryID, atBottom）两字段、装不下条内偏移——
/// 新承载的锚单独存本口（UserDefaults 编码字典，
/// 键＝线程 id），旧锚保留为回落（扩展锚缺位时按
/// 旧锚恢复）。切线程存取纪律与旧口一致（离线程
/// 时存、入线程时取）
enum ChatListAnchorStore {
    private static let defaultsKey = "chat.carrier.anchors.v1"

    private struct StoredAnchor: Codable {
        var entryID: String?
        var intraEntryOffset: Double
        var atBottom: Bool
    }

    static func anchor(for threadID: UUID) -> ChatListAnchor? {
        guard let dict = UserDefaults.standard.dictionary(
            forKey: defaultsKey
        ) as? [String: Data],
            let data = dict[threadID.uuidString],
            let stored = try? JSONDecoder().decode(
                StoredAnchor.self, from: data
            )
        else { return nil }
        return ChatListAnchor(
            entryID: stored.entryID.flatMap(UUID.init(uuidString:)),
            intraEntryOffset: stored.intraEntryOffset,
            atBottom: stored.atBottom
        )
    }

    static func setAnchor(
        _ anchor: ChatListAnchor, for threadID: UUID
    ) {
        let stored = StoredAnchor(
            entryID: anchor.entryID?.uuidString,
            intraEntryOffset: anchor.intraEntryOffset,
            atBottom: anchor.atBottom
        )
        guard let data = try? JSONEncoder().encode(stored)
        else { return }
        var dict = (UserDefaults.standard.dictionary(
            forKey: defaultsKey
        ) as? [String: Data]) ?? [:]
        dict[threadID.uuidString] = data
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }
}

// MARK: - 容器视图控制器

final class ChatListCarrierViewController: UIViewController,
    UIScrollViewDelegate, ChatListSurfaceControlling
{
    let scrollView = UIScrollView()
    private let contentView = UIView()

    var handle: ChatListCarrierHandle?
    var callbacks: ChatListCarrierCallbacks?

    /// §260：与两宿主（顶簇 TopBarGuideHost／舱带
    /// ComposerGuideHost）共享的列表本体句柄——本
    /// 承载的 UIScrollView 本体经它登记，两宿主的
    /// UIScrollEdgeElementContainerInteraction 才
    /// 绑得到。旧承载由内容栈里的登记锚 ChatList-
    /// ScrollAnchor 沿祖先链喂入；新承载面里没有
    /// 锚，本控制器改在句柄赋值拍直接登记（scroll-
    /// View 自初始化起恒存、登记与视图加载无关；
    /// 句柄弱引用、本体随控制器释放自动失效，与
    /// 锚的被动登记匣同式）
    var edgeScrollHandle: ChatListScrollViewHandle? {
        didSet { edgeScrollHandle?.register(scrollView) }
    }

    private var layoutParams = ChatCarrierLayout(
        horizontalPadding: 20, topPadding: 16,
        bottomPadding: 8, rowSpacing: 24,
        arrowTrailing: 16, arrowSize: 44
    )
    private var rows: [ChatCarrierRow] = []
    /// 行帧（滚动内容坐标，含顶 padding 起算）
    private var rowFrames: [CGRect] = []
    /// 非条目行的帧表占位 id（锚捕获用，捕获命中时
    /// 由 captureAnchor 向后顺延到下一条目行）
    private var frameIDs: [UUID] = []
    private var frameIDByKey: [String: UUID] = [:]
    /// 量实高（键＝行 key；版本变即弃）
    private var measuredHeights: [String: (version: Int, height: CGFloat)] = [:]
    private var hosted: [String: UIHostingController<AnyView>] = [:]
    private var hostedVersions: [String: Int] = [:]
    private var lastTopVisibleEntryID: UUID?
    private var lastReportedTopVisible: UUID??
    /// apply 记账的待应用 inset（§259：apply 只记
    /// 账，layoutContent 在帧表重建后同拍施工）。
    /// §263：只记顶 inset 与键盘动画参数——底 inset
    /// 不再有「待应用值」，施工拍以当拍实测留位现
    /// 算（量在哪、帧在哪，不吃喂入存量）
    private struct PendingInset {
        let topInset: CGFloat
        let animationDuration: TimeInterval
        let animationCurveRaw: Int
    }

    private var pendingInset: PendingInset?
    /// 落定拍调度账（§259）：排定标记／是否需先重
    /// 建帧表／materialize 重入门与合并待办标记
    private var settleScheduled = false
    private var settleNeedsRelayout = false
    private var isMaterializing = false
    private var materializePending = false
    private var appliedTopInset: CGFloat = -1
    /// 舱顶窗口系实测（§263）：ChatView 喂入的舱帧
    /// 窗口实测顶（ComposerGuideHost 的 barFrame-
    /// InWindow.minY——舱顶本人、每布局拍更新）。
    /// §260 的快照派生 bottomSpace 喂入自此退役：
    /// 派生公式「(窗口高−锚顶)＋栈高」混窗口系记账
    /// 与 §194 布局空间钉位、舱实际落座与锚模型恒
    /// 差一份壳层链偏差（诊断 gen3-gap-recheck 定
    /// 案），锚/栈高两个中间量退出公式
    private var composerTopInWindow: CGFloat = 0
    /// 单点边距（§263）：实测留位之外、与布局底
    /// padding 合计 24pt 目标总量的喂入侧份额
    /// （ChatView 喂 spacingM；§260 校准值不变）
    private var bottomMargin: CGFloat = 0
    /// 未量得回落（§263）：入窗量得实测留位前（未
    /// 入窗/首拍前）的瞬态种子——ChatView 喂入的
    /// 快照派生值，仅供此态施工，首个入窗布局拍即
    /// 被实测覆写、永不参与已量得帧的记账
    private var fallbackBottomSpace: CGFloat = 0
    /// 实测留位（§263）：承载帧底−舱顶，两实测同
    /// 在窗口系相减、量在承载自己的坐标系里——所
    /// 需量本体。nil＝尚未入窗量得（施工走回落）
    private var measuredBottomSpace: CGFloat?

    private var arrowHost: UIHostingController<AnyView>?
    private var arrowVisible = false

    // MARK: 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        // 记账全手动（inset 只认 ChatView 喂入的记
        // 账值，不许系统再叠安全区——冻结几何单源）
        scrollView.contentInsetAdjustmentBehavior = .never
        // 与旧承载 .scrollDismissesKeyboard(.inter-
        // actively) 同义
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        // §260：边缘效果样式的 UIKit 直设——与旧承
        // 载 ChatView 的 .scrollEdgeEffectStyle
        // (.soft, for: .top/.bottom) 同义同值。样式
        // 挂滚动视图本体的 edge effect（WWDC25
        // Session 284 官方式：scrollView.topEdge-
        // Effect.style）；SwiftUI 修饰符够不到 rep-
        // resentable 内的 UIKit 本体，§257 换承载时
        // 此式与句柄登记一并漏接、上下朦胧感全失
        // （0.50.46 真机反馈）。两宿主的注册容器只
        // 塑造效果在覆盖容器后的呈现、不带样式
        // （§213 纪律不变）；不自绘渐变（§173 红线）
        scrollView.topEdgeEffect.style = .soft
        scrollView.bottomEdgeEffect.style = .soft
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        installBlankTapDismiss()
        ChatDiagTrace.record(
            "换代包3 新承载装配（开关开）：UIScrollView 容器就绪"
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let oldWidth = scrollView.frame.width
        scrollView.frame = view.bounds
        if scrollView.frame.width != oldWidth {
            // 宽度变＝产物键失效＋量实全弃（宽是高
            // 的因子），按新宽重排
            measuredHeights.removeAll()
        }
        layoutContent(preservePosition: true)
        layoutArrow()
    }

    // MARK: 参数应用（representable update 入口）

    func apply(
        rows newRows: [ChatCarrierRow],
        layout: ChatCarrierLayout,
        topInset: CGFloat,
        composerTopInWindow newComposerTop: CGFloat,
        fallbackBottomSpace newFallback: CGFloat,
        bottomMargin newMargin: CGFloat,
        keyboardAnimationDuration: TimeInterval,
        keyboardAnimationCurveRaw: Int,
        arrowView: AnyView?
    ) {
        layoutParams = layout
        let rowsChanged = !rowsEqual(rows, newRows)
        if rowsChanged {
            rows = newRows
            // 版本变的行弃旧量实；§247（包 4）唯一
            // 例外：带留高旗的行（流式行落定换代）
            // 把量实移交到新版本——落定帧行高与流
            // 式期量实连续，托管重测后量实回填再纠
            // 偏；移交后记录版本即新版本，后续变化
            // 非再次带旗则按常规弃用
            let newRowsByKey = Dictionary(
                uniqueKeysWithValues: newRows.map { ($0.key, $0) }
            )
            var kept: [String: (version: Int, height: CGFloat)] =
                [:]
            for (key, record) in measuredHeights {
                guard let row = newRowsByKey[key] else { continue }
                if record.version == row.version {
                    kept[key] = record
                } else if row.keepsMeasuredHeightOnVersionChange {
                    kept[key] = (row.version, record.height)
                }
            }
            measuredHeights = kept
        }
        let insetChanged = appliedTopInset != topInset
            || composerTopInWindow != newComposerTop
            || fallbackBottomSpace != newFallback
            || bottomMargin != newMargin
        composerTopInWindow = newComposerTop
        fallbackBottomSpace = newFallback
        bottomMargin = newMargin
        if insetChanged {
            // §259：apply 只记账——inset 的实际应用
            // （含键盘动画与贴底校正）归 layoutContent
            // 在帧表重建后同拍施工。此处同步应用会在
            // 帧表未建时 set offset、经 didScroll 同步
            // 重入 materialize 撞未建帧表（0.50.45 首
            // 帧闪退同根③）
            appliedTopInset = topInset
            // §263：回报口径＝当拍实测口径的施工值
            // （先以新喂入的舱顶刷一次量测、施工拍再
            // 对齐一次）
            measureBottomSpace()
            handle?.bottomInset = effectiveBottomInset
            pendingInset = PendingInset(
                topInset: topInset,
                animationDuration: keyboardAnimationDuration,
                animationCurveRaw: keyboardAnimationCurveRaw
            )
        }
        if rowsChanged || insetChanged {
            layoutContent(preservePosition: true)
        }
        applyArrow(view: arrowView)
        // 读数产出移入落定拍（§259）：apply 尾不再同
        // 步报几何，排一拍由 settle 统一产出
        scheduleSettle()
    }

    private func rowsEqual(
        _ a: [ChatCarrierRow], _ b: [ChatCarrierRow]
    ) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            if lhs.key != rhs.key || lhs.version != rhs.version
                || lhs.entryID != rhs.entryID
                || abs(lhs.estimatedHeight - rhs.estimatedHeight) > 0.5 {
                return false
            }
        }
        return true
    }

    // MARK: 布局与托管

    private func resolvedHeight(for row: ChatCarrierRow) -> CGFloat {
        if let measured = measuredHeights[row.key],
           measured.version == row.version {
            return measured.height
        }
        return row.estimatedHeight
    }

    private func layoutContent(preservePosition: Bool) {
        layoutContent(
            preservePosition: preservePosition, inSettleBeat: false
        )
    }

    /// 帧表重建＋inset 施工＋位置校正（§259）：本
    /// 函数只做数据帧表与 inset/offset 施工，绝不
    /// 同步 materialize——托管与读数产出统一排到
    /// 落定拍；仅当本函数自身由落定拍调用时
    /// （inSettleBeat）才在尾部同拍落定
    private func layoutContent(
        preservePosition: Bool, inSettleBeat: Bool
    ) {
        guard scrollView.bounds.width > 0 else { return }
        // §263：本拍先量实测留位——下方施工与位置
        // 校正全以本拍两实测相减为准（入窗首拍即由
        // 回落种子翻实测、对账段随之拉回已应用
        // inset）
        measureBottomSpace()
        // 重排前先记位置（在底钉底/不在底锚恢复）：
        // 行高修正（产物落盘/量实到达）只许动锚上
        // 方的账，不许动在屏内容——通行做法（估算
        // 高精修时按锚补偿 offset）同式
        let wasAtBottom = preservePosition
            && currentDistance() <= 0.5
        let anchor = preservePosition && !wasAtBottom
            ? captureAnchor() : nil

        rebuildFrames()

        // inset 施工＋位置校正：帧表落定后同拍执行
        // （原 apply 同步块迁入，§259 同根③）；本段
        // 内的 offset 写入只会触发记账型 didScroll、
        // 不再重入施工
        let constructedThisPass = pendingInset != nil
        let construct = { [self] in
            if let pending = pendingInset {
                pendingInset = nil
                // §263：施工底 inset＝当拍实测留位＋单
                // 点边距（顶 inset 不掺量测：帧顶与窗
                // 口顶同位、喂入即真值）；指示器 inset
                // 与回报同值
                let applied = UIEdgeInsets(
                    top: pending.topInset, left: 0,
                    bottom: effectiveBottomInset, right: 0
                )
                scrollView.contentInset = applied
                scrollView.verticalScrollIndicatorInsets =
                    applied
                handle?.bottomInset = effectiveBottomInset
                layoutArrow()
            }
            if preservePosition {
                if wasAtBottom {
                    scrollView.contentOffset = CGPoint(
                        x: 0, y: maxBottomOffsetY()
                    )
                } else if let anchor,
                          let offset = ChatListAnchor.restoredOffsetY(
                              frames: pureFrames(),
                              anchor: anchor,
                              contentOriginY: Double(
                                  layoutParams.topPadding
                              ),
                              topInset: Double(appliedTopInset),
                              bottomInset: Double(
                                  effectiveBottomInset
                              ),
                              contentHeight: Double(
                                  scrollView.contentSize.height
                              ),
                              viewportHeight: Double(
                                  scrollView.bounds.height
                              )
                          ) {
                    scrollView.contentOffset = CGPoint(
                        x: 0, y: CGFloat(offset)
                    )
                }
            }
        }
        if let pending = pendingInset,
           pending.animationDuration > 0,
           scrollView.window != nil {
            UIView.animate(
                withDuration: pending.animationDuration,
                delay: 0,
                options: UIView.AnimationOptions(
                    rawValue: UInt(pending.animationCurveRaw)
                        << 16
                ).union([.beginFromCurrentState]),
                animations: construct
            )
        } else {
            construct()
        }

        // §263 实测对账：inset 施工时未入窗（走回落
        // 种子）、入窗量得实测后，或舱落座变化未经
        // apply 到达本拍时，把已应用的底 inset 拉回
        // 当拍实测恒等值。键盘动画中 contentInset
        // 的模型值恒为目标值、对账恒等不打断动画；
        // 位置校正已在 construct 内以施工口径执行、
        // 此处只动 inset 本体
        if !constructedThisPass {
            let eff = effectiveBottomInset
            if abs(scrollView.contentInset.bottom - eff)
                > 0.5 {
                var inset = scrollView.contentInset
                inset.bottom = eff
                scrollView.contentInset = inset
                var indicator =
                    scrollView.verticalScrollIndicatorInsets
                indicator.bottom = eff
                scrollView.verticalScrollIndicatorInsets =
                    indicator
                handle?.bottomInset = eff
            }
        }

        if inSettleBeat {
            performSettleBeat()
        } else {
            scheduleSettle()
        }
    }

    /// 帧表重建（纯数据施工）：按当前 rows 与记账
    /// 高（量实优先、否则估算）算帧表与内容高；不
    /// 触 offset、不托管——rows 与 rowFrames 自此
    /// 同源同长，是 materialize 的入口前提（§259）
    private func rebuildFrames() {
        let rowWidth = scrollView.bounds.width
            - layoutParams.horizontalPadding * 2
        let heights = rows.map { resolvedHeight(for: $0) }
        var naturalHeight = layoutParams.topPadding
            + layoutParams.bottomPadding
        for (index, height) in heights.enumerated() {
            naturalHeight += height
            if index < heights.count - 1 {
                naturalHeight += layoutParams.rowSpacing
            }
        }
        let fill = bottomAnchorFill(
            naturalHeight: naturalHeight
        )
        var frames: [CGRect] = []
        var ids: [UUID] = []
        var y = layoutParams.topPadding + fill
        for (index, row) in rows.enumerated() {
            frames.append(
                CGRect(
                    x: layoutParams.horizontalPadding,
                    y: y, width: rowWidth,
                    height: heights[index]
                )
            )
            ids.append(frameID(for: row))
            y += heights[index]
            if index < rows.count - 1 {
                y += layoutParams.rowSpacing
            }
        }
        rowFrames = frames
        frameIDs = ids
        let contentHeight = naturalHeight + fill
        contentView.frame = CGRect(
            x: 0, y: 0,
            width: scrollView.bounds.width,
            height: contentHeight
        )
        scrollView.contentSize = contentView.frame.size
    }

    /// 底锚定填充（§274）：内容自然高不足有效视口
    /// 高（V−顶 inset−底 inset）时，差额整笔垫在首
    /// 行之上——内容高下限＝有效视口高，最大底偏
    /// 移的 −顶 inset 钳制点恰与「末行底→舱顶＝
    /// 底 padding＋边距」落点重合，短内容自此物理
    /// 可达底（平台同构：SwiftUI defaultScroll-
    /// Anchor 的 .alignment 底对齐／Android stack-
    /// FromEnd 均为「内容不足时贴底」的官方机制，
    /// 本承载是 UIScrollView 手工承载、以内容最小
    /// 高等价实现）。填充量只吃实测：V 取本视图帧
    /// 高、顶 inset 取记账实值、底 inset 须已入窗
    /// 量得实测留位才许参与（measuredBottomSpace
    /// 在场为门）——未量得的瞬态不填充：拿回落种
    /// 子算填充＝拿派生值施工，§263 已退役此路。
    /// 长内容填充恒 0，§270（二修）留位公式与落
    /// 点逐值不变；填充随行高/落座每拍重算（流式
    /// 增长时填充等量收、末行底落点不动）
    private func bottomAnchorFill(
        naturalHeight: CGFloat
    ) -> CGFloat {
        guard measuredBottomSpace != nil else { return 0 }
        let viewportHeight = scrollView.bounds.height
        guard viewportHeight > 0 else { return 0 }
        let minContentHeight = viewportHeight
            - appliedTopInset - effectiveBottomInset
        return max(0, minContentHeight - naturalHeight)
    }

    /// 同拍一致性对齐：帧表与行集不同长时先纯数据
    /// 重建对齐再消费——不是下标守卫，是 materialize
    /// 入口前提（同源同长）的同拍恢复，消费方（落
    /// 定拍/命令口/读数产出）统一经此
    private func ensureFramesCoherent() {
        guard rowFrames.count != rows.count,
              scrollView.bounds.width > 0
        else { return }
        rebuildFrames()
    }

    /// 纯内容系帧表（首行顶边 y＝0，Core 锚模型口径）
    private func pureFrames() -> [ChatListAnchor.RowFrame] {
        zip(frameIDs, rowFrames).map { id, frame in
            ChatListAnchor.RowFrame(
                id: id,
                y: Double(frame.minY - layoutParams.topPadding),
                height: Double(frame.height)
            )
        }
    }

    private func frameID(for row: ChatCarrierRow) -> UUID {
        if let entryID = row.entryID { return entryID }
        if let existing = frameIDByKey[row.key] {
            return existing
        }
        let generated = UUID()
        frameIDByKey[row.key] = generated
        return generated
    }

    /// 托管窗口：可见区上下各扩一屏（与包 2 预热
    /// 「可见区±一屏」同口径）；窗口外行卸托管、
    /// 只留帧与量实高。
    /// §259：本函数只许由落定拍（performSettleBeat）
    /// 调用，入口两道门——重入门（重入即合并待办、
    /// 立即返回）与同源门（rows 与 rowFrames 不同
    /// 长即本拍不施工）；函数内下标不另设守卫，前
    /// 提由调度单源＋两道门保证（0.50.45 首帧闪退
    /// 的陷阱正是旧形态在布局期经 didScroll 同步进
    /// 入本函数、撞 rows 已换新而 rowFrames 未建）
    private func materializeNow() {
        guard !isMaterializing else {
            materializePending = true
            ChatDiagTrace.record(
                "§259 materialize 重入被合并待办（双保险命中）"
            )
            return
        }
        guard rowFrames.count == rows.count else { return }
        let bounds = scrollView.bounds
        guard bounds.height > 0 else { return }
        isMaterializing = true
        defer {
            isMaterializing = false
            if materializePending {
                materializePending = false
                scheduleSettle()
            }
        }
        let offsetY = scrollView.contentOffset.y
        let windowMin = offsetY - bounds.height
        let windowMax = offsetY + bounds.height * 2
        var needed: Set<String> = []
        for (index, row) in rows.enumerated() {
            let frame = rowFrames[index]
            guard frame.maxY >= windowMin,
                  frame.minY <= windowMax
            else { continue }
            needed.insert(row.key)
            let host: UIHostingController<AnyView>
            if let existing = hosted[row.key] {
                host = existing
                if hostedVersions[row.key] != row.version {
                    host.rootView = row.makeView()
                    hostedVersions[row.key] = row.version
                }
            } else {
                host = UIHostingController(
                    rootView: row.makeView()
                )
                host.view.backgroundColor = .clear
                hosted[row.key] = host
                hostedVersions[row.key] = row.version
                addChild(host)
                contentView.addSubview(host.view)
                host.didMove(toParent: self)
            }
            host.view.frame = frame
            // 量实：托管后以真实拟合高回填（结构段
            // 与未覆盖行型的承载侧定高在此收口；
            // 与当前记账高差 >0.5 才记，避免抖动环）
            let measured = host.sizeThatFits(
                in: CGSize(
                    width: frame.width,
                    height: .greatestFiniteMagnitude
                )
            ).height
            if measured > 0,
               abs(measured - frame.height) > 0.5,
               measuredHeights[row.key]?.height != measured {
                measuredHeights[row.key] = (
                    version: row.version, height: measured
                )
                scheduleRelayout()
            }
        }
        let staleKeys = hosted.keys.filter {
            !needed.contains($0)
        }
        for key in staleKeys {
            guard let host = hosted[key] else { continue }
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            hosted.removeValue(forKey: key)
            hostedVersions.removeValue(forKey: key)
        }
    }

    // MARK: 落定拍（§259 合并调度）

    /// 落定拍排定：materialize 与几何读数产出的唯
    /// 一调度口（原 scheduleRelayout 的合并调度件
    /// 升格）——已排定则只合并待办、不重复入队，
    /// 与 UICollectionView 失效合并同构。排定来源：
    /// didScroll 记账、apply、layoutContent、量实
    /// 回填（经 scheduleRelayout 标记重建）
    private func scheduleSettle() {
        guard !settleScheduled else { return }
        settleScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            settleScheduled = false
            if settleNeedsRelayout {
                settleNeedsRelayout = false
                layoutContent(
                    preservePosition: true, inSettleBeat: true
                )
            } else {
                performSettleBeat()
            }
        }
    }

    /// 落定拍本体：帧表先同拍对齐（materialize 的
    /// 入口前提），再托管、再产读数——三者只许在
    /// 此执行；布局期与一切滚动回调内一律不进
    private func performSettleBeat() {
        ensureFramesCoherent()
        materializeNow()
        reportScrollGeometry()
    }

    /// 量实回填的重排请求：标记落定拍需先重建帧
    /// 表，再走统一调度口（不另立调度器）
    private func scheduleRelayout() {
        settleNeedsRelayout = true
        scheduleSettle()
    }

    // MARK: 几何读数与回调

    /// 实测留位量测（§263）：所需量＝舱顶→承载帧
    /// 底，两端同取窗口系实测相减——帧底由本视图
    /// convert 实帧、舱顶为 ChatView 喂入的舱帧实
    /// 测顶（barFrameInWindow 每拍更新）。无窗口时
    /// 保留上次实测（不虚报新值）；壳层帧与舱落座
    /// 日后增减自动跟随、不写死数。§260 的帧外段
    /// （帧底→窗口底）量测整段退役：其前提（帧底
    /// 停坞上方）与 §186 探针冲突、生产恒量得 0、
    /// 扣减空转（诊断定案）
    private func measureBottomSpace() {
        guard let window = view.window else { return }
        let frameInWindow = view.convert(
            view.bounds, to: window
        )
        measuredBottomSpace = max(
            0, frameInWindow.maxY - composerTopInWindow
        )
    }

    /// 底留位本体（§263）：已量得走实测、未量得走
    /// 回落种子；施工/距底/落点/有效视口/钮落位全
    /// 部只读本值（实测单源）
    private var effectiveBottomSpace: CGFloat {
        measuredBottomSpace ?? fallbackBottomSpace
    }

    /// 实际施工的底 inset（§263）：实测留位＋单点
    /// 边距（与布局底 padding 合计 24pt 目标总量）
    private var effectiveBottomInset: CGFloat {
        effectiveBottomSpace + bottomMargin
    }

    /// 距底读数（§263）：底界与留位同一实测——以
    /// effectiveBottomInset（实测派生）为标尺，不
    /// 许再读 adjustedContentInset.bottom 自证：
    /// §260 口径下列表停自家最大偏移恒读 0、留位
    /// 多算多少空距就藏多少、回底箭头永不现（诊
    /// 断定案）；换实测标尺后，施工值与量测一旦分
    /// 叉读数即如实显形
    private func currentDistance() -> CGFloat {
        ChatScrollSupply.uiKitDistance(
            contentHeight: Double(scrollView.contentSize.height),
            offsetY: Double(scrollView.contentOffset.y),
            viewportHeight: Double(scrollView.bounds.height),
            bottomInset: Double(effectiveBottomInset)
        ).cgFloat
    }

    private func maxBottomOffsetY() -> CGFloat {
        max(
            -appliedTopInset,
            scrollView.contentSize.height + effectiveBottomInset
                - scrollView.bounds.height
        )
    }

    private func reportScrollGeometry() {
        // 首帧帧未定（bounds 为零）不报：读数全是假
        // 值、会把判定喂偏——与旧承载种子纪律同式，
        // 定版帧到达后自然开报
        guard let handle, scrollView.bounds.height > 0
        else { return }
        // §259：读数产出已移入落定拍，此处同拍再对
        // 齐帧表一次（下方行循环下标与 materialize
        // 同前提：rows 与 rowFrames 同源同长）
        ensureFramesCoherent()
        handle.latestDistance = currentDistance()
        handle.containerHeight = scrollView.bounds.height
        // 末端事实：末行帧完整落在有效视口（扣除底
        // inset 遮挡带）内——与旧承载尾锚事实同义
        if let last = rowFrames.last {
            let visibleTop = scrollView.contentOffset.y
                + appliedTopInset
            let effectiveBottom = scrollView.contentOffset.y
                + scrollView.bounds.height - effectiveBottomInset
            handle.contentEndVisible =
                last.minY >= visibleTop - 1
                && last.maxY <= effectiveBottom + 1
        } else {
            handle.contentEndVisible = false
        }
        // 顶可见条目：首个与有效视口顶相交的条目行
        let visibleTop = scrollView.contentOffset.y
            + appliedTopInset
        var topEntry: UUID?
        for (index, row) in rows.enumerated() {
            if rowFrames[index].maxY > visibleTop {
                topEntry = row.entryID
                break
            }
        }
        lastTopVisibleEntryID = topEntry
        if lastReportedTopVisible == nil
            || lastReportedTopVisible! != topEntry {
            lastReportedTopVisible = topEntry
            callbacks?.onTopVisibleEntry(topEntry)
        }
        callbacks?.onScrollGeometry()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // §259：滚动回调＝系统回调，只许记账不许施
        // 工——记账即排一拍落定，托管与读数产出全
        // 在落定拍执行。旧形态在此同步 materialize：
        // 布局期 setFrame 引发的系统 offset 校正会
        // 同步重入本回调，当时 rows 已换新、rowFrames
        // 未建，materialize 行循环下标必越界（0.50.45
        // 真机 .ips 定案：本文件原 L431 下标陷阱）
        scheduleSettle()
    }

    // MARK: 命令口

    func scrollToBottom(animated: Bool) {
        // §259：命令口同拍校验——消费内容高前先对齐帧表
        ensureFramesCoherent()
        let target = maxBottomOffsetY()
        if animated {
            // 人发起的回底走 Core 回底弹簧参数（ζ＝
            // 1.0、响应按距缩放，BottomScrollSpring
            // 定版）——旧承载的 SwiftUI 弹簧在此以
            // UIKit 弹簧动画同参复现，用户手势可接管
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
                scrollView.contentOffset = CGPoint(
                    x: 0, y: target
                )
            }
        } else {
            scrollView.contentOffset = CGPoint(x: 0, y: target)
        }
    }

    func scrollToEntry(_ id: UUID, animated: Bool) {
        guard let index = rows.firstIndex(
            where: { $0.entryID == id }
        ) else { return }
        // §259：命令口同拍校验——帧表与行集对齐后
        // 再取帧；宽为零帧表建不起时本命令无从落点、
        // 直接返回（非下标守卫，是落点不存在）
        ensureFramesCoherent()
        guard index < rowFrames.count else { return }
        let target = min(
            max(rowFrames[index].minY - appliedTopInset,
                -appliedTopInset),
            maxBottomOffsetY()
        )
        scrollView.setContentOffset(
            CGPoint(x: 0, y: target), animated: animated
        )
    }

    func captureAnchor() -> ChatListAnchor? {
        guard !rows.isEmpty else { return nil }
        if currentDistance() <= 0.5 {
            return .bottom
        }
        let pureTop = Double(
            scrollView.contentOffset.y + appliedTopInset
                - layoutParams.topPadding
        )
        guard let captured = ChatListAnchor.capture(
            frames: pureFrames(), viewportTop: pureTop
        ), let hitID = captured.entryID else { return nil }
        if rows.contains(where: { $0.entryID == hitID }) {
            return captured
        }
        // 命中非条目行（直播区等）：顺延到其后第一
        // 个条目行、条内偏移归零；其后无条目行则本
        // 次不存锚（回落旧锚/首屏定版路）
        guard let hitIndex = frameIDs.firstIndex(of: hitID)
        else { return nil }
        for index in hitIndex..<rows.count {
            if let entryID = rows[index].entryID {
                return ChatListAnchor(
                    entryID: entryID,
                    intraEntryOffset: 0,
                    atBottom: false
                )
            }
        }
        return nil
    }

    func restore(_ anchor: ChatListAnchor) {
        layoutContent(preservePosition: false)
        if anchor.atBottom {
            scrollToBottom(animated: false)
            return
        }
        if let offset = ChatListAnchor.restoredOffsetY(
            frames: pureFrames(),
            anchor: anchor,
            contentOriginY: Double(layoutParams.topPadding),
            topInset: Double(appliedTopInset),
            bottomInset: Double(effectiveBottomInset),
            contentHeight: Double(scrollView.contentSize.height),
            viewportHeight: Double(scrollView.bounds.height)
        ) {
            scrollView.contentOffset = CGPoint(
                x: 0, y: CGFloat(offset)
            )
        }
        ChatDiagTrace.record(
            "换代包3 锚恢复：条目 \(anchor.entryID?.uuidString ?? "nil")"
                + " 条内偏移 \(Int(anchor.intraEntryOffset))pt"
        )
    }

    // MARK: 回底钮浮层（容器 overlay）

    private func applyArrow(view newView: AnyView?) {
        if let newView {
            let host: UIHostingController<AnyView>
            if let existing = arrowHost {
                host = existing
                host.rootView = newView
            } else {
                host = UIHostingController(rootView: newView)
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
                    host.view.transform = CGAffineTransform(
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

    /// 钮落位：右距与旧钮行同值；底缘＝输入舱顶上
    /// 方 gap——舱顶在本容器坐标系＝帧底−实测留位
    /// （§263：留位为承载帧底与舱顶两实测相减，钮
    /// 落位与施工 inset 同源）。钮是 overlay 子视
    /// 图：本函数只改钮自身帧，不触任何滚动记账
    private func layoutArrow() {
        guard let host = arrowHost else { return }
        measureBottomSpace()
        let size = layoutParams.arrowSize
        host.view.frame = CGRect(
            x: view.bounds.width - layoutParams.arrowTrailing
                - size,
            y: view.bounds.height - effectiveBottomSpace
                - layoutParams.arrowGapAboveComposer - size,
            width: size,
            height: size
        )
        view.bringSubviewToFront(host.view)
    }

    // MARK: 点空白收键盘（与 ScrollViewTapDismiss 同口径）

    private var blankTapDelegate: ChatCarrierBlankTapDelegate?

    private func installBlankTapDismiss() {
        let delegate = ChatCarrierBlankTapDelegate { [weak self] in
            self?.callbacks?.onBlankTap()
        }
        let tap = UITapGestureRecognizer(
            target: delegate,
            action: #selector(
                ChatCarrierBlankTapDelegate.handleTap
            )
        )
        tap.name = "OneDayBlankTapDismissCarrier"
        tap.cancelsTouchesInView = false
        tap.delegate = delegate
        scrollView.addGestureRecognizer(tap)
        blankTapDelegate = delegate
    }
}

/// 点空白收键盘的识别器 delegate：仲裁口径与
/// ScrollViewTapDismiss.swift 的定版逐字同义（触点
/// 落在任何 UITextView 子树内不接收、与既有识别器
/// 同时识别、不吞触摸）——旧承载的安装器靠 ascend
/// 找滚动视图，新承载的滚动视图就在自家容器内、
/// 直接装配，故只复用其 delegate 规则、不复用其
/// 寻面装配
final class ChatCarrierBlankTapDelegate: NSObject,
    UIGestureRecognizerDelegate
{
    private let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    @objc func handleTap() {
        onTap()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Representable

struct ChatListCarrierView: UIViewControllerRepresentable {
    var rows: [ChatCarrierRow]
    var layout: ChatCarrierLayout
    var topInset: CGFloat
    /// §263：舱顶窗口系实测（舱宿主 barFrameIn-
    /// Window.minY）与未量得回落（快照派生值、仅
    /// 瞬态种子）、单点边距——底留位自此由承载以
    /// 两实测相减自产，不再喂入派生 inset
    var composerTopInWindow: CGFloat
    var fallbackBottomSpace: CGFloat
    var bottomMargin: CGFloat
    var keyboardAnimationDuration: TimeInterval
    var keyboardAnimationCurveRaw: Int
    var arrowView: AnyView?
    var handle: ChatListCarrierHandle
    var callbacks: ChatListCarrierCallbacks
    /// §260：两宿主注册共用的列表本体句柄（Chat-
    /// View 的 listScrollHandle，与旧承载同一份）；
    /// 装配时透传给控制器、由其登记本体
    var edgeScrollHandle: ChatListScrollViewHandle

    func makeUIViewController(
        context: Context
    ) -> ChatListCarrierViewController {
        let controller = ChatListCarrierViewController()
        controller.handle = handle
        controller.callbacks = callbacks
        controller.edgeScrollHandle = edgeScrollHandle
        handle.controller = controller
        return controller
    }

    func updateUIViewController(
        _ controller: ChatListCarrierViewController,
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
            keyboardAnimationDuration: keyboardAnimationDuration,
            keyboardAnimationCurveRaw: keyboardAnimationCurveRaw,
            arrowView: arrowView
        )
    }
}

private extension Double {
    var cgFloat: CGFloat { CGFloat(self) }
}
