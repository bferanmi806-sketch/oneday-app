import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 聊天原生重建 R3（DESIGN §295，施工图 chat-
/// native-rebuild-blueprint-20261115 §五 R3）：落
/// 定散文行下沉为原生 cell——不再经 SwiftUI 托
/// 管（拆 UIHostingConfiguration＋representable
/// 两层），文本本体直接是 §168 的 SelectableUI-
/// TextView（TextKit 2），文本选择/数据探测/链
/// 接出口全在原生层装配（与 SelectableTextRepre-
/// sentable.makeUIView 逐项同构：关编辑/开选择/
/// 关滚动、dataDetectorTypes＝[.phoneNumber,
/// .link]（包 5 T4 开集随本体迁移）、零 inset/
/// 零 lineFragmentPadding、链接色经 linkTextAt-
/// tributes）。
///
/// 下沉粒度＝行（施工图的「以行型为粒度」口
/// 径）：ChatView 资格判定（nativeProseSpec）只
/// 放行「纯散文行」——助手行须无思考块/图片行/
/// 交付项/文件牌/摘行（呈现与托管形态逐字同构
/// 才下沉），且段序列全为 prose/quote（结构段
/// code/table/taskList/divider 在席的行整行留托
/// 管，行内混合留下一切片）；用户行须只有正文
/// 泡（无引用/图片/文件牌/待发/失败）。本会话刚
/// 落定的条目（streamSettleMap 有记）不下沉——
/// H11 落定不换装字面优先：落定帧须是同一 cell
/// 的 reconfigure，换 cell 类即换装；该条目下次
/// 冷加载（映射不在）时自然下沉。
///
/// 几何与托管形态逐值同源（双形态对拍由装配测
/// 试⑪守）：助手泡左缘/列宽走 §263 屏宽比公式、
/// 泡内边距 bubblePaddingH/V、段间 spacingSM、
/// 分隔与泡间距 spacingS；量高走 Selectable-
/// TextRepresentable.measuredSize 同一台离屏量
/// 测视图（呈现与量测同源是 §168/§251 的既有单
/// 源，本面不另设量测）。行高仍只由集合视图布
/// 局持有（H10）：cell 经 preferredLayoutAttri-
/// butesFitting 报内容高、无帧表、无回写。
///
/// 交互对位（包 5 三件在新承载的落点）：
/// - 右滑回复：行内直接装 SwipeReplyPanInstal-
///   lerView 本体（与 SwiftUI 桥同一视图类、同
///   一 Core SwipeReplyMotion 判据）——辖区帧＝
///   本行内容帧（installer 铺满气泡区、convert
///   到集合视图即 cell 帧口径，施工图 §3.2 #1
///   「辖区帧改读 cell 帧」）；呈现（位移/箭头
///   显形/武装变色/回位）按 SwipeReplyModifier
///   同口径在原生层复刻，判定零自创。
/// - 长按菜单（S3）：UIContextMenuInteraction
///   只挂气泡铬件面（bubbleView），且委托以点
///   位否决守仲裁——点位落在任一文本视图内即
///   返回 nil 终止交互（文本归 UITextView 自家
///   选字＋编辑菜单）、落在边距带才出整行菜单
///   （五项与 MessageMenuModifier 同序同名同
///   图标：回复/在旁聊里接着问/复制/选择/分
///   享；复制走 Pasteboard 收敛口、分享走系统
///   UIActivityViewController＝ShareLink 的
///   UIKit 本体）。
/// - 选区回报/链接出口：文本委托与 representa-
///   ble 的 Coordinator 同语义（选区变→onSel-
///   ectionChange；链接点按→openURL 出口、恒
///   返回 false 不许系统直开）。

// MARK: - 行规格（ChatView 喂入）

/// 原生散文行规格：段落属性串在 ChatView 的
/// SwiftUI 环境内拼装（字体档/墨色解析与 Sele-
/// ctableInlineText 同源同值），回调半边（菜
/// 单/右滑/选区/链接）由 ChatView 注入既有动
/// 作链（beginReply/forkToSideChat/选择 sheet/
/// noteTextSelection/openURL），本面不另立链
struct ChatNativeProseSpec {
    enum Segment {
        /// 合并散文段（§168：一份文本存储）
        case prose(NSAttributedString)
        /// 引用段（竖条＋弱化文本，文本仍是同本体）
        case quote(NSAttributedString)
    }

    var dividerText: String?
    var isUser: Bool
    var segments: [Segment]
    var linkColor: UIColor
    var bubbleFill: UIColor
    var dividerColor: UIColor
    var quoteBarColor: UIColor
    var highlightColor: UIColor
    var highlighted: Bool
    var arrowIdleFill: UIColor
    var arrowArmedFill: UIColor
    var arrowIdleTint: UIColor
    var arrowArmedTint: UIColor
    /// 整行菜单五项与右滑共用动作半边
    var menuPlainText: String
    var onMenuReply: () -> Void
    var onMenuFork: () -> Void
    var onMenuSelect: () -> Void
    var swipeEnabled: Bool
    var onSwipeReply: () -> Void
    var onSelectionChange: (Bool) -> Void
    var openURL: (URL) -> Void
}

// MARK: - 段拼装单源（呈现/产物/测试共用）

/// 落定散文的段拼装：与 MarkdownText 的呈现映
/// 射逐字同源——散文段经 MarkdownText.prose-
/// Paragraphs 映射＋SelectableInlineText.build
/// 拼装（§251 单源：呈现与产物共用映射函数，
/// 本面只换承载不换拼装）；引用段经 quotePar-
/// agraphs 同式。含结构段（code/table/task-
/// List/divider）返回 nil＝整行留托管。拼装结
/// 果按（角色＋全文＋样式键）进程内缓存（与
/// InlineTextRenderCache 同纪律：NSCache 封顶
/// 256），ChatView 每遍 body 重建行集不反复拼装
enum ChatNativeProseAssembly {
    private final class SegmentsBox: NSObject {
        let segments: [ChatNativeProseSpec.Segment]
        init(_ segments: [ChatNativeProseSpec.Segment]) {
            self.segments = segments
        }
    }

    private final class AssemblyCache: @unchecked Sendable {
        static let shared = AssemblyCache()
        private let cache =
            NSCache<NSString, SegmentsBox>()
        init() { cache.countLimit = 256 }
        func object(
            forKey key: NSString
        ) -> [ChatNativeProseSpec.Segment]? {
            cache.object(forKey: key)?.segments
        }
        func setObject(
            _ segments: [ChatNativeProseSpec.Segment],
            forKey key: NSString
        ) {
            cache.setObject(
                SegmentsBox(segments), forKey: key
            )
        }
    }

    static func segments(
        isUser: Bool,
        content: String,
        styleKey: String,
        baseFont: UIFont,
        overrideFont: (UIFont.TextStyle) -> UIFont,
        textColor: UIColor,
        dimmedColor: UIColor,
        quoteTextColor: UIColor
    ) -> [ChatNativeProseSpec.Segment]? {
        let key = (
            (isUser ? "u|" : "a|") + styleKey
                + "|" + content
        ) as NSString
        if let cached = AssemblyCache.shared.object(
            forKey: key
        ) {
            return cached
        }
        let built: [ChatNativeProseSpec.Segment]?
        if isUser {
            // 用户正文：plainRuns 不解析 markdown、
            // 整形只在 run 层施加（与 bubble() 用户
            // 分支逐字同式）
            let paragraph = InlineTextParagraph(
                runs: TextShaping.shapeRuns(
                    InlineRunBuilder.plainRuns(content)
                )
            )
            built = [.prose(SelectableInlineText.build(
                paragraphs: [paragraph],
                baseFont: baseFont,
                overrideFont: overrideFont,
                textColor: textColor,
                dimmedColor: dimmedColor
            ))]
        } else {
            var result: [ChatNativeProseSpec.Segment] = []
            var sinkable = true
            for segment in MarkdownMessageAssembler
                .segments(for: content) {
                switch segment {
                case .prose(let paragraphs):
                    result.append(.prose(
                        SelectableInlineText.build(
                            paragraphs: MarkdownText
                                .proseParagraphs(paragraphs),
                            baseFont: baseFont,
                            overrideFont: overrideFont,
                            textColor: textColor,
                            dimmedColor: dimmedColor
                        )
                    ))
                case .quote(let lines):
                    result.append(.quote(
                        SelectableInlineText.build(
                            paragraphs: MarkdownText
                                .quoteParagraphs(lines),
                            baseFont: baseFont,
                            overrideFont: overrideFont,
                            textColor: quoteTextColor,
                            dimmedColor: quoteTextColor
                        )
                    ))
                case .code, .table, .taskList, .divider:
                    sinkable = false
                }
                if !sinkable { break }
            }
            built = sinkable && !result.isEmpty
                ? result : nil
        }
        if let built {
            AssemblyCache.shared.setObject(
                built, forKey: key
            )
        }
        return built
    }
}

// MARK: - 文本委托（与 representable Coordinator 同语义）

private final class ChatNativeTextDelegate: NSObject,
    UITextViewDelegate
{
    var onSelectionChange: ((Bool) -> Void)?
    var openURL: ((URL) -> Void)?

    func textViewDidChangeSelection(
        _ textView: UITextView
    ) {
        onSelectionChange?(
            textView.selectedRange.length > 0
        )
    }

    /// 链接点按：交 ChatView 的 openURL 出口（与
    /// SwiftUI Text 链接同一出口）、不许系统直开
    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        openURL?(url)
        return false
    }
}

// MARK: - 行视图（手动布局：几何公式与托管形态逐值同源）

final class ChatNativeProseRowView: UIView {
    private let highlightView = UIView()
    private let dividerLabel = UILabel()
    /// 右滑呈现的平移层（只含气泡区：分隔不平
    /// 移——与托管形态 entryRowContent 的背景/
    /// 修饰符分界同界）
    private let swipeContent = UIView()
    private let bubbleView = UIView()
    private let arrowContainer = UIView()
    private let arrowImage = UIImageView()
    private let installer = SwipeReplyPanInstallerView()
    private let textDelegate = ChatNativeTextDelegate()

    private var spec: ChatNativeProseSpec?
    private var currentSegments:
        [ChatNativeProseSpec.Segment] = []
    private var segmentViews: [UIView] = []
    private var segmentBars: [UIView?] = []
    private var textViews: [SelectableUITextView] = []

    private var dragOffset: CGFloat = 0
    private var hasTriggered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        highlightView.layer.cornerRadius =
            OneDayMetrics.containerCorner
        addSubview(highlightView)

        arrowContainer.layer.cornerRadius = 15
        arrowContainer.alpha = 0
        arrowImage.contentMode = .center
        arrowImage.image = UIImage(
            systemName: MessageActionSymbols.reply,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 14, weight: .semibold
            )
        )
        arrowContainer.addSubview(arrowImage)
        addSubview(arrowContainer)

        dividerLabel.textAlignment = .center
        dividerLabel.font = .preferredFont(
            forTextStyle: .footnote
        )
        addSubview(dividerLabel)

        addSubview(swipeContent)
        swipeContent.addSubview(bubbleView)

        // S3：整行菜单只挂气泡铬件面；文本区由委
        // 托点位否决守（见 contextMenuInteraction）
        bubbleView.addInteraction(
            UIContextMenuInteraction(delegate: self)
        )

        installer.isUserInteractionEnabled = false
        installer.backgroundColor = .clear
        installer.onPanChanged = { [weak self] x in
            self?.handlePanChanged(x)
        }
        installer.onPanEnded = { [weak self] in
            self?.handlePanEnded()
        }
    }

    // MARK: 配置与复用

    func configure(_ spec: ChatNativeProseSpec) {
        self.spec = spec

        // 段身份短路（§168 同纪律：内容键未变绝不
        // 重设文本——重设即冲选区）：拼装缓存同键
        // 恒同实例，段属性串逐一恒等即视为内容未
        // 变、文本视图整批保留（选区/手柄原样存
        // 续），只更新标量属性与门控。选区形成本
        // 身会经回报翻新行版本（右滑门控）触发本
        // 方法——短路是它不自毁的前提。真换内容
        // 时才结清旧选区（与 representable 的
        // dismantle 同口：回报关闭、免记账悬空）
        let segmentsUnchanged =
            spec.segments.count == currentSegments.count
            && zip(spec.segments, currentSegments)
                .allSatisfy { pair in
                    pair.0.attributed === pair.1.attributed
                }
        if segmentsUnchanged {
            applyScalarSpec(spec)
            return
        }
        if textViews.contains(
            where: { $0.selectedRange.length > 0 }
        ) {
            spec.onSelectionChange(false)
        }
        currentSegments = spec.segments

        for view in segmentViews {
            view.removeFromSuperview()
        }
        segmentViews = []
        segmentBars = []
        textViews = []
        for segment in spec.segments {
            switch segment {
            case .prose(let attributed):
                let textView = makeTextView(
                    attributed, linkColor: spec.linkColor
                )
                bubbleView.addSubview(textView)
                segmentViews.append(textView)
                segmentBars.append(nil)
                textViews.append(textView)
            case .quote(let attributed):
                let container = UIView()
                let bar = UIView()
                bar.backgroundColor = spec.quoteBarColor
                bar.layer.cornerRadius = 1.5
                container.addSubview(bar)
                let textView = makeTextView(
                    attributed, linkColor: spec.linkColor
                )
                container.addSubview(textView)
                bubbleView.addSubview(container)
                segmentViews.append(container)
                segmentBars.append(bar)
                textViews.append(textView)
            }
        }
        resetSwipePresentation()
        applyScalarSpec(spec)
    }

    /// 标量规格应用（内容未变时 configure 的唯一
    /// 动作）：分隔/气泡/点亮的呈现值、文本委托
    /// 回调、右滑桥门控——全是无副作用的属性写，
    /// 不碰文本视图本体
    private func applyScalarSpec(
        _ spec: ChatNativeProseSpec
    ) {
        dividerLabel.text = spec.dividerText
        dividerLabel.textColor = spec.dividerColor
        dividerLabel.isHidden = spec.dividerText == nil
        if let dividerText = spec.dividerText {
            dividerLabel.accessibilityLabel =
                "时间 \(dividerText)"
        }
        // §321（2026-11-17 助手回复呈现对齐）：助
        // 手行撤气泡填充——文本直落列表背景（与托
        // 管形态 assistantBubble 同步撤填充，几何
        // §263 逐值不动：列宽/左缘/内边距全保留、
        // 只去掉承载面本身）；bubbleView 本体保留
        // 作菜单/右滑的铬件面（命中与交互不依赖填
        // 充色）。用户泡填充逐字不动。§225 的恢复
        // 气泡口径被用户 2026-11-17 指令取代（见
        // DESIGN §321 沿革）
        bubbleView.backgroundColor = spec.isUser
            ? spec.bubbleFill : .clear
        bubbleView.layer.cornerRadius = spec.isUser
            ? OneDayMetrics.bubbleCorner
            : OneDayMetrics.assistantBubbleCorner
        highlightView.backgroundColor = spec.highlighted
            ? spec.highlightColor : .clear
        for textView in textViews {
            textView.linkTextAttributes = [
                .foregroundColor: spec.linkColor
            ]
        }

        textDelegate.onSelectionChange =
            spec.onSelectionChange
        textDelegate.openURL = spec.openURL

        if spec.swipeEnabled {
            if installer.superview == nil {
                swipeContent.addSubview(installer)
                swipeContent.sendSubviewToBack(installer)
            }
            installer.installIfNeeded()
        } else {
            installer.uninstall()
            installer.removeFromSuperview()
        }
        setNeedsLayout()
    }

    /// cell 复用清理（与 prepareForReuse 对位）：
    /// 摘桥、清选区记账、复位平移与箭头
    func resetForReuse() {
        if let spec,
           textViews.contains(
               where: { $0.selectedRange.length > 0 }
           ) {
            spec.onSelectionChange(false)
        }
        installer.uninstall()
        installer.removeFromSuperview()
        spec = nil
        currentSegments = []
        for view in segmentViews {
            view.removeFromSuperview()
        }
        segmentViews = []
        segmentBars = []
        textViews = []
        dragOffset = 0
        hasTriggered = false
        swipeContent.transform = .identity
        arrowContainer.alpha = 0
    }

    /// 文本视图本体装配：与 SelectableTextRep-
    /// resentable.makeUIView 逐项同构（§168 本
    /// 体子类＋TK2 钉死＋T4 探测开集）
    private func makeTextView(
        _ attributed: NSAttributedString,
        linkColor: UIColor
    ) -> SelectableUITextView {
        let textView = SelectableUITextView(
            usingTextLayoutManager: true
        )
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = [.phoneNumber, .link]
        textView.delegate = textDelegate
        textView.attributedText = attributed
        textView.linkTextAttributes = [
            .foregroundColor: linkColor
        ]
        return textView
    }

    // MARK: 几何（与托管形态逐值同源）

    private struct RowLayout {
        var height: CGFloat = 0
        var dividerFrame: CGRect = .zero
        var bubbleFrame: CGRect = .zero
        /// 段帧（bubbleView 坐标系）
        var segmentFrames: [CGRect] = []
        /// 引用段的文本子帧（段容器坐标系；散文段为 nil）
        var quoteTextFrames: [CGRect?] = []
    }

    private func computeLayout(
        width: CGFloat
    ) -> RowLayout {
        guard let spec else { return RowLayout() }
        var layout = RowLayout()
        let padH = OneDayMetrics.bubblePaddingH
        let padV = OneDayMetrics.bubblePaddingV
        var y: CGFloat = 0
        if let dividerText = spec.dividerText {
            let font = UIFont.preferredFont(
                forTextStyle: .footnote
            )
            let textHeight = ceil(
                (dividerText as NSString).size(
                    withAttributes: [.font: font]
                ).height
            )
            layout.dividerFrame = CGRect(
                x: 0, y: 0, width: width,
                height: textHeight
            )
            y += textHeight + OneDayMetrics.spacingS
        }
        if spec.isUser {
            // 用户泡：Spacer(minLength: bubbleSide-
            // Inset) 让位后右对齐；正文宽走同一台
            // 量测视图的 sizeThatFits 返回值（与
            // representable 的 SwiftUI 尺寸口径同
            // 源——短文抱合、长文封顶换行）
            let attributed = spec.segments[0].attributed
            let proposal = width
                - OneDayMetrics.bubbleSideInset
                - padH * 2
            let measured = SelectableTextRepresentable
                .measuredSize(
                    attributed: attributed,
                    proposal: ProposedViewSize(
                        width: max(1, proposal),
                        height: nil
                    )
                )
            let bubbleWidth = measured.width + padH * 2
            let bubbleHeight = measured.height + padV * 2
            layout.bubbleFrame = CGRect(
                x: width - bubbleWidth, y: y,
                width: bubbleWidth, height: bubbleHeight
            )
            layout.segmentFrames = [CGRect(
                x: padH, y: padV,
                width: measured.width,
                height: measured.height
            )]
            layout.quoteTextFrames = [nil]
            layout.height = y + bubbleHeight
            return layout
        }
        // 助手泡（§263）：左缘＝屏宽×左缘占屏比、
        // 文宽＝屏宽×文宽占屏比（量测喂入同值）；
        // cell 内坐标以行内容宽为原点重演托管公
        // 式（HStack 的 leading padding 可为负值，
        // 与 SwiftUI 同许）
        let screenWidth = UIScreen.main.bounds.width
        let columnCap = screenWidth
            * OneDayMetrics.assistantTextWidthFraction
            + padH * 2
        let leading = screenWidth
            * OneDayMetrics.assistantTextLeadingFraction
            - OneDayMetrics.pageGutter
            - padH
        let bubbleWidth = min(
            columnCap, width - leading
        )
        let textWidth = bubbleWidth - padH * 2
        var segmentY = padV
        for segment in spec.segments {
            let segmentWidth: CGFloat
            switch segment {
            case .prose:
                segmentWidth = textWidth
            case .quote:
                // 引用段可用宽＝文宽−（竖条 3＋间距
                // spacingS）（§251 引用宽口径）
                segmentWidth = textWidth - 3
                    - OneDayMetrics.spacingS
            }
            let height = SelectableTextRepresentable
                .measuredSize(
                    attributed: segment.attributed,
                    proposal: ProposedViewSize(
                        width: max(1, segmentWidth),
                        height: nil
                    )
                ).height
            layout.segmentFrames.append(CGRect(
                x: padH, y: segmentY,
                width: textWidth, height: height
            ))
            if case .quote = segment {
                layout.quoteTextFrames.append(CGRect(
                    x: 3 + OneDayMetrics.spacingS, y: 0,
                    width: segmentWidth, height: height
                ))
            } else {
                layout.quoteTextFrames.append(nil)
            }
            segmentY += height + OneDayMetrics.spacingSM
        }
        let bubbleHeight = segmentY
            - OneDayMetrics.spacingSM + padV
        layout.bubbleFrame = CGRect(
            x: leading, y: y,
            width: bubbleWidth, height: bubbleHeight
        )
        layout.height = y + bubbleHeight
        return layout
    }

    override func sizeThatFits(
        _ size: CGSize
    ) -> CGSize {
        let width = size.width > 0
            ? size.width : bounds.width
        guard width > 0 else { return size }
        return CGSize(
            width: width,
            height: computeLayout(width: width).height
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlightView.frame = bounds
        guard spec != nil, bounds.width > 0 else { return }
        let layout = computeLayout(width: bounds.width)
        dividerLabel.frame = layout.dividerFrame
        swipeContent.frame = layout.bubbleFrame
        bubbleView.frame = swipeContent.bounds
        installer.frame = swipeContent.bounds
        for (index, view) in segmentViews.enumerated() {
            guard index < layout.segmentFrames.count
            else { break }
            view.frame = layout.segmentFrames[index]
            if let bar = segmentBars[index],
               let textFrame = layout
                   .quoteTextFrames[index] {
                bar.frame = CGRect(
                    x: 0, y: 0, width: 3,
                    height: view.frame.height
                )
                textViews[index].frame = textFrame
            }
        }
        arrowContainer.frame = CGRect(
            x: 4,
            y: layout.bubbleFrame.midY - 15,
            width: 30, height: 30
        )
        arrowImage.frame = arrowContainer.bounds
    }

    // MARK: 测试与普查读口（与 SwipeReplyPan-
    // InstallerView.installedRecognizer 同例：装
    // 配断言够得着原生装配本体，不许测试侧另搭
    // 同形结构充数）

    var testTextViews: [SelectableUITextView] {
        textViews
    }

    var testBubbleView: UIView { bubbleView }

    var testInstaller: SwipeReplyPanInstallerView {
        installer
    }

    var testSwipeOffsetX: CGFloat {
        swipeContent.transform.tx
    }

    var testArrowAlpha: CGFloat {
        arrowContainer.alpha
    }

    // MARK: 右滑呈现（SwipeReplyModifier 同口径）

    private func handlePanChanged(_ translationX: CGFloat) {
        guard let spec, spec.swipeEnabled else { return }
        let newOffset = SwipeReplyMotion.dragOffset(
            translationWidth: translationX,
            currentOffset: dragOffset
        )
        dragOffset = newOffset
        applySwipePresentation()
        if !hasTriggered,
           SwipeReplyMotion.shouldTrigger(
               offset: newOffset
           ) {
            hasTriggered = true
            // 轻触觉与引用落定同一因果链、只震一次
            // （与 SwipeReplyModifier 同点）
            Haptics.impact(.light)
            spec.onSwipeReply()
        }
    }

    private func handlePanEnded() {
        hasTriggered = false
        dragOffset = 0
        // 回位动画＝MotionTokens.swap 的 UIKit 镜
        // 像（easeInOut 0.2；Reduce Motion 时无动画
        // ——MotionTokens.resolved 的同义处置）
        if UIAccessibility.isReduceMotionEnabled {
            applySwipePresentation()
            return
        }
        UIView.animate(
            withDuration: 0.2, delay: 0,
            options: [.curveEaseInOut,
                      .beginFromCurrentState]
        ) {
            self.applySwipePresentation()
        }
    }

    private func applySwipePresentation() {
        guard let spec else { return }
        swipeContent.transform = CGAffineTransform(
            translationX: SwipeReplyMotion.displayOffset(
                for: dragOffset
            ),
            y: 0
        )
        let progress = SwipeReplyMotion.revealProgress(
            offset: dragOffset
        )
        let armed = SwipeReplyMotion.shouldTrigger(
            offset: dragOffset
        )
        arrowContainer.alpha = progress
        arrowContainer.transform = CGAffineTransform(
            scaleX: 0.6 + 0.4 * progress,
            y: 0.6 + 0.4 * progress
        )
        arrowContainer.backgroundColor = armed
            ? spec.arrowArmedFill : spec.arrowIdleFill
        arrowImage.tintColor = armed
            ? spec.arrowArmedTint : spec.arrowIdleTint
    }

    private func resetSwipePresentation() {
        dragOffset = 0
        hasTriggered = false
        swipeContent.transform = .identity
        arrowContainer.alpha = 0
    }

    // MARK: 分享（ShareLink 的 UIKit 本体）

    private func presentShare(text: String) {
        var presenter = window?.rootViewController
        while let next = presenter?
            .presentedViewController {
            presenter = next
        }
        guard let presenter else { return }
        let activity = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        activity.popoverPresentationController?
            .sourceView = bubbleView
        presenter.present(activity, animated: true)
    }
}

extension ChatNativeProseSpec.Segment {
    /// 段的属性串（布局量测与测试取证共用读口）
    var attributed: NSAttributedString {
        switch self {
        case .prose(let attributed),
             .quote(let attributed):
            return attributed
        }
    }
}

// MARK: - 整行菜单（S3 原生挂载面）

extension ChatNativeProseRowView:
    UIContextMenuInteractionDelegate
{
    /// 点位仲裁（S3 在原生层的落法）：交互挂气
    /// 泡铬件面（bubbleView），但点位落在任一文
    /// 本视图帧内即返回 nil——交互当场终止、触
    /// 摸完整归 UITextView 自家选字与编辑菜单；
    /// 落在气泡边距带（背景＋内边距区）才出整行
    /// 菜单。五项与 MessageMenuModifier 同序同
    /// 名同图标（SF Symbol 标识即 UI 测试的语言
    /// 无关判据）
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let spec else { return nil }
        for textView in textViews {
            let frame = textView.convert(
                textView.bounds, to: bubbleView
            )
            if frame.contains(location) {
                return nil
            }
        }
        return UIContextMenuConfiguration(
            identifier: nil, previewProvider: nil
        ) { _ in
            UIMenu(title: "", children: [
                UIAction(
                    title: "回复",
                    image: UIImage(systemName:
                        MessageActionSymbols.reply)
                ) { _ in spec.onMenuReply() },
                UIAction(
                    title: "在旁聊里接着问",
                    image: UIImage(systemName:
                        MessageActionSymbols.fork)
                ) { _ in spec.onMenuFork() },
                UIAction(
                    title: "复制",
                    image: UIImage(systemName:
                        MessageActionSymbols.copy)
                ) { _ in
                    Pasteboard.copy(spec.menuPlainText)
                },
                UIAction(
                    title: "选择",
                    image: UIImage(systemName:
                        MessageActionSymbols.select)
                ) { _ in spec.onMenuSelect() },
                UIAction(
                    title: "分享",
                    image: UIImage(systemName:
                        MessageActionSymbols.share)
                ) { [weak self] _ in
                    self?.presentShare(
                        text: spec.menuPlainText
                    )
                },
            ])
        }
    }
}

// MARK: - 原生散文 cell

/// 原生散文 cell：内容只有 ChatNativeProse-
/// RowView 一层；自适应高经 preferredLayout-
/// AttributesFitting 报行视图的内容高（compo-
/// sitional .estimated＋selfSizingInvalidation
/// 的标准自适应口，H10 行高只由布局持有）
final class ChatNativeProseCell: UICollectionViewCell {
    static let reuseID = "ChatNativeProseCell"

    let rowView = ChatNativeProseRowView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        rowView.frame = contentView.bounds
        rowView.autoresizingMask = [
            .flexibleWidth, .flexibleHeight,
        ]
        contentView.addSubview(rowView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        rowView.frame = contentView.bounds
        rowView.autoresizingMask = [
            .flexibleWidth, .flexibleHeight,
        ]
        contentView.addSubview(rowView)
    }

    func configure(with spec: ChatNativeProseSpec) {
        rowView.configure(spec)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        rowView.resetForReuse()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes:
            UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy()
            as! UICollectionViewLayoutAttributes
        let fitted = rowView.sizeThatFits(CGSize(
            width: layoutAttributes.size.width,
            height: CGFloat.greatestFiniteMagnitude
        ))
        attributes.size = CGSize(
            width: layoutAttributes.size.width,
            height: fitted.height
        )
        return attributes
    }
}
