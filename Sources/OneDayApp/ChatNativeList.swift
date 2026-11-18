import OneDayCore
import OneDayDesign
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
/// keyboardLayoutGuide（H8），§302 起改回 §194
/// 通知帧顶单常量形态（见下 H8 沿革）。
///
/// §325（B 档退役，2026-11-17；同根审计 chat-
/// page-root-audit-20261117 §5 定案）：自造三件
/// 整套退役——①双 cell 形态：R3 的原生散文 cell
/// （ChatNativeProseCell）整件删除，落定行统一走
/// 托管 cell 单渲染路径，内容 facet 只影响行内呈
/// 现、不再决定行是哪种 cell（§320.1 的形态翻转
/// 先删后插分流随之退役——无形态可翻）；②行高估
/// 算管线：产物层估算（carrierRowEstimate／占位
/// 均值聚合）退出列表关键路径，compositional 的
/// .estimated 只留固定常量供未物化区滚动几何，
/// 物化行高一律由 UIHostingConfiguration 自适应
/// ＋selfSizingInvalidation 由框架持有收敛；
/// ③手维护版本哈希：行版本（Int 折算）退役，改
/// ChatNativeRowRevision 结构化派生——行描述的
/// 渲染输入全量值比较（Equatable），条目行由条
/// 目模型全字段快照单点派生（见 revision 节）。
///
/// §329（布局环结构修，2026-11-18；定因 crash-
/// 05068-diagnosis-20261118）：.67/.68 真机同签
/// 名复崩证实 §325 ②「行高归框架自适应」不成立
/// ——环由 compositional post-pass 自我失效驱
/// 动、与 App 侧闸门无关。本节改：行高由量测
/// 栈同步合成（ChatNativeRowHeight）回喂、布
/// 局改 section-per-row＋.absolute 消费（框架
/// 不再估算→修正）；apply 入 §325.2 滚动闸
/// （滚动期整笔记账、停滚落定拍消费）。§325
/// ①③与 §325.2 守卫、selfSizingInvalidation
/// 档位、§321 均不动，详见 DESIGN §329。
///
/// 几何纪律（施工图 §四硬约束）：
/// - H1 间距单源：相邻消息纵向间距只由 section
///   的 interGroupSpacing 一处声明（spacingL 24）；
///   cell 内容不带任何泡外纵 padding，时间分隔仍
///   长在条目 cell 内（ChatView 行内容自带）。
/// - H2/H10 行高单权威、无帧表：本类没有任何帧
///   表、任何量实回填——行高由 ChatView 的合成
///   器（§329）同步算定、随行描述喂入，布局以
///   .absolute 逐 section 消费（section-per-
///   row）；contentSize 只由集合视图自己持有；
///   托管拟合高永不回写（拟合与布局脱钩是布局
///   环的构造拆除，定因见 §329）。
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
/// - H8 键盘跟随（R2 换代→§302 回 §194 形态）：
///   R2 曾定「只走 keyboardLayoutGuide」——舱底
///   钉本视图引导线顶、引导线逐帧驱动。2026-
///   11-16 用户 .59 真机录屏证伪（定因报告 key-
///   board-rise-diagnosis-20261116）：引导线在本
///   层级（SwiftUI 托管内嵌控制器）真机不追踪真
///   键盘、舱全程钉坞位被键盘盖住，与 §193→
///   §194 病史同族；其真机门 A2/A3 从未回填即
///   随 .59 转默认。§302 落位回 §194 形态：舱底
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
///   照旧）；但 kbSnapshot 供数自 §302 起同源
///   收口：同一通知解析点在驱动舱常量的同拍组
///   装 KeyboardFrameUpdate 经 onKeyboardFrame-
///   Change 喂 ChatView 的 kbFrameUpdate（与旧
///   面 ComposerGuideHost 同一口径、同一快照，
///   不许第二套）——isKeyboardUp／聚焦藏坞在
///   新面恢复触发（定因 K2 的修法）。

// MARK: - 行修订值（§325 结构化派生，代手维护版本哈希）

/// 行修订值：行「变没变」的唯一判据——不再是手
/// 工折算的 Int 哈希（carrierEntryVersion 一类：
/// facet 枚举漏一项、该行永不重配，§320 文件牌
/// 即此病），而是行渲染输入的**全量值**有序清单，
/// Equatable 逐值比较。清单由构造点按渲染输入逐
/// 项填入（文本填全文、数据填本体、标量填原值），
/// 不折长度、不折哈希——比较的是值本身。
struct ChatNativeRowRevision: Equatable {
    enum Part: Equatable {
        case text(String)
        case data(Data)
        case flag(Bool)
        case count(Int)
        case real(Double)
    }

    var parts: [Part] = []

    init(parts: [Part] = []) {
        self.parts = parts
    }

    mutating func addText(_ value: String?) {
        parts.append(.flag(value != nil))
        parts.append(.text(value ?? ""))
    }

    mutating func addData(_ value: Data?) {
        parts.append(.flag(value != nil))
        if let value { parts.append(.data(value)) }
    }

    mutating func addFlag(_ value: Bool) {
        parts.append(.flag(value))
    }

    mutating func addCount(_ value: Int) {
        parts.append(.count(value))
    }

    mutating func addReal(_ value: Double?) {
        parts.append(.flag(value != nil))
        parts.append(.real(value ?? 0))
    }

    /// 条目行修订值（单点派生）：按 ChatEntry 落盘
    /// 字段的声明序全量快照——渲染的一切 facet
    /// （正文/工具卡/思考/引用四族/图片与文件路径/
    /// 回响三键/发送状态）都由这些字段派生（计算
    /// 属性 allImageDatas/remoteImagePaths/toolCard
    /// 等无一例外），字段值不变则渲染输入不变、任
    /// 一字段变则修订必变，不存在「漏折一项」的清
    /// 单可漏。环境侧渲染输入（分隔文案/锚点点亮/
    /// 选区在场/样式键）同列入账。
    static func entry(
        _ entry: ChatEntry,
        dividerText: String?,
        highlighted: Bool,
        selectionActive: Bool,
        styleKey: String
    ) -> ChatNativeRowRevision {
        var revision = ChatNativeRowRevision()
        revision.addText(entry.role)
        revision.addText(entry.content)
        revision.addData(entry.imageData)
        revision.addData(entry.imageDatasData)
        revision.addText(entry.quoteRole)
        revision.addText(entry.quoteContent)
        revision.addText(entry.feedPostID)
        revision.addText(entry.feedPostTitle)
        revision.addText(entry.feedPostBody)
        revision.addText(entry.feedPostSource)
        revision.addText(entry.ideaQuoteID)
        revision.addText(entry.ideaQuoteTitle)
        revision.addText(entry.ideaQuoteBody)
        revision.addText(entry.fileQuoteName)
        revision.addText(entry.fileQuotePath)
        revision.addText(entry.goalQuoteCategory)
        revision.addText(entry.reasoning)
        revision.addReal(entry.reasoningSeconds)
        revision.addData(entry.toolCardData)
        revision.addData(entry.remoteImagePathsData)
        revision.addData(entry.remoteFilePathsData)
        revision.addText(entry.echoKey)
        revision.addText(entry.approvalKey)
        revision.addText(entry.traceKey)
        revision.addData(entry.traceEchoData)
        revision.addFlag(entry.sendFailed)
        revision.addText(entry.sendStateRaw)
        revision.addText(entry.deliveryState)
        revision.parts.append(
            .real(entry.createdAt.timeIntervalSinceReferenceDate)
        )
        revision.addText(dividerText)
        revision.addFlag(highlighted)
        revision.addFlag(selectionActive)
        revision.addText(styleKey)
        return revision
    }
}

// MARK: - 行描述（ChatView 喂入）

/// 原生面行菜单描述（§330，0.50.70 热修题 2）：
/// 行菜单的动作集——与 SwiftUI MessageMenu-
/// Modifier 同源同序同图符（回复／在旁聊里接着
/// 问／复制／选择／分享），由 ChatView 在行构造
/// 点以条目现成闭包组装。原生面自 §330 起菜单
/// 承载换 UIKit UIContextMenuInteraction 挂
/// cell 本体（见托管 cell 节）；gen3 面不消费本
/// 描述（其菜单仍走 SwiftUI .contextMenu）
struct ChatNativeRowContextMenu {
    let plainText: String
    let onReply: () -> Void
    let onFork: () -> Void
    let onSelect: () -> Void
    let onShare: () -> Void

    /// 菜单本体：项集/序/图符与 MessageMenu-
    /// Modifier 的 SwiftUI 菜单逐项一致，不改产
    /// 品语义；复制走 Pasteboard 收敛口径（与
    /// CopyButton 同源一处）
    func makeMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: "回复",
                image: UIImage(
                    systemName: MessageActionSymbols.reply
                )
            ) { _ in onReply() },
            UIAction(
                title: "在旁聊里接着问",
                image: UIImage(
                    systemName: MessageActionSymbols.fork
                )
            ) { _ in onFork() },
            UIAction(
                title: "复制",
                image: UIImage(
                    systemName: MessageActionSymbols.copy
                )
            ) { _ in Pasteboard.copy(plainText) },
            UIAction(
                title: "选择",
                image: UIImage(
                    systemName: MessageActionSymbols.select
                )
            ) { _ in onSelect() },
            UIAction(
                title: "分享",
                image: UIImage(
                    systemName: MessageActionSymbols.share
                )
            ) { _ in onShare() },
        ])
    }
}

/// 原生面行：身份键（diffable 条目身份，与 gen3
/// 行键同名同源）＋条目 id（锚/顶可见用，非条目
/// 行为 nil）＋修订值（渲染输入全量值、变→
/// reconfigure 原位更新，§325）＋行高（§329 量
/// 测回喂固定高：由 ChatView 的高度合成器同步
/// 算定、布局以 .absolute 消费——框架不再估
/// 算→修正，见 DESIGN §329）＋视图构建闭包
/// （只在（重）配置 cell 时调用）。§325 起全体
/// 行只有托管 cell 一种形态——本描述不再携带
/// 形态判别
struct ChatNativeRow {
    let key: String
    let entryID: UUID?
    let revision: ChatNativeRowRevision
    /// §329 回喂高（pt）：合成器未给的构造点（测
    /// 试手搓行等）回落固定常量——单值、永不随
    /// 行集聚合（兜底口径见 §329）
    let height: CGFloat
    let makeView: () -> AnyView
    /// §330 行菜单（原生面 UIKit 承载）：仅条目
    /// 行由 ChatView 喂入（与 SwiftUI 菜单同门
    /// 控——正文空不挂）；其余行恒 nil
    let contextMenu: ChatNativeRowContextMenu?

    init(
        key: String, entryID: UUID?,
        revision: ChatNativeRowRevision = ChatNativeRowRevision(),
        height: CGFloat = ChatNativeRowHeightComposer
            .fallbackHeight,
        makeView: @escaping () -> AnyView,
        contextMenu: ChatNativeRowContextMenu? = nil
    ) {
        self.key = key
        self.entryID = entryID
        self.revision = revision
        self.height = height
        self.makeView = makeView
        self.contextMenu = contextMenu
    }
}

// MARK: - 布局参数匣（compositional 布局提供者只认本匣、不认控制器本体）

private final class ChatNativeLayoutBox {
    var horizontalPadding: CGFloat = 20
    var topPadding: CGFloat = 16
    var bottomPadding: CGFloat = 8
    var rowSpacing: CGFloat = 24
    /// §325：未物化区滚动几何的固定占位高——只此
    /// 一个常量、不再由行估算聚合派生（产物层估
    /// 算管线退役）。§329 后只余布局提供者越界
    /// （section 序超出当前行集）的防御回落
    static let estimatedPlaceholder: CGFloat = 120
    /// §329：当前行集的回喂高（序＝行序）：布局
    /// 提供者按 section 序直读本表给 .absolute
    /// 高；apply 落写、提供者只读，两处不许各算
    /// 一份
    var rowHeights: [CGFloat] = []
    /// §325.2 布局 pass 计数口（section 提供者被调
    /// 用次数）：收敛压测的 pass 数读数——稳态下强
    /// 制布局/重复 apply 不得再触发 section 重建；
    /// 生产路径只多一次计数、无行为影响
    private(set) var sectionProviderCallCount = 0
    func noteSectionProviderCall() {
        sectionProviderCallCount += 1
    }
}

// MARK: - 托管 cell

/// 托管 cell：UIHostingConfiguration 只渲染——
/// 内容以行键为 SwiftUI 身份（复用时状态不跨条
/// 目串行，施工图 §七风险 2）；拟合尺寸由集合视
/// 图布局自己消费，本类不读、不记（H10）
/// §330（0.50.70 热修题 2）：行菜单承载在本类——
/// UIContextMenuInteraction 直接挂 cell 本体，
/// 不再走托管内容内的 SwiftUI .contextMenu（强
/// 加帧内托管视图的布局结果不可恃、.69 真机长
/// 按全灭，定因见 hotfix-05070-diagnosis）。点
/// 位否决沿 §265：点落在任一文本视图帧内→归文
/// 本体系（选字/编辑菜单），行菜单不触发；非文
/// 本区（气泡背景/内边距带/行内铬件）→出行菜单
/// （internal 而非 private：装配测试须以生产原
/// 物读配置普查与菜单 delegate——与控制器/合成
/// 器的 internal 测试面同式）
final class ChatNativeHostingCell: UICollectionViewCell,
    UIContextMenuInteractionDelegate
{
    static let reuseID = "ChatNativeHostingCell"

    /// 配置普查（测试读口，与布局匣计数口同式：
    /// 生产路径只多两次赋值、无行为影响）：本
    /// cell 的配置次数与最近配置行键——§330 在
    /// 途延后的断言以此为据（在途行计数不动、清
    /// 零后恰涨一次）
    private(set) var configureCount = 0
    private(set) var configuredKey: String?

    /// 本行菜单描述（configure 落写、复用清零）；
    /// nil＝本行无菜单（门控与 ChatView 构造点同
    /// 口径：正文空的纯图片行不挂）
    private var rowMenu: ChatNativeRowContextMenu?
    private var menuInteraction: UIContextMenuInteraction?
    /// 行菜单呈现中（willDisplay→willEnd 记账）：
    /// 呈现中的菜单锚在本 cell 上，本标记供题 1
    /// 在途读数——呈现期间不许换代本 cell 内容
    private(set) var isContextMenuPresented = false

    func configure(with row: ChatNativeRow) {
        configureCount += 1
        configuredKey = row.key
        rowMenu = row.contextMenu
        if rowMenu != nil {
            installMenuInteractionIfNeeded()
        }
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
        rowMenu = nil
        configuredKey = nil
        isContextMenuPresented = false
    }

    private func installMenuInteractionIfNeeded() {
        guard menuInteraction == nil else { return }
        let interaction = UIContextMenuInteraction(
            delegate: self
        )
        addInteraction(interaction)
        menuInteraction = interaction
    }

    // MARK: 行菜单（UIContextMenuInteraction）

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let rowMenu else { return nil }
        // §265 点位否决：点在文本视图帧内不出行菜单
        if Self.pointIsOnTextView(location, in: self) {
            return nil
        }
        return UIContextMenuConfiguration(
            identifier: nil, previewProvider: nil
        ) { _ in rowMenu.makeMenu() }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration:
            UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        isContextMenuPresented = true
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration:
            UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        isContextMenuPresented = false
    }

    // willPerformPreviewAction 不实现：预览即 cell
    // 本体（previewProvider 恒 nil 的系统默认形
    // 态）、点预览无导航语义，delegate 缺省收口即
    // 标准路（本 SDK 的 CommitAnimating 无 commit
    // 成员，自实现反而越界）

    /// 点位否决判据：点（cell 坐标）落在托管内容
    /// 子树任一 UITextView 的帧内——文本视图是
    /// 选字/编辑菜单的辖区（§265），行菜单让行。
    /// internal：装配测试以生产原物验本判据
    static func pointIsOnTextView(
        _ point: CGPoint, in cell: UIView
    ) -> Bool {
        for frame in textViewFrames(in: cell) {
            if frame.contains(point) { return true }
        }
        return false
    }

    private static func textViewFrames(
        in root: UIView
    ) -> [CGRect] {
        var frames: [CGRect] = []
        func walk(_ view: UIView) {
            for subview in view.subviews {
                if let textView = subview as? UITextView {
                    frames.append(
                        textView.convert(
                            textView.bounds, to: root
                        )
                    )
                }
                walk(subview)
            }
        }
        walk(root)
        return frames
    }

    // MARK: 手势在途读数（§330 题 1）

    /// 本 cell 辖内有手势在途：任一识别器处于
    /// began/changed（文本选字长按/拖选、行菜单
    /// 长按、右滑桥 pan——桥识别器本体在宿主滚
    /// 动视图上、经其安装视图的普查读口读），或
    /// 行菜单呈现中。在途为真时控制器延后本行
    /// reconfigure：托管视图中途换代会令识别器
    /// 随宿主消亡、双击序列与长按计时被静默吞掉
    /// （.69 真机双击/长按全灭的候选机理 C）
    var hasGestureInFlight: Bool {
        if isContextMenuPresented { return true }
        return Self.subtreeHasActiveGesture(self)
    }

    private static func subtreeHasActiveGesture(
        _ view: UIView
    ) -> Bool {
        for recognizer in view.gestureRecognizers ?? [] {
            if recognizer.state == .began
                || recognizer.state == .changed {
                return true
            }
        }
        if let installer =
            view as? SwipeReplyPanInstallerView,
           let pan = installer.installedRecognizer,
           pan.state == .began || pan.state == .changed {
            return true
        }
        for subview in view.subviews {
            if subtreeHasActiveGesture(subview) {
                return true
            }
        }
        return false
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
    private var revisionsByKey:
        [String: ChatNativeRowRevision] = [:]
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
    /// 是舱落位的唯一数（§302 回 §194 形态：键
    /// 盘态＝通知帧顶、静息态＝坞实测顶，sync-
    /// BottomConstant 唯一计算点）。装配测试经
    /// internal 读口取其帧
    private(set) var composerHost:
        UIHostingController<AnyView>?
    /// §302：键盘帧更新回调（representable 桥接
    /// 回 ChatView 的 kbFrameUpdate 绑定）——与
    /// 舱常量同一通知解析点同拍组装（reportKey-
    /// boardFrame），帧顶已转窗口坐标、动画参数
    /// 原值；快照本体仍是 ChatView 的 kbSnapshot
    /// 一份，本容器不另持快照
    var onKeyboardFrameChange: ((KeyboardFrameUpdate) -> Void)?
    /// §302 位置引导线：top 由 bottomGuideTop-
    /// Constraint 的常量定位（布局空间换算，见
    /// syncBottomConstant）；舱底恒钉其 topAnchor、
    /// 约束永不切换激活态（§194「模式即病灶」）
    private let bottomGuide = UILayoutGuide()
    private var bottomGuideTopConstraint: NSLayoutConstraint!
    /// §302 坞锚当前参照（UITabBar 本体或类名兜
    /// 底命中；回落态为 nil 且 dockIsFallback＝
    /// true，参照＝窗口安全区底）——与 §194 同
    /// 式：只读其实帧、永不被约束直接引用
    private weak var dockBarView: UIView?
    private var dockIsFallback = false
    private weak var anchorWindow: UIWindow?
    /// §302.1 续作：回落态布局拍重解析的上次尝试
    /// 时刻——回落壳内恒无坞时每拍全窗遍历找坞会
    /// 扰动落定收敛时序，布局拍自愈加 0.3s 节流
    /// （窗口变化与离散触发点不经此闸，见
    /// viewDidLayoutSubviews／resolveAnchors）
    private var lastFallbackResolveAt: CFTimeInterval = 0
    private var keyboardUp = false
    /// §302 键盘顶存账（窗口坐标）：willShow/
    /// willChangeFrame 通知的结束帧顶——键盘本
    /// 人广播的真值，常量换算的唯一键盘输入；
    /// 收起即清
    private var keyboardTopInWindow: CGFloat?
    /// 视图未装载时到达的舱内容（装载拍补装）
    private var pendingComposerView: AnyView?
    /// 落定拍调度账（与 gen3 §259 同式：滚动回调
    /// 只记账、施工与读数产出统一在落定拍）
    private var settleScheduled = false
    /// §325.2：布局参数变更的失效记账（apply 只记
    /// 账、落定拍 pass 外合并施工，见 apply 注）
    private var pendingLayoutInvalidation = false
    /// §325.2：滚动期被冻结的落定拍记账（滚动结束
    /// 回调合并落写时消费）
    private var settleDeferredDuringScroll = false
    /// §329：滚动期到达的整笔 apply 喂入（滚动闸
    /// 记账槽，与 §325.2 冻结同族——停滚后由落定
    /// 拍先行消费、再走原有落写链；后到覆盖先到，
    /// 与 representable 只认最新喂入同义）
    private struct PendingApply {
        var rows: [ChatNativeRow]
        var layout: ChatCarrierLayout
        var topInset: CGFloat
        var bottomMargin: CGFloat
        var composerView: AnyView?
        var arrowView: AnyView?
    }
    private var pendingApply: PendingApply?
    /// §330（0.50.70 热修题 1）：手势在途延后重配
    /// 的留账键集——落写时可见 cell 正有识别器在
    /// 途的行，其 reconfigure 延后一拍（托管视图
    /// 中途换代会吞掉在途的双击/长按）；键留本集
    /// 作重试源（修订记账已按新行落写、修订差不
    /// 会再检出本键），后续每趟 apply 与每记落定
    /// 拍都复读在途态重试、在途清零即落写
    private var gestureDeferredReconfigureKeys:
        Set<String> = []
    /// 落点意图（H6）：冷开/命令贴底置真；落定拍
    /// 判达标＋几何跨拍稳定后消（§302.3）、或用
    /// 户拖动接管即消
    private var landingIntent = false
    /// 落点意图置真时刻（收敛重拍的时间窗预算起
    /// 点，见 performSettleBeat 的尾差处理）
    private var landingIntentSince: CFTimeInterval = 0
    /// §302.3 意图消费的几何稳定账：上一落定拍的
    /// contentSize——与本拍逐值同才算几何静止；消
    /// 费另须本拍钉前已在底（上一钉熬过整拍布局
    /// 冲刷、迟到回调未现形），意图置真/消解时清零
    private var landingSettleContentSize: CGFloat?
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
            sectionIndex, _ in
            box.noteSectionProviderCall()
            return ChatRootViewController.makeSection(
                box: box, sectionIndex: sectionIndex
            )
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
            sectionIndex, _ in
            box.noteSectionProviderCall()
            return ChatRootViewController.makeSection(
                box: box, sectionIndex: sectionIndex
            )
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
        // View 属性、非 layout 属性）：托管内容
        // （SwiftUI 拟合）的尺寸变化即自动重测，不
        // 手算不回填（H9/H10）。§325.2 守卫 3③ 定
        // 档：.enabled（内容尺寸变化才失效）——最激
        // 进档 .enabledIncludingConstraints（cell 内
        // 任何约束变化即失效）是 .66 崩溃成环三件
        // 套之一（诊断定因），托管内容的尺寸变化经
        // 托管视图本体上报、.enabled 已足；两档收敛
        // 对照由 R3 ⑮′ 压测实证（pass 数入 CI 日志）
        collectionView.selfSizingInvalidation =
            .enabled
        collectionView.register(
            ChatNativeHostingCell.self,
            forCellWithReuseIdentifier:
                ChatNativeHostingCell.reuseID
        )
        makeDataSource()
    }

    /// compositional 单列 section（§329 改 section-
    /// per-row）：一行一 section、item/group 高＝
    /// .absolute(该行回喂高)——框架不估算、不修
    /// 正，post-pass 偏移修正按构造不存在。间距
    /// 仍单源（H1）：行距改由 section 底 inset 承
    /// 担（非末行＝rowSpacing、末行＝bottomPad-
    /// ding、首行顶＝topPadding），总几何与旧
    /// interGroupSpacing 口径逐值等价；左右 inset
    /// 恒 horizontalPadding。提供者越界（序≥行集
    /// 长）回落固定占位常量（防御、正常路径不达）
    private static func makeSection(
        box: ChatNativeLayoutBox, sectionIndex: Int
    ) -> NSCollectionLayoutSection {
        let rowCount = box.rowHeights.count
        let height = sectionIndex < rowCount
            ? box.rowHeights[sectionIndex]
            : ChatNativeLayoutBox.estimatedPlaceholder
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(max(0, height))
        )
        let item = NSCollectionLayoutItem(
            layoutSize: itemSize
        )
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(max(0, height))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize, subitems: [item]
        )
        let section = NSCollectionLayoutSection(
            group: group
        )
        section.contentInsets = NSDirectionalEdgeInsets(
            top: sectionIndex == 0 ? box.topPadding : 0,
            leading: box.horizontalPadding,
            bottom: sectionIndex >= rowCount - 1
                ? box.bottomPadding : box.rowSpacing,
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
        // §302：位置引导线入本视图（top 常量待
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
        // §302 键盘信号（与 §194 同式）：willShow/
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
        // §302 锚解析触发点之一（入窗后窗口已定）：
        // 与 §194 的入窗/显形重解析同式——切格往返
        // 期间标签栏实例若被换过，在此换新参照
        resolveAnchors()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveAnchors()
    }

    // MARK: 键盘跟随（§302 回 §194 形态）

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

    /// §302 帧变化跟进（交互式下滑收键盘/候选条
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

    /// §302 键盘帧顶存账：通知的结束帧是屏幕坐
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

    /// §302 键盘态翻转：升起先把通知帧顶存账（常
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

    /// §302 锚解析：在本视图所在窗口的层级里找坞
    /// 参照（UITabBar 本体或类名兜底），只登记引
    /// 用与命中模式——位置由 syncBottomConstant
    /// 逐拍换算进位置常量，参照本身不被任何约束
    /// 引用。触发点只在离散事件（入窗/显形/键盘
    /// 收起）与回落态布局拍自愈——后者经
    /// viewDidLayoutSubviews 的 0.3s 节流闸（§302.1
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

    /// §302 位置常量唯一计算点：bottomGuide 的
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

    /// §302 键盘帧更新包的组装点——与 updateKey-
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

    /// §325 引导线重验采样口（装配测试专用、只读）：
    /// 本视图 keyboardLayoutGuide 顶边的窗口坐标——
    /// 与通知帧顶同帧对账的测试读口（生产采样走
    /// sampleGuideForTrace 自述通道、本口不参与驱
    /// 动）
    /// §325.2 测试读口：布局 pass 计数（section 提
    /// 供者调用数）——长历史收敛压测断言 pass 数有
    /// 界/稳态零重建用，生产无消费
    var testSectionProviderCallCount: Int {
        layoutBox.sectionProviderCallCount
    }

    /// §329 测试读口：当前行集的回喂高（布局匣
    /// rowHeights 的只读镜像）——生产链压测对账
    /// 「采用高 vs 帧高」用，生产无消费
    var testAdoptedRowHeights: [CGFloat] {
        layoutBox.rowHeights
    }

    /// §325.2 测试口：selfSizingInvalidation 档位
    /// 对照压测用（生产默认 .enabled，见装配处注）
    var testSelfSizingInvalidation:
        UICollectionView.SelfSizingInvalidation {
        get { collectionView.selfSizingInvalidation }
        set { collectionView.selfSizingInvalidation = newValue }
    }

    var testKeyboardGuideTopInWindow: CGFloat? {
        guard let window = view.window else { return nil }
        return view.convert(
            CGPoint(
                x: 0,
                y: view.keyboardLayoutGuide.layoutFrame.minY
            ),
            to: window
        ).y
    }

    /// §302 引导线采样对照（只记自述、永不驱动）：
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
            "原生面 §302 [\(event)] kbTopWin=\(kbText) "
                + "guideTopWin="
                + String(format: "%.1f", guideTopInWindow)
        )
    }

    // MARK: 输入舱收编（R2／§302）

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
    /// 拍传到本约束（§302，见键盘跟随节），舱随
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
                // §325：单渲染路径——全体行只有托管
                // cell 一种形态，内容 facet 只决定行
                // 内呈现（makeView 本体），不决定 cell
                // 类；reconfigure 恒同注册原地重配
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
        // §302：本拍先做位置常量同步——窗口未解
        // 析（入窗前）或回落态（标签栏随呈现时序
        // 迟到）在此补解析、找到即退出回落；常量
        // 只读缓存的坞参照实帧/键盘存账帧顶（与
        // §194 布局拍纪律同式）。§302.1 续作：回
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
        // §325.2 守卫 1：inset 施工（reconcileInsets
        // 与 measureBottomSpace）迁出布局拍——本拍
        // 只记账排落定拍，施工归落定拍在 pass 外合
        // 并执行（诊断守卫条目 1 点名本处）。键盘动
        // 画期本拍逐帧到达、落定拍在帧间逐拍合并落
        // 写，跟随链不断（§302 对账改走落定拍）
        scheduleSettle()
        if (wasAtBottom || landingIntent)
            && !userInteracting {
            pinToBottom()
            // §302.3：布局拍只钉不消费意图——末钉
            // 之后集合视图内部布局拍仍可能迟到回调
            // offset（compositional 锚点保全，见落
            // 定拍注），消费判据须跨拍验几何稳定、
            // 统一归落定拍（performSettleBeat）
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
        // §329 滚动闸：滚动期（tracking/deceler-
        // ating）到达的喂入整笔只记账、不施工——
        // 与 §325.2 落定拍冻结共用同一记账（settle-
        // DeferredDuringScroll），停滚后由 flush-
        // DeferredSettle→落定拍先消费本槽再落写。
        // 削 apply 在滚动中开启布局 pass 的触发面；
        // 非滚动期行为逐字不变（走 applyNow）
        if collectionView.isTracking
            || collectionView.isDecelerating {
            pendingApply = PendingApply(
                rows: newRows, layout: layout,
                topInset: topInset,
                bottomMargin: newMargin,
                composerView: composerView,
                arrowView: arrowView
            )
            settleDeferredDuringScroll = true
            return
        }
        applyNow(
            rows: newRows, layout: layout,
            topInset: topInset, bottomMargin: newMargin,
            composerView: composerView,
            arrowView: arrowView
        )
    }

    private func applyNow(
        rows newRows: [ChatNativeRow],
        layout: ChatCarrierLayout,
        topInset: CGFloat,
        bottomMargin newMargin: CGFloat,
        composerView: AnyView?,
        arrowView: AnyView?
    ) {
        // 布局参数同步进匣：间距/内边距任一变即失
        // 效布局（compositional 声明式重算，不手
        // 算帧——H10）。§325 起 .estimated 占位是
        // 固定常量、不随行集变化，不入本对账
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
        if paramsChanged {
            // §325.2 守卫集：invalidateLayout 不许在
            // apply（representable update）内同步执行
            // ——布局参数只记账，失效施工归落定拍在
            // pass 外合并执行一次（值真变才记账，本
            // 分支即是）。2026-11-17 .66 真机崩溃链
            // （compositional 在可见 cell 更新 pass 内
            // 自我 invalidate 自递归至 UIKit 断言）的
            // 防线之一：任何喂入路径都不许在布局 pass
            // 可达的同步链里碰布局失效
            pendingLayoutInvalidation = true
        }

        let newByKey = Dictionary(
            uniqueKeysWithValues: newRows.map {
                ($0.key, $0)
            }
        )
        let oldKeys = rows.map(\.key)
        let newKeys = newRows.map(\.key)
        // §325：重配对账只认修订值全量比较——同键
        // 行的渲染输入任一值变即 reconfigure 原位
        // 更新；单形态下 reconfigure 恒同注册、不
        // 再有跨形态翻转分流（§320.1 退役）
        let keysChanged = oldKeys != newKeys
        let revisionMismatchKeys = newKeys.filter {
            revisionsByKey[$0] != nil
                && revisionsByKey[$0]
                    != newByKey[$0]?.revision
        }
        // §330（题 1）手势在途分流：候选＝修订差
        // ∪ 在途留账（留账键的修订差已被上趟记账
        // 吃掉、只认本集重试）；逐键读其可见 cell
        // 的在途态（cell 尚按旧行序在屏、索引走旧
        // 键序）——在途者本拍不重配、留账下拍重试，
        // 其余照旧落写。高度-only 变化不入候选（候
        // 选只由修订差与留账构成）、本就不触发重
        // 配——回归断言在装配测试钉住
        var candidateKeys = revisionMismatchKeys
        for key in gestureDeferredReconfigureKeys
        where newByKey[key] != nil
            && !candidateKeys.contains(key) {
            candidateKeys.append(key)
        }
        let (reconfigureKeys, gestureDeferred) =
            partitionGestureDeferred(
                candidateKeys, orderedKeys: oldKeys
            )
        gestureDeferredReconfigureKeys = gestureDeferred
        if !gestureDeferred.isEmpty {
            scheduleSettle(delay: 0.3)
        }
        let wasEmpty = rows.isEmpty
        rows = newRows
        rowsByKey = newByKey
        // §329：回喂高落写布局匣——须先于快照 apply
        // （apply 触发的布局 pass 即读新高）；高变
        // 而键/修订未变时（如展开态翻转、异步 facet
        // 到达），布局失效走既有记账、落定拍唯一
        // 施工口合并落写（§325.2 条目 1 同路）
        let newHeights = newRows.map(\.height)
        let heightsChanged =
            layoutBox.rowHeights != newHeights
        if heightsChanged {
            layoutBox.rowHeights = newHeights
            pendingLayoutInvalidation = true
        }
        if keysChanged {
            var snapshot =
                NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections(
                Array(newKeys.indices)
            )
            for (index, key) in newKeys.enumerated() {
                snapshot.appendItems(
                    [key], toSection: index
                )
            }
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
                landingSettleContentSize = nil
            }
        } else if !reconfigureKeys.isEmpty {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(reconfigureKeys)
            dataSource.apply(
                snapshot, animatingDifferences: false
            )
        }
        revisionsByKey = Dictionary(
            uniqueKeysWithValues: newRows.map {
                ($0.key, $0.revision)
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
            // （§302）
            fedTopInset = topInset
            measureBottomSpace()
            handle?.bottomInset = effectiveBottomInset
        }
        applyComposer(view: composerView)
        if keysChanged || !reconfigureKeys.isEmpty
            || insetChanged || paramsChanged
            || heightsChanged {
            scheduleSettle()
        }
        applyArrow(view: arrowView)
    }

    /// §330（题 1）在途分流：候选键逐个读其可见
    /// cell 的手势在途态——在途者延后（留账下拍
    /// 重试）、其余本拍落写。cell 不在屏（无 cell
    /// 可读）或键不在现行序内恒落写：在途只存在
    /// 于可见 cell
    private func partitionGestureDeferred(
        _ candidates: [String],
        orderedKeys: [String]
    ) -> (ready: [String], deferred: Set<String>) {
        var ready: [String] = []
        var deferred: Set<String> = []
        for key in candidates {
            guard let index = orderedKeys
                    .firstIndex(of: key),
                  let cell = collectionView
                    .cellForItem(
                        at: IndexPath(
                            item: 0, section: index
                        )
                    ) as? ChatNativeHostingCell
            else {
                ready.append(key)
                continue
            }
            if cell.hasGestureInFlight {
                deferred.insert(key)
            } else {
                ready.append(key)
            }
        }
        return (ready, deferred)
    }

    /// §330（题 1）在途延后重配的落写口（落定拍
    /// 在整笔喂入消费后调用）：留账键逐个复读在
    /// 途态，清零者以现行快照 reconfigure 落写
    /// （cell 供应器读 rowsByKey 现行行）；仍在途
    /// 者留账并续排一拍。在途窗口以秒计（长按菜
    /// 单呈现/拖选），0.3s 一拍的重试成本只是一
    /// 次可见 cell 读数
    private func flushGestureDeferredReconfigures() {
        guard !gestureDeferredReconfigureKeys.isEmpty
        else { return }
        let present = gestureDeferredReconfigureKeys
            .filter { rowsByKey[$0] != nil }
        let (ready, deferred) =
            partitionGestureDeferred(
                Array(present),
                orderedKeys: rows.map(\.key)
            )
        gestureDeferredReconfigureKeys = deferred
        let snapshotItems = Set(
            dataSource.snapshot().itemIdentifiers
        )
        let applicable = ready.filter {
            snapshotItems.contains($0)
        }
        if !applicable.isEmpty {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(applicable)
            dataSource.apply(
                snapshot, animatingDifferences: false
            )
        }
        if !deferred.isEmpty {
            scheduleSettle(delay: 0.3)
        }
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
        if collectionView.isTracking
            || collectionView.isDecelerating {
            // §325.2 守卫 2③＋4：滚动期冻结——本拍
            // 只记账（report 轻量读数照常产出）、不
            // 施工：不写 inset、不钉底、不消费布局失
            // 效记账；滚动结束回调（didEndDrag 不减
            // 速／didEndDecelerating）一次性合并落写。
            // 手势中不改视口几何（诊断守卫口径）
            settleDeferredDuringScroll = true
            report()
            return
        }
        if let pending = pendingApply {
            // §329：滚动闸记账的消费口——停滚后第
            // 一拍先落写整笔喂入（其引发的布局失效
            // 记账由紧随的既有合并口同拍消费），再
            // 走本拍余下链（量测/inset/落位）
            pendingApply = nil
            applyNow(
                rows: pending.rows,
                layout: pending.layout,
                topInset: pending.topInset,
                bottomMargin: pending.bottomMargin,
                composerView: pending.composerView,
                arrowView: pending.arrowView
            )
        }
        // §330（题 1）：在途延后重配的落写——须在
        // 整笔喂入消费之后（行集已是最新），布局失
        // 效施工之前（重配引发的布局需求由紧随的
        // 合并口同拍消费）
        flushGestureDeferredReconfigures()
        if pendingLayoutInvalidation {
            // §325.2：布局失效的唯一施工口——落定拍
            // 在布局 pass 外、同拍合并执行一次，随后
            // layoutIfNeeded 冲刷收敛
            pendingLayoutInvalidation = false
            collectionView.collectionViewLayout
                .invalidateLayout()
        }
        collectionView.layoutIfNeeded()
        measureBottomSpace()
        reconcileInsets()
        if let anchor = pendingAnchor {
            pendingAnchor = nil
            executeRestore(anchor)
        } else if landingIntent && !userInteracting {
            let prePinDistance = currentDistance()
            pinToBottom()
            let csNow = collectionView.contentSize.height
            if prePinDistance <= 0.5
                && currentDistance() <= 0.5
                && landingSettleContentSize == csNow {
                // §302.3 消费判据＝上一钉熬过整拍：
                // 本拍开口（布局冲刷后、钉前）已在
                // 底＋钉后仍在底＋contentSize 与上一
                // 落定拍逐值同，才许消费意图。定因
                // （§302.3 量测）：落定链可达算术
                // max 且落点稳定（直设 3352 三读不
                // 动），残差是末钉之后集合视图内部
                // 布局拍迟到回调 offset（composi-
                // tional 锚点保全、R1 期 ≤2pt 残差
                // 同族；回调量随收敛几何走 3.3–4）——
                // 回调在本拍开口布局落地即现形于
                // prePinDistance、不许消费，须由后
                // 续拍重钉且整拍无回调才收口
                landingIntent = false
                landingSettleContentSize = nil
            } else if CACurrentMediaTime()
                - landingIntentSince < 2.0 {
                // 收敛尾差（H6）：意图存续期内延迟
                // 重拍（与 gen3 §259 落定拍的
                // asyncAfter 同式）——真实迟到修正
                // （如图片落图改行高）落地后重钉、收
                // 敛即停；预算按时间窗不按次数。2 秒
                // 窗外仍未收敛则停拍、残差由现测读数
                // 如实呈报不假装在底
                landingSettleContentSize = csNow
                scheduleSettle(delay: 0.05)
            } else {
                landingSettleContentSize = nil
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
                       item: 0, section: rows.count - 1
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
        // 条目行（非条目行跳过、继续向下找条目行）。
        // §325.2 守卫 4：只查可见 cell（indexPaths-
        // ForVisibleItems、至多一屏行数），禁全 rows
        // 遍历——旧式全表扫描在长会话下每拍 O(n)，
        // 是 .66 滚动卡顿的放大器（诊断候选 2）
        let visibleTop = collectionView.contentOffset.y
            + collectionView.contentInset.top
        var topEntry: UUID?
        let visibleItems = collectionView
            .indexPathsForVisibleItems.map(\.section).sorted()
        for index in visibleItems {
            guard index < rows.count,
                  let entryID = rows[index].entryID,
                  let attrs = collectionView
                    .layoutAttributesForItem(
                        at: IndexPath(item: 0, section: index)
                    ),
                  attrs.frame.maxY > visibleTop
            else { continue }
            topEntry = entryID
            break
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
        landingSettleContentSize = nil
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate {
            userInteracting = false
            flushDeferredSettle()
        }
    }

    func scrollViewDidEndDecelerating(
        _ scrollView: UIScrollView
    ) {
        userInteracting = false
        flushDeferredSettle()
    }

    /// §325.2：滚动期冻结的施工在滚动结束一次性
    /// 合并落写（守卫 2③ 的落写口）
    private func flushDeferredSettle() {
        guard settleDeferredDuringScroll else { return }
        settleDeferredDuringScroll = false
        scheduleSettle()
    }

    // MARK: 命令口（句柄转发目标，与 gen3 容器同名同义）

    func scrollToBottom(animated: Bool) {
        landingIntent = true
        landingIntentSince = CACurrentMediaTime()
        landingSettleContentSize = nil
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
                at: IndexPath(item: 0, section: index)
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
                    at: IndexPath(item: 0, section: index)
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
                    at: IndexPath(item: 0, section: index)
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
    /// 边钉其位置引导线（§302 通知帧顶常量驱
    /// 动）；底几何的喂入自此只剩本内容本体，无
    /// 舱顶/动画参数喂入
    var composerView: AnyView
    /// §302：键盘帧更新收件槽（ChatView 的 kb-
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

    /// §302：把控制器的键盘帧回调接回 ChatView
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
