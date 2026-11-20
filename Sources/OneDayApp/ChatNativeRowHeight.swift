import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 行高合成器（§329）：聊天列表 .absolute 回喂高
/// 的唯一出处——由 ChatView 在 nativeRows() 逐行
/// 同步合成、随 ChatNativeRow.height 喂入布局。
///
/// 同源纪律（§251 不分家）：文本量测走呈现本体
/// 同一拼装（SelectableInlineText.build＋Mark-
/// downText.proseParagraphs/quoteParagraphs）＋同
/// 一量测台（SelectableTextRepresentable.refer-
/// enceHeight，§251 对拍基准台）；结构段与 facet
/// 高按各自视图几何逐项确定性合成（公式出处随
/// 各函数注）。合成输入与呈现读同一批状态源：条
/// 目模型、EntryScanMemo 扫描、FileMetadataStore
/// 存在性、DeliveryStore 登记 meta、行状态账本
/// （展开/审批详情）——任一源变化都经 ChatView
/// 重渲回到本合成器，不存在第二份高度事实。
///
/// 兜底（§329 入册）：facet 按视图本体的未就绪
/// 形态合成（未确证＝降级形态、meta 未到＝0），
/// 就绪后经重渲回填；整体不可达的防御分支用固
/// 定常量 fallbackHeight（单值、永不聚合）。
/// §331（题 3 根治）形态注：本合成器自 .70 起分
/// 两层——@MainActor 适配器（现行 init：持账本/
/// 宿主活读源，负责备忘键、facet 快照与量测工
/// 单组装）＋去隔离核心（facet 快照 init：只读
/// 值快照与环境，公式本体全在此层，线程无关、
/// 可在量测台后台队列整行执行）。核心读点一律
/// 经 facet 访问器（见 facet 节），活读源只许
/// 适配器与摘要函数碰——核心在后台算出与主线
/// 程同步算逐值同高，由对拍测试钉住
struct ChatNativeRowHeightComposer {
    /// 防御兜底高（§329）：单值常量、沿旧占位常
    /// 量语义，只在合成整体不可达时用。
    /// nonisolated：ChatNativeRow 的默认参数在
    /// 非隔离上下文引用本值（CGFloat 值类型、
    /// 恒定不变，隔离无意义）
    nonisolated static let fallbackHeight: CGFloat = 120

    /// 列表内容宽（屏宽−左右 inset 40）
    let contentWidth: CGFloat
    /// 助手正文宽（屏宽×文宽占屏比，与气泡布局
    /// 封顶同值，§263 单源）
    let assistantTextWidth: CGFloat
    let sizeCategory: UIContentSizeCategory
    let boldText: Bool
    let displayScale: CGFloat
    /// 活读源（适配器形态在席；量测台形态为 nil）
    let ledger: ChatRowStateLedger?
    let hubStore: AgentHubStore?
    let agentDisplayName: String
    let emptyStateAvatarSize: CGFloat
    /// 环境原值（量测工单按此重建核心）
    let screenWidth: CGFloat
    let horizontalPadding: CGFloat
    /// facet 快照（核心唯一外部输入；适配器形态
    /// 由各入口在调用核心前按行填入本值的副本）
    var facets = ChatNativeRowFacets()

    init(
        screenWidth: CGFloat,
        horizontalPadding: CGFloat,
        sizeCategory: UIContentSizeCategory,
        boldText: Bool,
        displayScale: CGFloat,
        ledger: ChatRowStateLedger,
        hubStore: AgentHubStore,
        agentDisplayName: String,
        emptyStateAvatarSize: CGFloat
    ) {
        self.contentWidth = screenWidth
            - horizontalPadding * 2
        self.assistantTextWidth = screenWidth
            * OneDayMetrics.assistantTextWidthFraction
        self.sizeCategory = sizeCategory
        self.boldText = boldText
        self.displayScale = displayScale
        self.ledger = ledger
        self.hubStore = hubStore
        self.agentDisplayName = agentDisplayName
        self.emptyStateAvatarSize = emptyStateAvatarSize
        self.screenWidth = screenWidth
        self.horizontalPadding = horizontalPadding
    }

    /// 量测台形态（§331）：无活读源、facets 为唯
    /// 一外部输入——供后台队列整行量测
    init(
        screenWidth: CGFloat,
        horizontalPadding: CGFloat,
        sizeCategory: UIContentSizeCategory,
        boldText: Bool,
        displayScale: CGFloat,
        agentDisplayName: String,
        emptyStateAvatarSize: CGFloat,
        facets: ChatNativeRowFacets
    ) {
        self.contentWidth = screenWidth
            - horizontalPadding * 2
        self.assistantTextWidth = screenWidth
            * OneDayMetrics.assistantTextWidthFraction
        self.sizeCategory = sizeCategory
        self.boldText = boldText
        self.displayScale = displayScale
        self.ledger = nil
        self.hubStore = nil
        self.agentDisplayName = agentDisplayName
        self.emptyStateAvatarSize = emptyStateAvatarSize
        self.screenWidth = screenWidth
        self.horizontalPadding = horizontalPadding
        self.facets = facets
    }

    // MARK: - 量测基元（与呈现同台）

    private var bodyBaseFont: UIFont {
        InlineTextFonts.baseFont(
            textStyle: .body,
            category: sizeCategory, boldText: boldText
        )
    }

    private func spec(
        _ style: UIFont.TextStyle
    ) -> CGFloat {
        InlineTextFonts.specLineHeight(
            textStyle: style,
            category: sizeCategory, boldText: boldText
        )
    }

    /// 未钉字重的纯文本字体（走 baseFont：粗体文
    /// 本开关的 semibold 升档与呈现同口径）
    private func plainFont(
        _ style: UIFont.TextStyle
    ) -> UIFont {
        InlineTextFonts.baseFont(
            textStyle: style,
            category: sizeCategory, boldText: boldText
        )
    }

    /// 钉字重字体（.weight() 烘入的文本不受无障碍
    /// 粗体环境影响，FontRoles 粗体映射注同口径）：
    /// preferredFont 按档取本体后叠字重 trait
    private func weightedFont(
        _ style: UIFont.TextStyle,
        _ weight: UIFont.Weight
    ) -> UIFont {
        let preferred = UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: sizeCategory
            )
        )
        let descriptor = preferred.fontDescriptor
            .addingAttributes([
                UIFontDescriptor.AttributeName.traits: [
                    UIFontDescriptor.TraitKey.weight:
                        weight.rawValue,
                ],
            ])
        return UIFont(descriptor: descriptor, size: 0)
    }

    private func monospacedFont(
        _ style: UIFont.TextStyle
    ) -> UIFont {
        let preferred = UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: sizeCategory
            )
        )
        guard let descriptor = preferred.fontDescriptor
            .withDesign(.monospaced)
        else { return preferred }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// 纯文本量测（呈现同台）：拼装口径与 Select-
    /// ableInlineText.build 的段落样式同（词断行、
    /// 段后距 0）；空串由量测台回字体行高（与视
    /// 图渲染空 Text 占一行同值）
    private func measurePlain(
        _ text: String,
        font: UIFont,
        width: CGFloat,
        lineLimit: Int? = nil,
        styleForLimit: UIFont.TextStyle? = nil
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font, .paragraphStyle: style,
            ]
        )
        var height = ChatNativeTextMeasure.height(
            attributed: attributed, width: width,
            emptyLineHeight: font.lineHeight
        )
        if let lineLimit, let styleForLimit {
            height = min(
                height,
                spec(styleForLimit) * CGFloat(lineLimit)
            )
        }
        return height
    }

    private func plainHeight(
        _ text: String,
        _ style: UIFont.TextStyle,
        width: CGFloat,
        lineLimit: Int? = nil
    ) -> CGFloat {
        measurePlain(
            text, font: plainFont(style), width: width,
            lineLimit: lineLimit, styleForLimit: style
        )
    }

    private func weightedHeight(
        _ text: String,
        _ style: UIFont.TextStyle,
        _ weight: UIFont.Weight,
        width: CGFloat,
        lineLimit: Int? = nil
    ) -> CGFloat {
        measurePlain(
            text, font: weightedFont(style, weight),
            width: width,
            lineLimit: lineLimit, styleForLimit: style
        )
    }

    /// SwiftUI Text 单行实高（§329 续修校准实证）：
    /// UIFont 行高按显示像素向上取整——与量测台
    /// 的 spec 步长不同值（例 .footnote：实高
    /// 15.67 vs spec 18），凡呈现走 SwiftUI Text
    /// 的单行字（限行 1 的标题/标签类）走本式
    private func swiftLineHeight(_ font: UIFont) -> CGFloat {
        (font.lineHeight * displayScale).rounded(.up)
            / displayScale
    }

    /// SwiftUI Text 多行实高（§329 续修校准实
    /// 证）：折行点与量测台一致（同为 TextKit 折
    /// 行）、逐行量值不同——行数＝量测高÷字阶
    /// spec 步长取整，实高＝首行（swiftLine-
    /// Height）＋(行数−1)×spec 步长。校准集逐
    /// 值验算：思考正文 6 行 105.67、代码 5 行
    /// 87.67、工具详情等宽 3 行 46.33 全中。
    /// 凡呈现走 SwiftUI Text 的多行文本（代码/
    /// 思考正文/工具详情/表格格值）走本式，不
    /// 许再直用量测高
    private func swiftTextHeight(
        measured: CGFloat,
        stepStyle: UIFont.TextStyle,
        firstLineFont: UIFont
    ) -> CGFloat {
        guard measured > 0 else { return measured }
        let step = spec(stepStyle)
        guard step > 0 else { return measured }
        let lines = max(
            1, Int((measured / step).rounded())
        )
        return swiftLineHeight(firstLineFont)
            + CGFloat(lines - 1) * step
    }

    /// 自然单行宽（表格列宽/回响时间列宽用）
    private func naturalWidth(
        _ text: String, font: UIFont
    ) -> CGFloat {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        return ChatNativeTextMeasure.naturalWidth(
            attributed: attributed
        )
    }

    /// 拼装量测（散文/引用/任务项正文）：与产物
    /// 层 build 同一拼装口（LayoutProductService
    /// .build 的 assemble 同式——颜色只作量测工
    /// 件属性、不影响高，解析口径照抄同源）
    private func assembledHeight(
        paragraphs: [InlineTextParagraph],
        foreground: Color,
        width: CGFloat
    ) -> CGFloat {
        let assembled = SelectableInlineText.build(
            paragraphs: paragraphs,
            baseFont: bodyBaseFont,
            overrideFont: { textStyle in
                InlineTextFonts.baseFont(
                    textStyle: textStyle,
                    category: sizeCategory,
                    boldText: boldText
                )
            },
            textColor: Self.resolved(foreground),
            dimmedColor: Self.resolved(
                Palette.inkSecondaryOnFill
            )
        )
        return ChatNativeTextMeasure.height(
            attributed: assembled, width: width,
            emptyLineHeight: bodyBaseFont.lineHeight
        )
    }

    /// 环境外解析颜色（与 LayoutProductService
    /// .resolved 同式：量测工件用、不影响高）
    private static func resolved(
        _ color: Color
    ) -> UIColor {
        var environment = EnvironmentValues()
        environment.colorScheme =
            UITraitCollection.current.userInterfaceStyle
                == .dark ? .dark : .light
        return UIColor(
            cgColor: color.resolve(in: environment)
                .cgColor
        )
    }

    // MARK: - 文本高备忘（同内容×宽×样式只量一次）

    /// nonisolated(unsafe)：NSCache 官方文档保
    /// 证线程安全（§331 起备忘被量测台后台队列
    /// 读写）、只是未标 Sendable——由本注背书
    /// §333：与整行备忘（rowCache 1024）同轨封
    /// 顶——旧形态无 countLimit，长会话文本备忘
    /// 无界涨、与整行层口径不一致
    private nonisolated(unsafe) static let textCache:
        NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1024
        return cache
    }()

    private func memoKey(
        _ kind: String, _ text: String, _ width: CGFloat
    ) -> NSString {
        let hash = LayoutProductKey.fnv1a(text)
        return "\(kind)|\(hash)|\(text.utf8.count)"
            + "|\(LayoutProductKey.quantizedWidth(Double(width)))"
            + "|\(sizeCategory.rawValue)|\(boldText ? "b" : "r")"
            as NSString
    }

    private func memoized(
        _ kind: String, _ text: String, _ width: CGFloat,
        _ compute: () -> CGFloat
    ) -> CGFloat {
        let key = memoKey(kind, text, width)
        if let hit = Self.textCache.object(forKey: key) {
            return CGFloat(hit.doubleValue)
        }
        let value = compute()
        Self.textCache.setObject(
            NSNumber(value: Double(value)), forKey: key
        )
        return value
    }

    // MARK: - 整行高备忘（§330 题 3 interim）

    /// 整行备忘（0.50.70 热修 §330，题 3 interim）：
    /// §329 后每次 ChatView body 求值都全表逐行同
    /// 步重算行高，未被文本备忘覆盖的 facet（表格
    /// 逐格自然宽/工具卡详情字段/审批卡逐项/文件
    /// 牌名/交付卡）走真实 TextKit 量测——长会话滚
    /// 动卡顿的实测主因（定因见 hotfix-05070-
    /// diagnosis 题 3）。本层在行入口加整行备忘：
    /// 键＝行修订摘要（ChatNativeRowRevision 结构
    /// 化派生，与重配判据同源）＋环境指纹（宽/字
    /// 阶/粗体/缩放/智能体名）＋facet 状态摘要（修
    /// 订之外的高度输入逐项折入：账本展开覆盖与
    /// 审批详情四态、宿主审批锚态/备注/裁决中、交
    /// 付 meta 与封面缓存态、文件存在性与元数据、
    /// 本地图解码态、回响时刻的日界），跨 body 求
    /// 值留存（静态缓存），O(1) 命中即整行跳过。
    /// 根治（量测异步预排版）随根治版，本层只做
    /// interim 减负、公式本体一字不动
    /// nonisolated(unsafe)：同 textCache 注
    private nonisolated(unsafe) static let rowCache:
        NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1024
        return cache
    }()

    /// 整行实算普查计数（测试读口，与 §329 布局
    /// 匣计数口同式：生产路径只多一次计数、无行
    /// 为影响）：备忘未命中而真算一行的次数——滚
    /// 动稳态下同修订同环境的行入口应全命中、本
    /// 计数不涨
    /// 计数盒（§331）：量测台后台队列也会触发
    /// 实算、裸 Int 静态量不再并发安全——锁盒承
    /// 载（与 OneDayCore ParseMemoBox 同式）
    private static let rowComputationBox =
        LockedRowComputationCounter()

    static var rowComputationCount: Int {
        rowComputationBox.read()
    }

    static func resetRowComputationCount() {
        rowComputationBox.reset()
    }

    /// 环境指纹：合成器构造口径中影响高的全体
    /// （宽经 LayoutProductKey 量化、与文本备忘
    /// 同口径）
    private var environmentFingerprint: String {
        "w\(LayoutProductKey.quantizedWidth(Double(contentWidth)))"
            + "|aw\(LayoutProductKey.quantizedWidth(Double(assistantTextWidth)))"
            + "|\(sizeCategory.rawValue)"
            + "|\(boldText ? "b" : "r")"
            + "|s\(displayScale)"
            + "|n\(LayoutProductKey.fnv1a(agentDisplayName))"
    }

    private func rowMemo(
        _ key: String, _ compute: () -> CGFloat
    ) -> CGFloat {
        let nsKey = key as NSString
        if let hit = Self.rowCache.object(forKey: nsKey) {
            return CGFloat(hit.doubleValue)
        }
        Self.rowComputationBox.increment()
        let value = compute()
        Self.rowCache.setObject(
            NSNumber(value: Double(value)), forKey: nsKey
        )
        return value
    }

    /// 整行备忘缓存口（§331）：同步路径（rowMemo）
    /// 与量测台回填共用同一缓存层——命中判定与落
    /// 写只此一处，两路不会各存一份。nonisolated：
    /// 量测台在后台队列回填（NSCache 本身线程安全）
    nonisolated static func cachedRowHeight(
        forKey key: String
    ) -> CGFloat? {
        rowCache.object(forKey: key as NSString)
            .map { CGFloat($0.doubleValue) }
    }

    nonisolated static func storeRowHeight(
        _ height: CGFloat, forKey key: String
    ) {
        rowCache.setObject(
            NSNumber(value: Double(height)),
            forKey: key as NSString
        )
    }

    // MARK: - 量测工单组装（§331 适配器）

    /// 条目行量测工单：主线程快照 facet＋条目，
    /// 工单在量测台后台队列以同形核心量测——与
    /// 同步路径 entryHeightWithFacets 逐值同高
    /// （对拍测试钉住）
    @MainActor
    func makeEntryMeasureJob(
        for entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false,
        memoKey: String, rowKey: String
    ) -> ChatNativeRowMeasureJob {
        let facets: ChatNativeRowFacets
        if let ledger, let hubStore {
            facets = ChatNativeRowFacetSnapshotter
                .entryFacets(
                    for: entry, ledger: ledger,
                    hubStore: hubStore
                )
        } else {
            facets = ChatNativeRowFacets()
        }
        let snapshot = ChatEntryHeightSnapshot(entry)
        return makeJob(
            memoKey: memoKey, rowKey: rowKey,
            facets: facets
        ) {
            $0.entryHeightCore(
                snapshot, dividerText: dividerText,
                showsUnreadDivider: showsUnreadDivider
            )
        }
    }

    /// 工具组量测工单（同形）
    @MainActor
    func makeToolGroupMeasureJob(
        cards: [ToolCard], groupKey: String,
        memoKey: String, rowKey: String
    ) -> ChatNativeRowMeasureJob {
        let facets: ChatNativeRowFacets
        if let ledger {
            facets = ChatNativeRowFacetSnapshotter
                .groupFacets(
                    cards: cards, groupKey: groupKey,
                    ledger: ledger
                )
        } else {
            facets = ChatNativeRowFacets()
        }
        return makeJob(
            memoKey: memoKey, rowKey: rowKey,
            facets: facets
        ) {
            $0.toolGroupHeightUncached(
                cards: cards, groupKey: groupKey
            )
        }
    }

    /// 审批区量测工单（同形）
    @MainActor
    func makeZoneMeasureJob(
        memoKey: String, rowKey: String
    ) -> ChatNativeRowMeasureJob {
        let facets: ChatNativeRowFacets
        if let ledger, let hubStore {
            facets = ChatNativeRowFacetSnapshotter
                .zoneFacets(
                    ledger: ledger, hubStore: hubStore
                )
        } else {
            facets = ChatNativeRowFacets()
        }
        return makeJob(
            memoKey: memoKey, rowKey: rowKey,
            facets: facets
        ) {
            $0.approvalZoneHeightUncached()
        }
    }

    /// 回告卡量测工单（同形；卡面是纯值输入、无
    /// facet）
    @MainActor
    func makeReportMeasureJob(
        _ item: OverviewNotification,
        memoKey: String, rowKey: String
    ) -> ChatNativeRowMeasureJob {
        makeJob(memoKey: memoKey, rowKey: rowKey) {
            $0.reportCardHeightUncached(item)
        }
    }

    /// 工单骨架：环境按本适配器原值带走，后台以
    /// 量测台形态（facets 唯一输入）重建核心执行
    /// 核心闭包——工单内容自此不可变
    @MainActor
    private func makeJob(
        memoKey: String, rowKey: String,
        facets: ChatNativeRowFacets =
            ChatNativeRowFacets(),
        core: @escaping (
            ChatNativeRowHeightComposer
        ) -> CGFloat
    ) -> ChatNativeRowMeasureJob {
        let screenWidth = self.screenWidth
        let horizontalPadding = self.horizontalPadding
        let sizeCategory = self.sizeCategory
        let boldText = self.boldText
        let displayScale = self.displayScale
        let agentDisplayName = self.agentDisplayName
        let emptyStateAvatarSize =
            self.emptyStateAvatarSize
        return ChatNativeRowMeasureJob(
            memoKey: memoKey, rowKey: rowKey
        ) {
            let composer = ChatNativeRowHeightComposer(
                screenWidth: screenWidth,
                horizontalPadding: horizontalPadding,
                sizeCategory: sizeCategory,
                boldText: boldText,
                displayScale: displayScale,
                agentDisplayName: agentDisplayName,
                emptyStateAvatarSize:
                    emptyStateAvatarSize,
                facets: facets
            )
            return core(composer)
        }
    }

    /// 修订摘要：ChatNativeRowRevision 的 parts
    /// 逐项 FNV-1a 折算（值清单→定长摘要；比较口
    /// 径与修订的 Equatable 逐值比较等价——摘要
    /// 只作备忘键、碰撞概率可忽略且碰撞后果仅是
    /// 一行高取错值，与文本备忘的 fnv 键同险同级）
    private static func revisionDigest(
        _ revision: ChatNativeRowRevision
    ) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ value: UInt64) {
            hash ^= value
            hash &*= 0x0000_0100_0000_01b3
        }
        for part in revision.parts {
            switch part {
            case .text(let string):
                mix(0x1)
                mix(LayoutProductKey.fnv1a(string))
            case .data(let data):
                mix(0x2)
                mix(fnv1a(data))
            case .flag(let flag):
                mix(flag ? 0x31 : 0x30)
            case .count(let count):
                mix(UInt64(bitPattern: Int64(count)))
            case .real(let real):
                mix(real.bitPattern)
            }
        }
        return "\(hash)"
    }

    private static func fnv1a(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// 工具卡结构化摘要（§331 R10 修）：逐字
    /// 段入修订摘要——原 JSON 编码摘要与 §325
    /// 结构化派生双轨并存、且实测同卡同组键二
    /// 算未命中（对照：全手写摘要的条目键跨趟
    /// 稳定），统一废止 JSON 口；字段集＝
    /// ToolCard 全字段、不漏一项
    private static func cardDigest(
        _ card: ToolCard
    ) -> String {
        var revision = ChatNativeRowRevision()
        revision.addText(card.id)
        revision.addText(card.toolName)
        revision.addText(card.category.rawValue)
        revision.addText(card.title)
        revision.addText(card.summary)
        revision.addText(card.result)
        revision.addFlag(card.resultFailed)
        revision.addText(card.arguments)
        return revisionDigest(revision)
    }

    /// 回告卡结构化摘要（同 cardDigest 口径）：
    /// 字段集＝OverviewNotification 全字段
    private static func reportDigest(
        _ item: OverviewNotification
    ) -> String {
        var revision = ChatNativeRowRevision()
        revision.addText(item.id)
        revision.addText(item.kind)
        revision.addText(item.title)
        revision.addText(item.body)
        revision.addText(item.createdAt)
        revision.addFlag(item.read)
        revision.addText(item.refId)
        revision.addText(item.changeId)
        return revisionDigest(revision)
    }

    private static func boolDigest(
        _ value: Bool?
    ) -> String {
        value.map { $0 ? "1" : "0" } ?? "-"
    }

    // MARK: - facet 访问器（§331 核心唯一外部读口）

    /// 展开覆盖：适配器形态读活账本、量测台形态
    /// 读快照——核心只经本口，不许直碰账本/宿主/
    /// 各 Store（后台队列上无活源可碰）
    private func facetExpansionOverride(
        for key: String
    ) -> Bool? {
        if let ledger {
            // 活读支仅适配器形态可达（恒主线程）；
            // 量测台形态 ledger 恒 nil 不可达——
            // assumeIsolated 前提由构造方式保证
            return MainActor.assumeIsolated {
                ledger.expansionOverride(for: key)
            }
        }
        return facets.expansionOverrides[key]
    }

    private func facetApprovalDetail(
        for recordID: String
    ) -> ApprovalDetailState {
        if let ledger {
            return MainActor.assumeIsolated {
                ledger.approvalDetail(for: recordID)
            }
        }
        return facets.approvalDetails[recordID]
            ?? ApprovalDetailState()
    }

    private func facetAnchorState(
        for recordID: String
    ) -> ApprovalAnchor.RowState {
        if let hubStore {
            return MainActor.assumeIsolated {
                hubStore.anchorRowState(
                    recordID: recordID
                )
            }
        }
        return facets.anchorStates[recordID] ?? .loading
    }

    private func facetCardNote(
        for recordID: String
    ) -> String? {
        if let hubStore {
            return MainActor.assumeIsolated {
                hubStore.cardNotes[recordID]
            }
        }
        return facets.cardNotes[recordID]
    }

    private func facetIsDeciding(
        _ recordID: String
    ) -> Bool {
        if let hubStore {
            return MainActor.assumeIsolated {
                hubStore.decidingIDs
                    .contains(recordID)
            }
        }
        return facets.decidingIDs.contains(recordID)
    }

    private func facetFileExistence(
        _ path: String
    ) -> FileMetadataStore.Existence? {
        if ledger != nil {
            return MainActor.assumeIsolated {
                FileMetadataStore.shared
                    .existence(for: path)
            }
        }
        return facets.fileExistences[path]
    }

    private func facetFileSize(
        _ path: String
    ) -> Int64? {
        if ledger != nil {
            return MainActor.assumeIsolated {
                FileMetadataStore.shared
                    .metadata(for: path)?.size
            }
        }
        return facets.fileSizes[path]
    }

    private func facetDeliveryMeta(
        _ id: String
    ) -> DeliveryStore.MetaResult? {
        if ledger != nil {
            return MainActor.assumeIsolated {
                DeliveryStore.shared
                    .metaResult(for: id)
            }
        }
        return facets.deliveryMetas[id]
    }

    /// 封面形态：活读形态按现行公式现算（登记快
    /// 照 cover ∨ 封面图缓存 ∨ 缩略图缓存）、快
    /// 照形态读快照点同公式的定格值
    private func facetDeliveryCoverForm(
        _ meta: BridgeDelivery
    ) -> Bool {
        if ledger != nil {
            let synthetic = WorkspaceFileEntry(
                name: meta.name, path: meta.path,
                isDirectory: false, size: meta.size,
                mtime: nil, mimeType: meta.mime
            )
            return MainActor.assumeIsolated {
                meta.cover.cover
                    || DeliveryStore.shared
                        .hasCachedImage(
                            id: meta.id, variant: .cover
                        )
                    || FileThumbnailStore.shared
                        .hasCachedThumbnail(
                            for: synthetic,
                            targetPixelSize: 720
                        )
            }
        }
        return facets.deliveryCoverForms[meta.id]
            ?? false
    }

    private func facetLocalImageDecoded(
        entryID: UUID, index: Int, data: Data
    ) -> Bool {
        if ledger != nil {
            return LocalImageDecodeCache.shared.image(
                entryID: entryID, index: index,
                data: data
            ) != nil
        }
        return facets.localImageDecoded.indices
            .contains(index)
            && facets.localImageDecoded[index]
    }

    /// 审批区遍历集（ready 记录/锚定集/已决行
    /// id）：活读形态读宿主、快照形态读快照
    private func facetZoneInputs()
        -> (records: [WriteGateRecord],
            anchored: Set<String>,
            resolvedLineIDs: [String])?
    {
        if let hubStore {
            return MainActor.assumeIsolated {
                guard case .ready(let records)
                    = hubStore.approvalState
                else { return nil }
                return (
                    records,
                    hubStore.anchoredRecordIDs,
                    hubStore.resolvedLines.map(\.id)
                )
            }
        }
        guard let records = facets.zoneRecords
        else { return nil }
        return (
            records, facets.zoneAnchoredIDs,
            facets.zoneResolvedLineIDs
        )
    }

    /// 审批详情四态摘要（合成读的全体：展开/加载
    /// 态＋详情的注意行/原文失效位/diff 全文＋错
    /// 误文案）
    private func approvalDetailDigest(
        _ recordID: String
    ) -> String {
        let state = facetApprovalDetail(for: recordID)
        var parts = [
            "x\(state.expanded ? "1" : "0")",
            "l\(state.loading ? "1" : "0")",
            "e\(state.error.map { "\(LayoutProductKey.fnv1a($0))" } ?? "-")",
        ]
        if let detail = state.detail {
            var detailParts = detail.review.noteLabels
                .map { "\(LayoutProductKey.fnv1a($0))" }
            detailParts.append(
                "o\(detail.review.requestedOldString != nil ? "1" : "0")"
            )
            detailParts.append(
                "d\(LayoutProductKey.fnv1a(detail.review.displayDiff))"
            )
            parts.append(
                "D\(detailParts.joined(separator: ","))"
            )
        } else {
            parts.append("D-")
        }
        return parts.joined(separator: "|")
    }

    /// 审批记录本体摘要（卡面合成读的全体：问句/
    /// 原因行派生文案＋可裁决/阻断位＋备注＋裁决
    /// 中——记录其余字段不入高）
    private func approvalRecordDigest(
        _ record: WriteGateRecord
    ) -> String {
        "q\(LayoutProductKey.fnv1a(ApprovalCardCopy.question(for: record)))"
            + "|r\(ApprovalCardCopy.reasonLine(for: record).map { "\(LayoutProductKey.fnv1a($0))" } ?? "-")"
            + "|c\(record.canDecide ? "1" : "0")"
            + "|b\(record.isBlocked ? "1" : "0")"
            + "|n\(facetCardNote(for: record.id).map { "\(LayoutProductKey.fnv1a($0))" } ?? "-")"
            + "|d\(facetIsDeciding(record.id) ? "1" : "0")"
    }

    /// 文件状态摘要（牌/图/交付合成读的全体：存
    /// 在性＋元数据大小——牌面副行与菜单在席判定
    /// 的输入）
    private func fileStateDigest(
        _ path: String
    ) -> String {
        let existence = facetFileExistence(path)
        let size = facetFileSize(path)
        return "\(existence)|\(size.map(String.init) ?? "-")"
    }

    /// 交付 meta 摘要（交付合成读的全体：未到/
    /// 查无/已载三态；已载折状态/种类/名/大小＋
    /// 封面三路缓存态）
    private func deliveryMetaDigest(
        _ id: String
    ) -> String {
        switch facetDeliveryMeta(id) {
        case nil:
            return "nil"
        case .notFound:
            return "nf"
        case .loaded(let meta):
            // 封面三路缓存态在高里只以合成形态
            // （coverForm）出现——摘要同口径折合
            // 成形态一位，与核心读点逐值对应
            let coverFlag = facetDeliveryCoverForm(meta)
                ? "1" : "0"
            return "ld\(meta.status)"
                + "|\(meta.kind)"
                + "|\(LayoutProductKey.fnv1a(meta.name))"
                + "|\(String(meta.size))"
                + "|cf\(coverFlag)"
        }
    }

    /// 条目行 facet 状态摘要：修订之外的高度输入
    /// 逐项折入（账本两键/审批锚全态/交付与文件
    /// 状态/本地图解码/回响日界）——摘要的每一项
    /// 都对应 entryHeight 家族的一处外部读，漏折
    /// 一项即旧高残留、与 §325 修订漏折同病，故
    /// 逐项按合成读点对账列全
    private func entryFacetDigest(
        _ entry: ChatEntry
    ) -> String {
        var parts: [String] = []
        parts.append(
            "rx\(Self.boolDigest(facetExpansionOverride(for: ChatRowStateKeys.reasoningEntry(entry.id))))"
        )
        parts.append(
            "tx\(Self.boolDigest(facetExpansionOverride(for: ChatRowStateKeys.toolEntry(entry.id))))"
        )
        if entry.traceKey != nil {
            // 回响时刻文案随日界变宽（今天只时刻、
            // 跨日带月日）：折当日判定
            parts.append(
                "td\(Calendar.current.isDateInToday(entry.createdAt) ? "1" : "0")"
            )
        }
        if entry.approvalKey != nil {
            let recordID = ApprovalAnchor.recordID(
                fromKey: entry.approvalKey ?? ""
            ) ?? ""
            parts.append(
                "apd\(approvalDetailDigest(recordID))"
            )
            switch facetAnchorState(
                for: recordID
            ) {
            case .pending(let record):
                parts.append(
                    "app\(approvalRecordDigest(record))"
                )
            case .decided:
                parts.append("apDecided")
            case .stale:
                parts.append("apStale")
            case .loading:
                parts.append("apLoading")
            }
        }
        if entry.role == "user" {
            if !entry.allImageDatas.isEmpty {
                // 本地图行：任一解出即出卡（与合成
                // 同判）
                let decoded = entry.allImageDatas
                    .indices.contains { index in
                        facetLocalImageDecoded(
                            entryID: entry.id,
                            index: index,
                            data: entry.allImageDatas[
                                index
                            ]
                        )
                    }
                parts.append("li\(decoded ? "1" : "0")")
            }
            for rawPath in entry.remoteFilePaths {
                let split = FileLineAnchor.split(
                    pathWithAnchor: rawPath
                )
                parts.append(
                    "rf\(LayoutProductKey.fnv1a(split.path))=\(fileStateDigest(split.path))"
                )
            }
        } else {
            // 助手行：派生扫描与合成同源（EntryScan-
            // Memo 备忘在席、此处只多一趟缓存读）；
            // 存在性/交付态逐路径/逐 id 折入——disp-
            // layText 的剥离集与各图/牌/交付槽高都
            // 由这批状态决定
            let scans = EntryScanMemo.scans(
                entryID: entry.id,
                content: entry.content,
                remoteImagePaths: entry.remoteImagePaths
            )
            for deliveryID in scans.delivery.deliveryIDs {
                parts.append(
                    "dl\(deliveryID)=\(deliveryMetaDigest(deliveryID))"
                )
            }
            // §333（待办 143 根治）：路径并集改走
            // EntryScanMemo.facetPaths 备忘（五源
            // 并集与旧现算逐字相等）——旧形态每趟
            // 键组装对正文重跑 wholeMessagePath＋
            // 组合排除口径的 detectStandalone-
            // Anchored 全文扫，长会话每趟 body 求
            // 值全表重付，是 §331 量测台落成后热
            // 路径上残余的主线程同步全扫；现第二
            // 趟起只剩备忘读＋逐路径状态摘要（状
            // 态本身仍逐趟活读、翻转即键变，失效
            // 语义不变）
            for path in EntryScanMemo.facetPaths(
                entryID: entry.id,
                content: entry.content,
                remoteImagePaths: entry.remoteImagePaths
            ) {
                parts.append(
                    "fx\(LayoutProductKey.fnv1a(path))=\(fileStateDigest(path))"
                )
            }
        }
        return parts.joined(separator: "|")
    }

    // MARK: - Markdown 高（助手正文/直播正文共用）

    /// MarkdownText 本体高：段序列与呈现同一装配
    /// （MarkdownMessageAssembler.segments），段
    /// 间 spacingSM——公式逐段见各分支注
    func markdownHeight(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return memoized("md", text, assistantTextWidth) {
            markdownHeightUncached(text)
        }
    }

    private func markdownHeightUncached(
        _ text: String
    ) -> CGFloat {
        let segments = MarkdownMessageAssembler
            .segments(for: text)
        guard !segments.isEmpty else { return 0 }
        var total: CGFloat = 0
        for segment in segments {
            total += segmentHeight(segment)
        }
        total += OneDayMetrics.spacingSM
            * CGFloat(segments.count - 1)
        return total
    }

    private func segmentHeight(
        _ segment: MarkdownMessageSegment
    ) -> CGFloat {
        let width = assistantTextWidth
        switch segment {
        case .prose(let paragraphs):
            // proseView：合并散文段单文本视图（拼
            // 装与产物层同源）
            return assembledHeight(
                paragraphs: MarkdownText.proseParagraphs(
                    paragraphs
                ),
                foreground: Palette.bodyInk,
                width: width
            )
        case .quote(let lines):
            // blockquoteView：竖条 3＋spacingS 后
            // 文本合一（宽折算与产物层 builder 同值）
            return assembledHeight(
                paragraphs: MarkdownText.quoteParagraphs(
                    lines
                ),
                foreground: Palette.inkSecondaryOnFill,
                width: width - (3 + OneDayMetrics.spacingS)
            )
        case .code(let code, _):
            // codeView：内距 spacingSM＋头行（复制
            // 钮命中域 44 恒在席）＋spacingXS＋代码
            // 文本（横滚不折行；呈现是 SwiftUI
            // Text——量测高只借行数、实高走
            // swiftTextHeight，§329 续修校准）
            let codeHeight = swiftTextHeight(
                measured: SelectableTextRepresentable
                    .referenceHeight(
                        attributed: NSAttributedString(
                            string: code,
                            attributes: [
                                .font: monospacedFont(
                                    .footnote
                                ),
                            ]
                        ),
                        width: nil
                    ),
                stepStyle: .footnote,
                firstLineFont: monospacedFont(.footnote)
            )
            return OneDayMetrics.spacingSM * 2
                + OneDayMetrics.minTapTarget
                + OneDayMetrics.spacingXS
                + codeHeight
        case .table(let header, _, let rows):
            return tableHeight(
                header: header, rows: rows, width: width
            )
        case .taskList(let items):
            // listView：项间 spacingXS；项＝标记列
            // 22＋spacingS＋正文（level 逐级再缩
            // spacingM），正文走拼装量测
            var total: CGFloat = 0
            for item in items {
                let textWidth = width
                    - 22 - OneDayMetrics.spacingS
                    - CGFloat(item.level)
                        * OneDayMetrics.spacingM
                total += assembledHeight(
                    paragraphs: [.markdown(item.text)],
                    foreground: Palette.bodyInk,
                    width: textWidth
                )
            }
            if items.count > 1 {
                total += OneDayMetrics.spacingXS
                    * CGFloat(items.count - 1)
            }
            return total
        case .divider:
            return 1 / max(displayScale, 1)
        }
    }

    /// 表格高（MarkdownTablePresentation 分流与
    /// 呈现同源：≤4 列 Grid、>4 列降级列表）
    private func tableHeight(
        header: [String], rows: [[String]],
        width: CGFloat
    ) -> CGFloat {
        if MarkdownTablePresentation.mode(
            columnCount: header.count
        ) == .list {
            return tableListHeight(
                header: header, rows: rows, width: width
            )
        }
        // Grid（§329 续修校准实证）：横滚 Scroll-
        // View＋Grid 组合下，格上的 frame(max-
        // ColumnWidth) 不压缩列宽——列宽按各格自
        // 然宽取列最大值、每格恒单行（拟合直测：
        // 备注列自然宽 270 整行不折、整表高与
        // 「全行单行」模型逐值一致）。行高＝
        // SwiftUI .callout 单行实高（表头 bold
        // 同值）；行间 verticalSpacing spacingXS；
        // 表头行与数据行之间 GroupDivider 一行。
        // 注：§149「封顶折行」设计意图在此组合下
        // 未达成、属呈现层既有行为，本式只对齐
        // 量测、呈现改判归主线
        let rowLineHeight = swiftLineHeight(
            plainFont(.callout)
        )
        let dividerHeight = 1 / max(displayScale, 1)
        let gridRows = rows.count + 2
        return rowLineHeight * CGFloat(rows.count + 1)
            + dividerHeight
            + OneDayMetrics.spacingXS
                * CGFloat(gridRows - 1)
    }

    /// 表格降级列表高（>4 列）：逐数据行成组（组
    /// 间 GroupDivider＋spacingSM 节奏），组内逐
    /// 列一行「标签 footnote semibold＋值 callout」
    /// （HStack firstTextBaseline、spacingS）
    private func tableListHeight(
        header: [String], rows: [[String]],
        width: CGFloat
    ) -> CGFloat {
        let entries = MarkdownTablePresentation
            .listEntries(header: header, rows: rows)
        let dividerHeight = 1 / max(displayScale, 1)
        var total: CGFloat = 0
        for (rowIndex, row) in entries.enumerated() {
            if rowIndex > 0 {
                total += dividerHeight
                    + OneDayMetrics.spacingSM
            }
            var rowTotal: CGFloat = 0
            for entry in row {
                let labelWidth = naturalWidth(
                    entry.label,
                    font: weightedFont(.footnote, .semibold)
                )
                let valueWidth = max(
                    width - labelWidth
                        - OneDayMetrics.spacingS,
                    20
                )
                let valueHeight = tableCellTextHeight(
                    entry.value, width: valueWidth
                )
                rowTotal += max(
                    swiftLineHeight(
                        weightedFont(.footnote, .semibold)
                    ),
                    swiftTextHeight(
                        measured: valueHeight,
                        stepStyle: .callout,
                        firstLineFont: plainFont(.callout)
                    )
                )
            }
            if row.count > 1 {
                rowTotal += OneDayMetrics.spacingXS
                    * CGFloat(row.count - 1)
            }
            total += rowTotal
            if rowIndex > 0 {
                total += OneDayMetrics.spacingSM
            }
        }
        return total
    }

    /// 表格格文本拼装（与 MarkdownText.inline 同
    /// 路：系统行内解析＋strong 段映射 strongFont
    /// ——格内字阶 .callout、strong＝.callout bold；
    /// 删除线段不影响高、不拼）
    private func tableCellAttributed(
        _ cell: String
    ) -> NSAttributedString {
        let base = plainFont(.callout)
        let bold = weightedFont(.callout, .bold)
        let result = NSMutableAttributedString()
        for segment in MarkdownInline.segments(cell) {
            guard let parsed = try? AttributedString(
                markdown: segment.text,
                options: AttributedString
                    .MarkdownParsingOptions(
                        interpretedSyntax:
                            .inlineOnlyPreservingWhitespace
                    )
            ) else {
                result.append(NSAttributedString(
                    string: segment.text,
                    attributes: [.font: base]
                ))
                continue
            }
            // 系统解析产物逐 run 按 intent 重映射
            // 到 UIKit 字体（strong→bold、其余
            // base），与视图 inlineAttributed 的
            // 映射同口径；run 无 intent 即正文段
            var converted = NSMutableAttributedString()
            for run in parsed.runs {
                let isStrong = run
                    .inlinePresentationIntent?
                    .contains(.stronglyEmphasized)
                    ?? false
                converted.append(NSAttributedString(
                    string: String(
                        parsed[run.range].characters
                    ),
                    attributes: [
                        .font: isStrong ? bold : base,
                    ]
                ))
            }
            if converted.length == 0 {
                converted = NSMutableAttributedString(
                    string: segment.text,
                    attributes: [.font: base]
                )
            }
            result.append(converted)
        }
        if result.length == 0 {
            return NSAttributedString(
                string: cell, attributes: [.font: base]
            )
        }
        return result
    }

    private func tableCellTextHeight(
        _ cell: String, width: CGFloat
    ) -> CGFloat {
        SelectableTextRepresentable.referenceHeight(
            attributed: tableCellAttributed(cell),
            width: width
        )
    }

    // MARK: - 文件牌族

    /// FileChip 本体高（RichContentViews 几何）：
    /// 卡＝纵内距 10×2＋max(图标盒 40, 名列高,
    /// 菜单命中域 44)；名列＝名（.body semibold
    /// ≤2 行，宽＝牌宽−左距 12−图标 40−间距 12
    /// −菜单 44）＋spacingXS＋副行 caption 一行。
    /// notice 反馈行对合成不可见（§329 残留 ⑴、
    /// 溢出＜行间距、不入账）
    func fileChipHeight(
        path: String, width: CGFloat
    ) -> CGFloat {
        let name = (path as NSString).lastPathComponent
        let synthetic = WorkspaceFileEntry(
            name: name, path: path, isDirectory: false,
            size: facetFileSize(path),
            mtime: nil, mimeType: nil
        )
        let hasMenu = !FileActionPolicy.menuActions(
            for: synthetic
        ).isEmpty
        let nameWidth = width
            - OneDayMetrics.spacingSM - 40
            - OneDayMetrics.spacingSM
            - (hasMenu ? OneDayMetrics.minTapTarget : 0)
        let nameHeight = weightedHeight(
            name, .body, .semibold,
            width: nameWidth, lineLimit: 2
        )
        let columnHeight = nameHeight
            + OneDayMetrics.spacingXS + spec(.caption1)
        return 20 + max(
            40, columnHeight,
            hasMenu ? OneDayMetrics.minTapTarget : 0
        )
    }

    /// AssistantFileChip：确证存在出牌、否则路径
    /// 原文 .callout 一行（可折行）——与视图存在
    /// 性门同判据（FileMetadataStore 同源读）。
    /// 台账 185 占位口径：存在性未定（unverified/
    /// 未读到）时先按牌高占位——旧口径未定即按文
    /// 本高、确证后翻牌高，整行凭空换高（与图片
    /// 槽 0↔190 同源病）；确证 missing 才落文本高
    func assistantFileChipHeight(
        path: String
    ) -> CGFloat {
        if facetFileExistence(path) == .missing {
            return plainHeight(
                path, .callout, width: contentWidth
            )
        }
        return fileChipHeight(
            path: path, width: contentWidth
        )
    }

    /// BarePathFileCard：确证不在出失效卡（无菜
    /// 单、几何与 FileChip 同族），其余走 FileChip
    func barePathFileCardHeight(
        path: String
    ) -> CGFloat {
        guard facetFileExistence(path) == .missing
        else {
            return fileChipHeight(
                path: path, width: contentWidth
            )
        }
        let name = (path as NSString).lastPathComponent
        let nameWidth = contentWidth
            - OneDayMetrics.spacingSM - 40
            - OneDayMetrics.spacingSM
        let nameHeight = weightedHeight(
            name, .body, .semibold,
            width: nameWidth, lineLimit: 2
        )
        let columnHeight = nameHeight
            + OneDayMetrics.spacingXS + spec(.caption1)
        return 20 + max(40, columnHeight)
    }

    // MARK: - 交付项

    /// AssistantDeliveryItem 高（DeliveryViews 状
    /// 态机同判）：meta 未到＝先按 §130 定高卡 190
    /// 占位（台账 185：旧口径 0 与 meta 到达后的
    /// 高翻转、整行凭空长高；占位后翻转方向只剩
    /// 「确证为小件时塌一次」）、查无＝标记原文
    /// .callout、gone＝一行 .callout、image＝§130
    /// 定高卡 190、其余＝封面卡
    func deliveryItemHeight(id: String) -> CGFloat {
        switch facetDeliveryMeta(id) {
        case nil:
            return ChatImageSizing.cardHeight
        case .notFound:
            return plainHeight(
                DeliveryMarker.markerText(for: id),
                .callout, width: contentWidth
            )
        case .loaded(let meta):
            if meta.status == .gone {
                return plainHeight(
                    L10n.format(
                        "%@（文件已删除）", meta.name
                    ),
                    .callout, width: contentWidth
                )
            }
            if meta.kind == "image" {
                return ChatImageSizing.cardHeight
            }
            return deliveryFileCardHeight(meta)
        }
    }

    /// DeliveryFileCard 高：封面区 148（封面形态
    /// 时）＋名列行（纵内距 cardInnerGap×2＋max(
    /// 图标盒 40〔无封面时〕, 名列高)）。封面形态
    /// 判定（§329）：登记快照 cover 在册 ∨ 快照
    /// 字节已缓存 ∨ §32 缩略图已缓存——三路皆空
    /// 时按无封面合成、管线首载到达后靠重渲回填
    func deliveryFileCardHeight(
        _ meta: BridgeDelivery
    ) -> CGFloat {
        let coverForm = facetDeliveryCoverForm(meta)
        let nameWidth = contentWidth
            - OneDayMetrics.spacingSM
            - (coverForm
                ? 0
                : 40 + OneDayMetrics.spacingSM)
        let nameHeight = weightedHeight(
            meta.name, .body, .semibold,
            width: nameWidth, lineLimit: 2
        )
        let columnHeight = nameHeight
            + OneDayMetrics.spacingXS + spec(.caption1)
        let rowHeight = max(
            coverForm ? 0 : 40, columnHeight
        )
        return (coverForm ? 148 : 0)
            + OneDayMetrics.cardInnerGap * 2 + rowHeight
    }

    // MARK: - 思考块

    /// ReasoningBlock 高：头行 minTapTarget 44 恒
    /// 在席；展开且正文非空时＋spacingXS＋正文区
    /// （限高 maxBodyHeight、正文宽＝内容宽−左距
    /// bubblePaddingH−竖线 2−spacingS）
    func reasoningHeight(
        text: String, expanded: Bool
    ) -> CGFloat {
        var total = OneDayMetrics.minTapTarget
        if expanded, !text.isEmpty {
            let bodyWidth = contentWidth
                - OneDayMetrics.bubblePaddingH
                - 2 - OneDayMetrics.spacingS
            let bodyHeight = min(
                swiftTextHeight(
                    measured: plainHeight(
                        text, .footnote, width: bodyWidth
                    ),
                    stepStyle: .footnote,
                    firstLineFont: plainFont(.footnote)
                ),
                CGFloat(ReasoningPresentation.maxBodyHeight)
            )
            total += OneDayMetrics.spacingXS + bodyHeight
        }
        return total
    }

    // MARK: - 工具卡族

    /// 工具卡副行（ToolCardView.subtitle 同逻辑
    /// 复刻：浏览器页面行→摘要→状态兜底，Core 单
    /// 源函数同读）
    private func toolCardSubtitle(
        _ card: ToolCard
    ) -> String {
        if card.category == .browser,
           let result = card.result,
           result.hasPrefix("Page: "),
           let open = result.firstIndex(of: "("),
           let close = result.firstIndex(of: ")"),
           open < close {
            let url = String(
                result[result.index(after: open)..<close]
            )
            if url.hasPrefix("http") { return url }
        }
        if !card.summary.isEmpty { return card.summary }
        switch ToolCardPresentation.state(of: card) {
        case .succeeded:
            return ToolResultUnwrap.isMeaningless(
                card.result ?? ""
            ) ? "（无输出）" : ""
        case .failed:
            return ToolCardPresentation
                .firstMeaningfulLine(of: card.result)
                ?? ""
        case .running:
            return ""
        }
    }

    /// 卡行本体高：max(图标盒 36, 标题行＋副行)；
    /// 标题/副行均 SwiftUI Text 单行——走实高
    /// （§329 续修校准：标题 .subheadline
    /// medium 实高 18、副行 .caption 实高
    /// 14.33，spec 口径各虚高 2/1.67）
    private func toolCardRowHeight(
        _ card: ToolCard
    ) -> CGFloat {
        var textHeight = swiftLineHeight(
            weightedFont(.subheadline, .medium)
        )
        if !toolCardSubtitle(card).isEmpty {
            textHeight += OneDayMetrics.spacingMicro
                + swiftLineHeight(plainFont(.caption1))
        }
        return max(36, textHeight)
    }

    /// 详情字段高：标签 caption 单行实高＋
    /// spacingMicro＋正文（caption SwiftUI
    /// Text 多行实高，等宽档走等宽量测借行数）
    private func toolDetailFieldHeight(
        text: String, monospaced: Bool, width: CGFloat
    ) -> CGFloat {
        let measured = monospaced
            ? measurePlain(
                text,
                font: monospacedFont(.caption1),
                width: width
            )
            : plainHeight(text, .caption1, width: width)
        let textHeight = swiftTextHeight(
            measured: measured,
            stepStyle: .caption1,
            firstLineFont: monospaced
                ? monospacedFont(.caption1)
                : plainFont(.caption1)
        )
        return swiftLineHeight(plainFont(.caption1))
            + OneDayMetrics.spacingMicro + textHeight
    }

    /// 详情区高（detailBody：参数字段→结果字段
    /// →工具名行，VStack spacingS）
    private func toolCardDetailHeight(
        _ card: ToolCard, width: CGFloat
    ) -> CGFloat {
        var fields: [CGFloat] = []
        if let arguments = card.arguments,
           !arguments.isEmpty {
            fields.append(toolDetailFieldHeight(
                text: Self.prettyArguments(arguments),
                monospaced: true, width: width
            ))
        } else if !card.summary.isEmpty {
            fields.append(toolDetailFieldHeight(
                text: card.summary,
                monospaced: false, width: width
            ))
        }
        let resultText = card.result.map {
            ToolResultUnwrap.isMeaningless($0)
                ? "（无输出）" : $0
        } ?? "进行中…"
        fields.append(toolDetailFieldHeight(
            text: resultText,
            monospaced: card.category == .terminal,
            width: width
        ))
        var total = fields.reduce(0, +)
            + swiftLineHeight(plainFont(.caption1))
        total += OneDayMetrics.spacingS
            * CGFloat(fields.count)
        return total
    }

    /// 参数详情排版（ToolCardView.prettyArguments
    /// 同式复刻：JSON 美化、解不出原文）
    private static func prettyArguments(
        _ raw: String
    ) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization
                .jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys,
                          .withoutEscapingSlashes]
              ),
              let text = String(
                data: pretty, encoding: .utf8
              )
        else { return raw }
        return text
    }

    /// ToolCardView 高（§330 备忘包装）：键＝卡
    /// 本体编码摘要＋宽＋展开/素面位＋环境指纹
    /// （合成只读卡本体与入参、无外部状态）
    func toolCardHeight(
        card: ToolCard, width: CGFloat,
        expanded: Bool, plain: Bool
    ) -> CGFloat {
        let key = "tc|\(Self.cardDigest(card))"
            + "|\(LayoutProductKey.quantizedWidth(Double(width)))"
            + "|\(expanded ? "1" : "0")\(plain ? "1" : "0")"
            + "|\(environmentFingerprint)"
        return rowMemo(key) {
            toolCardHeightUncached(
                card: card, width: width,
                expanded: expanded, plain: plain
            )
        }
    }

    /// ToolCardView 高：plain（组内嵌）无自家内
    /// 距、独立卡内距 15；展开＋spacingS＋发丝线
    /// 1＋spacingS＋详情区。
    /// 活动线分支（2026-11-20 结构归位·对话页，
    /// 与 ToolCardView.usesLineForm 同口径）：独
    /// 立落定卡默认压线——头行恒 minTapTarget
    /// （视觉一行、命中 44，与思考头行同式）；展
    /// 开＋spacingS＋发丝线 1＋spacingS＋详情区
    /// （详情宽＝全宽−左距 bubblePaddingH，无卡
    /// 面内距）
    func toolCardHeightUncached(
        card: ToolCard, width: CGFloat,
        expanded: Bool, plain: Bool
    ) -> CGFloat {
        if !plain,
           ToolCardPresentation.state(of: card) != .running {
            var total = OneDayMetrics.minTapTarget
            if expanded {
                total += OneDayMetrics.spacingS * 2 + 1
                total += toolCardDetailHeight(
                    card,
                    width: width - OneDayMetrics.bubblePaddingH
                )
            }
            return total
        }
        var total = toolCardRowHeight(card)
        if !plain { total += 30 }
        if expanded {
            total += OneDayMetrics.spacingS * 2 + 1
            total += toolCardDetailHeight(
                card, width: width - (plain ? 0 : 30)
            )
        }
        return total
    }

    /// ToolCardGroupView 高（§330 备忘包装＋
    /// §331 适配器）：键见 toolGroupMemoKey
    @MainActor
    func toolGroupHeight(
        cards: [ToolCard], groupKey: String
    ) -> CGFloat {
        rowMemo(
            toolGroupMemoKey(
                cards: cards, groupKey: groupKey
            )
        ) {
            toolGroupHeightWithFacets(
                cards: cards, groupKey: groupKey
            )
        }
    }

    /// 工具组备忘键（§330/§331 共用单点）：组键
    /// ＋逐卡编码摘要＋组/逐卡展开覆盖＋环境指纹
    @MainActor
    func toolGroupMemoKey(
        cards: [ToolCard], groupKey: String
    ) -> String {
        var keyParts = ["tg|\(groupKey)"]
        for card in cards {
            keyParts.append(Self.cardDigest(card))
        }
        keyParts.append(
            "g\(Self.boolDigest(ledger?.expansionOverride(for: groupKey)))"
        )
        for card in cards {
            let cardKey = ChatRowStateKeys
                .toolGroupCard(
                    groupKey: groupKey, cardID: card.id
                )
            keyParts.append(
                "c\(Self.boolDigest(ledger?.expansionOverride(for: cardKey)))"
            )
        }
        keyParts.append(environmentFingerprint)
        return keyParts.joined(separator: "|")
    }

    /// 工具组适配器一趟（§331）：快照组展开覆
    /// 盖后交核心（量测工单同形）
    @MainActor
    func toolGroupHeightWithFacets(
        cards: [ToolCard], groupKey: String
    ) -> CGFloat {
        var core = self
        if let ledger {
            core.facets = ChatNativeRowFacetSnapshotter
                .groupFacets(
                    cards: cards, groupKey: groupKey,
                    ledger: ledger
                )
        }
        return core.toolGroupHeightUncached(
            cards: cards, groupKey: groupKey
        )
    }

    /// ToolCardGroupView 高：内距 15＋组头行 36；
    /// 展开＋顶距 spacingS＋逐卡 plain 高＋卡间
    /// 分隔（发丝线 1＋纵内距 spacingS×2）
    func toolGroupHeightUncached(
        cards: [ToolCard], groupKey: String
    ) -> CGFloat {
        var total = 30 + max(
            36,
            swiftLineHeight(
                weightedFont(.subheadline, .medium)
            )
        )
        let groupExpanded = facetExpansionOverride(
            for: groupKey
        ) ?? false
        guard groupExpanded, !cards.isEmpty
        else { return total }
        total += OneDayMetrics.spacingS
        for (index, card) in cards.enumerated() {
            if index > 0 {
                total += 1 + OneDayMetrics.spacingS * 2
            }
            let cardKey = ChatRowStateKeys.toolGroupCard(
                groupKey: groupKey, cardID: card.id
            )
            total += toolCardHeightUncached(
                card: card,
                width: contentWidth - 30,
                expanded: facetExpansionOverride(
                    for: cardKey
                ) ?? false,
                plain: true
            )
        }
        return total
    }

    // MARK: - 引用块族（用户行）

    /// quoteBlock 高：内距 spacingS 全周；左条 2
    /// ＋spacingS＋两行字（名 caption 无截断、摘
    /// 要 caption ≤2 行），名/摘要间 spacingMicro
    private func messageQuoteHeight(
        name: String, summary: String,
        columnWidth: CGFloat,
        nameSingleLine: Bool
    ) -> CGFloat {
        let textWidth = columnWidth
            - OneDayMetrics.spacingS * 2
            - 2 - OneDayMetrics.spacingS
        let nameHeight = nameSingleLine
            ? spec(.caption1)
            : plainHeight(
                name, .caption1, width: textWidth
            )
        let summaryHeight = plainHeight(
            summary, .caption1, width: textWidth,
            lineLimit: 2
        )
        return OneDayMetrics.spacingS * 2
            + nameHeight
            + OneDayMetrics.spacingMicro
            + summaryHeight
    }

    // MARK: - 审批族

    /// 审批卡高（ChatApprovalCard＝卡面 face＋宿
    /// 主内距 spacingM）：face 为 VStack(spacingS)
    /// ——时间行／问句（.headline 折行）／说明行
    /// （单行）／原因行（在席时）／提示行（在席
    /// 时）／详情区（账本四态）／动作区，逐项与
    /// ApprovalCardFace 几何同值
    func approvalCardHeight(
        record: WriteGateRecord, width: CGFloat
    ) -> CGFloat {
        let innerWidth = width
            - OneDayMetrics.spacingM * 2
        var items: [CGFloat] = []
        items.append(spec(.caption1))
        items.append(weightedHeight(
            ApprovalCardCopy.question(for: record),
            .body, .semibold, width: innerWidth
        ))
        items.append(spec(.subheadline))
        if let reason = ApprovalCardCopy.reasonLine(
            for: record
        ) {
            items.append(plainHeight(
                reason, .footnote,
                width: innerWidth - 20
            ))
        }
        if let note = facetCardNote(for: record.id) {
            items.append(plainHeight(
                note, .caption1, width: innerWidth
            ))
        }
        // 详情区：收起＝SmoothExpand 零高一项；展
        // 开按四态分（加载行／内容＋收起行／错误
        // ＋收起行，内容与收起行各带顶距 spacingS
        // 且同为 face 的 VStack 子项）
        let detail = facetApprovalDetail(
            for: record.id
        )
        if !detail.expanded {
            items.append(0)
        } else if detail.loading {
            items.append(max(20, spec(.caption1)))
        } else if let loaded = detail.detail {
            items.append(
                OneDayMetrics.spacingS
                    + reviewContentHeight(
                        detail: loaded, record: record,
                        width: innerWidth
                    )
            )
            items.append(
                OneDayMetrics.spacingS + spec(.subheadline)
            )
        } else if let error = detail.error {
            items.append(plainHeight(
                error, .caption1, width: innerWidth
            ))
            items.append(
                OneDayMetrics.spacingS + spec(.subheadline)
            )
        } else {
            items.append(0)
        }
        // 动作区：提交中＝进度行；可裁决＝钮栈
        // （ApprovalCardSpec 单源）；不可裁决＝说
        // 明 caption 折行
        if facetIsDeciding(record.id) {
            items.append(max(20, spec(.caption1)))
        } else if record.canDecide {
            let actions = ApprovalCardSpec.actionStack(
                canDecide: true, blocked: record.isBlocked
            )
            items.append(
                CGFloat(actions.count)
                    * ApprovalCardSpec.buttonHeight
                    + CGFloat(max(0, actions.count - 1))
                        * ApprovalCardSpec.buttonSpacing
            )
        } else {
            items.append(plainHeight(
                "这类写入暂不支持在 App 内审批，请在 Hermes 中处理",
                .caption1, width: innerWidth
            ))
        }
        var total = items.reduce(0, +)
        total += OneDayMetrics.spacingS
            * CGFloat(max(0, items.count - 1))
        return total + OneDayMetrics.spacingM * 2
    }

    /// 审批详情内容高（ApprovalReviewContent 内
    /// 嵌形态：VStack spacingM——注意行×k／原文
    /// 失效警告（在席时）／diff 等宽 footnote 折
    /// 行／原始信息 DisclosureGroup 收起一行；
    /// DisclosureGroup 展开态不可上提，§329 残
    /// 留 ⑵按收起合成）
    private func reviewContentHeight(
        detail: WriteGateDetail,
        record: WriteGateRecord,
        width: CGFloat
    ) -> CGFloat {
        var items: [CGFloat] = []
        for label in detail.review.noteLabels {
            items.append(plainHeight(
                label, .footnote, width: width - 20
            ))
        }
        if detail.review.requestedOldString != nil {
            items.append(plainHeight(
                "这条修订要改的原文已经不存在，可能基于旧内容，批准前请仔细核对。",
                .footnote, width: width - 20
            ))
        }
        items.append(measurePlain(
            detail.review.displayDiff,
            font: monospacedFont(.footnote),
            width: width
        ))
        items.append(spec(.footnote))
        var total = items.reduce(0, +)
        total += OneDayMetrics.spacingM
            * CGFloat(max(0, items.count - 1))
        return total
    }

    /// 审批锚行高（approvalAnchorRow 四态）：待
    /// 批＝整卡；已决/失效/加载＝内距 spacingS
    /// 纵＋footnote 一行
    func approvalAnchorHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        let recordID = ApprovalAnchor.recordID(
            fromKey: entry.approvalKey ?? ""
        ) ?? ""
        switch facetAnchorState(
            for: recordID
        ) {
        case .pending(let record):
            return approvalCardHeight(
                record: record, width: contentWidth
            )
        case .decided, .stale, .loading:
            return OneDayMetrics.spacingS * 2
                + spec(.footnote)
        }
    }

    /// 审批区行高（§330 备忘包装＋§331 适配
    /// 器）：键见 zoneMemoKey
    @MainActor
    func approvalZoneHeight() -> CGFloat {
        rowMemo(zoneMemoKey()) {
            approvalZoneHeightWithFacets()
        }
    }

    /// 审批区备忘键（§330/§331 共用单点）：区
    /// facet 摘要（ready 态＋未锚定记录的卡面/
    /// 详情摘要＋已决行 id 集）＋环境指纹
    @MainActor
    func zoneMemoKey() -> String {
        "az|\(approvalZoneFacetDigest())"
            + "|\(environmentFingerprint)"
    }

    /// 审批区 facet 摘要：与 approvalZoneHeight
    /// 的遍历同集同序（未锚定者入账、锚定集经遍
    /// 历过滤间接在键内）
    private func approvalZoneFacetDigest() -> String {
        guard let inputs = facetZoneInputs()
        else { return "notready" }
        var parts: [String] = []
        for record in inputs.records
        where !inputs.anchored.contains(record.id) {
            parts.append(
                "r\(record.id)"
                    + "\(approvalRecordDigest(record))"
                    + "\(approvalDetailDigest(record.id))"
            )
        }
        for lineID in inputs.resolvedLineIDs
        where !inputs.anchored.contains(lineID) {
            parts.append("l\(lineID)")
        }
        return parts.joined(separator: "|")
    }

    /// 审批区适配器一趟（§331）：快照区 facet
    /// 后交核心（量测工单同形）
    @MainActor
    func approvalZoneHeightWithFacets() -> CGFloat {
        var core = self
        if let ledger, let hubStore {
            core.facets = ChatNativeRowFacetSnapshotter
                .zoneFacets(
                    ledger: ledger, hubStore: hubStore
                )
        }
        return core.approvalZoneHeightUncached()
    }

    /// 审批区行高（ChatApprovalZone）：非 ready
    /// ＝0；ready＝未锚定待批卡＋未锚定已决行、
    /// VStack spacingM
    func approvalZoneHeightUncached() -> CGFloat {
        guard let inputs = facetZoneInputs()
        else { return 0 }
        var items: [CGFloat] = []
        for record in inputs.records
        where !inputs.anchored.contains(record.id) {
            items.append(approvalCardHeight(
                record: record, width: contentWidth
            ))
        }
        for lineID in inputs.resolvedLineIDs
        where !inputs.anchored.contains(lineID) {
            items.append(
                OneDayMetrics.spacingS * 2
                    + spec(.footnote)
            )
        }
        guard !items.isEmpty else { return 0 }
        return items.reduce(0, +)
            + OneDayMetrics.spacingM
                * CGFloat(items.count - 1)
    }

    // MARK: - 回响族

    /// 留痕回响行高（traceEchoRow）：内距 H
    /// spacingM／V spacingS；左图标 13＋文字列
    /// （主句 footnote 折行／对象行单行／结果行
    /// ≤3 行、失败 ≤4 行，行间 spacingMicro）＋
    /// 右时刻 caption（宽现测、文字列宽随之折算）
    func traceEchoHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        let snapshot = entry.traceEcho
        let isFailed = snapshot?.isFailed ?? false
        let timeText = Self.traceEchoTimeText(
            entry.createdAt
        )
        let timeWidth = naturalWidth(
            timeText, font: plainFont(.caption1)
        )
        let textWidth = contentWidth
            - OneDayMetrics.spacingM * 2
            - 13 - OneDayMetrics.spacingS
            - OneDayMetrics.spacingS - timeWidth
        var column = plainHeight(
            snapshot?.headline ?? entry.content,
            .footnote, width: textWidth
        )
        if let label = snapshot?.targetLabel,
           !label.isEmpty {
            column += OneDayMetrics.spacingMicro
                + spec(.footnote)
        }
        if let outcome = snapshot?.outcome,
           !outcome.isEmpty {
            column += OneDayMetrics.spacingMicro
                + plainHeight(
                    outcome, .footnote,
                    width: textWidth,
                    lineLimit: isFailed ? 4 : 3
                )
        }
        return OneDayMetrics.spacingS * 2
            + max(column, spec(.caption1))
    }

    /// 回响时刻文案（ChatView.traceEchoTimeText
    /// 同式：今天只时刻、跨日带月日）
    private static func traceEchoTimeText(
        _ date: Date
    ) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(
                .dateTime.hour().minute()
            )
        }
        return date.formatted(
            .dateTime.month().day().hour().minute()
        )
    }

    /// 目标委派回响行高（echoRow）：图标 11＋正
    /// 文 footnote 居中折行＋时刻 caption2，纵内
    /// 距 spacingXS×2
    func echoHeight(_ entry: ChatEntryHeightSnapshot) -> CGFloat {
        let timeText = entry.createdAt.formatted(
            .dateTime.hour().minute()
        )
        let timeWidth = naturalWidth(
            timeText, font: plainFont(.caption2)
        )
        let textWidth = contentWidth
            - 11 - OneDayMetrics.spacingXS * 2
            - timeWidth
        let contentHeight = plainHeight(
            entry.content, .footnote, width: textWidth
        )
        return contentHeight
            + OneDayMetrics.spacingXS * 2
    }

    // MARK: - 回告卡

    /// 回告卡高（reportCard）：内距 spacingM 全
    /// 周；左图标 15＋文字列（标题 subheadline
    /// 折行＋正文 footnote ≤3 行、行间 spacing-
    /// Micro）＋右关闭钮 44；文字列宽＝内容宽−
    /// 内距−图标−两处 spacingS−钮 44
    func reportCardHeight(
        _ item: OverviewNotification
    ) -> CGFloat {
        rowMemo(reportMemoKey(item)) {
            reportCardHeightUncached(item)
        }
    }

    /// 回告卡备忘键（§330/§331 共用单点）
    func reportMemoKey(
        _ item: OverviewNotification
    ) -> String {
        "rc|\(item.id)"
            + "|\(Self.reportDigest(item))"
            + "|\(environmentFingerprint)"
    }

    func reportCardHeightUncached(
        _ item: OverviewNotification
    ) -> CGFloat {
        let textWidth = contentWidth
            - OneDayMetrics.spacingM * 2
            - 15 - OneDayMetrics.spacingS * 2
            - OneDayMetrics.minTapTarget
        var column = plainHeight(
            item.title, .subheadline, width: textWidth
        )
        if !item.body.isEmpty {
            column += OneDayMetrics.spacingMicro
                + plainHeight(
                    item.body, .footnote,
                    width: textWidth, lineLimit: 3
                )
        }
        return OneDayMetrics.spacingM * 2
            + max(OneDayMetrics.minTapTarget, column)
    }

    // MARK: - 空态族

    /// 空态形象段高：顶距 spacingXL＋头像档＋
    /// spacingS＋标题 callout＋spacingS＋说明
    /// caption 居中折行
    func emptyHeroHeight() -> CGFloat {
        rowMemo("eh|\(environmentFingerprint)") {
            emptyHeroHeightUncached()
        }
    }

    func emptyHeroHeightUncached() -> CGFloat {
        let titleHeight = plainHeight(
            L10n.format("和 %@ 聊聊", agentDisplayName),
            .callout, width: contentWidth
        )
        let captionHeight = plainHeight(
            L10n.string(
                "消息经你自己的服务器发给 Agent，记录只存这台手机。"
            ),
            .caption1, width: contentWidth
        )
        return OneDayMetrics.spacingXL
            + emptyStateAvatarSize
            + OneDayMetrics.spacingS + titleHeight
            + OneDayMetrics.spacingS + captionHeight
    }

    /// 空态建议条段高：顶距 spacingL＋三条建议
    /// 行（minHeight 50、行内文 callout 折行兜
    /// 底）＋行间 spacingS
    func emptySuggestionsHeight() -> CGFloat {
        rowMemo("es|\(environmentFingerprint)") {
            emptySuggestionsHeightUncached()
        }
    }

    func emptySuggestionsHeightUncached() -> CGFloat {
        let texts = EmptyChatSuggestions.texts
        var total = OneDayMetrics.spacingL
        for text in texts {
            let textHeight = plainHeight(
                L10n.string(text), .callout,
                width: contentWidth
                    - OneDayMetrics.spacingM * 2
                    - 15 - OneDayMetrics.spacingSM
            )
            total += max(50, textHeight)
        }
        if texts.count > 1 {
            total += OneDayMetrics.spacingS
                * CGFloat(texts.count - 1)
        }
        return total
    }

    /// 未配模型引导卡行高：行外顶距 spacingL（行
    /// 构建点 .padding(.top) 在席）＋卡（内距
    /// spacingM、题 callout semibold＋正文 foot-
    /// note 折行＋钮行 callout，行间 spacingS）
    func modelSetupCardHeight() -> CGFloat {
        rowMemo("ms|\(environmentFingerprint)") {
            modelSetupCardHeightUncached()
        }
    }

    func modelSetupCardHeightUncached() -> CGFloat {
        let innerWidth = contentWidth
            - OneDayMetrics.spacingM * 2
        let bodyHeight = plainHeight(
            "先去加一家服务商、选好模型，回来就能聊。",
            .footnote, width: innerWidth
        )
        let card = OneDayMetrics.spacingM * 2
            + spec(.callout)
            + OneDayMetrics.spacingS + bodyHeight
            + OneDayMetrics.spacingS + spec(.callout)
        return OneDayMetrics.spacingL + card
    }

    // MARK: - 直播行

    /// 直播思考行高：相位默认与 ReasoningBlock
    /// 同算（contentStarted 决定 streaming/
    /// contentStarted 相位），账本覆盖优先。直播
    /// 行恒同步路径（单行、流式瞬态，不进量测
    /// 台——见 §331 对位表注记）
    @MainActor
    func liveReasoningHeight(
        text: String, contentStarted: Bool
    ) -> CGFloat {
        let key = "lr|\(LayoutProductKey.fnv1a(text))"
            + "|\(contentStarted ? "1" : "0")"
            + "|\(Self.boolDigest(ledger?.expansionOverride(for: ChatRowStateKeys.liveReasoning)))"
            + "|\(environmentFingerprint)"
        return rowMemo(key) {
            liveReasoningHeightWithFacets(
                text: text, contentStarted: contentStarted
            )
        }
    }

    @MainActor
    func liveReasoningHeightWithFacets(
        text: String, contentStarted: Bool
    ) -> CGFloat {
        var core = self
        if let ledger,
           let value = ledger.expansionOverride(
               for: ChatRowStateKeys.liveReasoning
           ) {
            core.facets.expansionOverrides[
                ChatRowStateKeys.liveReasoning
            ] = value
        }
        return core.liveReasoningHeightUncached(
            text: text, contentStarted: contentStarted
        )
    }

    func liveReasoningHeightUncached(
        text: String, contentStarted: Bool
    ) -> CGFloat {
        let phase: ReasoningPhase = contentStarted
            ? .contentStarted : .streaming
        let expanded = facetExpansionOverride(
            for: ChatRowStateKeys.liveReasoning
        ) ?? ReasoningPresentation.defaultExpanded(
            phase: phase
        )
        return reasoningHeight(
            text: text, expanded: expanded
        )
    }

    /// 直播正文行高（nativeStreamingContent）：
    /// 空文＝等待泡（打字点 6／上传行 callout，
    /// 内容纵内距 spacingXS×2＋气泡纵内距 26）；
    /// 非空＝气泡内 StreamingBlockText（闭合块逐
    /// 块 MarkdownText＋尾块 StreamingText、段间
    /// spacingSM）＋气泡纵内距 26。尾块词元流高
    /// 以同字阶纯文本量测近似（直播行瞬态、落
    /// 定即被落定行替换，§329 口径）
    /// 【2026-11-20 卡顿修复包改增量口径】（全面
    /// 对比报告 §6 处方）：旧制整行备忘键＝全文
    /// FNV——流式文本每拍都变、恒未命中，每拍全
    /// 量分段＋闭合前缀整段重算。改后不再走整行
    /// 备忘：闭合块逐块走 markdownHeight 的内容
    /// 备忘（块内容冻结→恒命中）、累加求和，只
    /// 现算尾块增量；块间间隙走呈现侧同一两级口
    /// 径（StreamingBlockText.gapAfter：散文相邻
    /// paragraphSpacing、其余 spacingSM），与落
    /// 定整段量测的段内＋段间两级口径逐值等值、
    /// 落定不跳高（呈现侧同日改逐块呈现、两侧同
    /// 构）
    func liveTextHeight(
        text: String,
        isUploading: Bool
    ) -> CGFloat {
        liveTextHeightUncached(
            text: text, isUploading: isUploading
        )
    }

    func liveTextHeightUncached(
        text: String,
        isUploading: Bool
    ) -> CGFloat {
        let bubbleVertical =
            OneDayMetrics.bubblePaddingV * 2
        if text.isEmpty {
            let content = isUploading
                ? max(6, spec(.callout)) : 6
            return content
                + OneDayMetrics.spacingXS * 2
                + bubbleVertical
        }
        let blocks = StreamingBlockSegmenter.blocks(
            for: text
        )
        let tail = StreamingBlockSegmenter
            .tailSource(of: blocks)
        // 逐块累加（与呈现侧 closedParts 同一分
        // 解）：闭合块高走内容备忘恒命中、块后间
        // 隙走 gapAfter 两级口径（末块到尾块同
        // 走，见 gapAfter 注），尾块单独现算
        let parts = StreamingBlockText.closedParts(for: text)
        // 末块→尾块衔接与呈现侧同口径（gapAfter 两
        // 级口径须知尾块类别，台账 185）；空尾无衔接
        let tailKind = tail.isEmpty
            ? nil
            : blocks.last(where: { $0.isTail })?.kind
        var total: CGFloat = 0
        for (index, part) in parts.enumerated() {
            total += markdownHeight(part.source)
            // 空尾时末块后间隙不计（与光标行同为流
            // 式专属项，见下空尾对齐注）
            if !(tail.isEmpty && index == parts.count - 1) {
                total += StreamingBlockText.gapAfter(
                    index: index, parts: parts,
                    tailKind: tailKind
                )
            }
        }
        if tail.isEmpty {
            // 空尾两态对齐（台账 185）：光标行（呈现
            // 侧 StreamingCaret 恒占一行）与末块后间
            // 隙（空尾时 gapAfter 的 spacingSM 兜底
            // 值）都是流式专属项、落定量测无对应项——
            // 计入即落定瞬间整行塌约 34pt（用户报
            // 「间距有时会变」的落点之一）。两项同
            // 步不计、与落定逐值对齐：呈现侧光标在
            // 空尾态可能被行高框轻微裁切（瞬态、只
            // 发生在块边界拍），换落定不跳高——与本
            // 函数「落定不跳高」的既有口径同向
        } else if Self.tailUsesMarkdownMeasure(tail) {
            // 结构化尾块（台账 185）：尾块含列表/
            // 代码/表格/标题时，纯文本近似与落定
            // markdown 口径差出整行级偏差、块闭合/
            // 落定瞬间跳高——改走落定同口径整段量
            // 测（markdownHeight 内容备忘与闭合块
            // 同路）。纯散文尾块保留 plainHeight 近
            // 似（两口径差只在结构化内容上、散文近
            // 等，卡顿包既有结论不动）
            total += markdownHeight(tail)
        } else {
            total += memoized(
                "stream", tail, assistantTextWidth
            ) {
                plainHeight(
                    tail, .body,
                    width: assistantTextWidth
                )
            }
        }
        return total + bubbleVertical
    }

    /// 尾块结构化判定（台账 185）：含列表/代码围
    /// 栏/表格/标题任一结构标记→纯文本近似失效。
    /// 逐行扫（尾块为当前生长块、行数有界）；标记
    /// 集与诊断四类对齐——标题＝1–6 个 #＋空格起
    /// 行、无序列表＝- ／* ／+ 起行、有序列表＝
    /// 数字＋.／)＋空格、围栏＝```／~~~、表格＝
    /// 竖线起行或行内含 " | " 分隔
    static func tailUsesMarkdownMeasure(
        _ tail: String
    ) -> Bool {
        for rawLine in tail.split(
            separator: "\n", omittingEmptySubsequences: false
        ) {
            let line = rawLine.trimmingCharacters(
                in: .whitespaces
            )
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                return true
            }
            if line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }
                if hashes.count <= 6,
                   line.dropFirst(hashes.count)
                    .hasPrefix(" ") {
                    return true
                }
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ")
                || line.hasPrefix("+ ") {
                return true
            }
            if line.hasPrefix("|") || line.contains(" | ") {
                return true
            }
            var idx = line.startIndex
            var digits = 0
            while idx < line.endIndex, line[idx].isNumber {
                idx = line.index(after: idx)
                digits += 1
            }
            if digits > 0, idx < line.endIndex,
               line[idx] == "." || line[idx] == ")" {
                let after = line.index(after: idx)
                if after < line.endIndex, line[after] == " " {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - 条目行（与 ChatView.bubble 分流同序）

    /// 条目行高总口（§330 备忘包装）：键＝条目
    /// 修订摘要（与 ChatView 构造点的修订同源派
    /// 生——点亮/选区/样式键不入高、恒以中性值
    /// 派生）＋facet 状态摘要＋环境指纹
    @MainActor
    func entryHeight(
        _ entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false
    ) -> CGFloat {
        rowMemo(
            entryMemoKey(
                for: entry, dividerText: dividerText,
                showsUnreadDivider: showsUnreadDivider
            )
        ) {
            entryHeightWithFacets(
                entry, dividerText: dividerText,
                showsUnreadDivider: showsUnreadDivider
            )
        }
    }

    /// 条目行备忘键（§330/§331 共用单点）：同步
    /// 路径与量测台工单以同一键对账——键的构成
    /// 只此一处，不许两路各算一份
    @MainActor
    func entryMemoKey(
        for entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false
    ) -> String {
        entryMemoKey(
            baseRevision: ChatNativeRowRevision.entryBase(
                entry,
                dividerText: dividerText,
                showsUnreadDivider: showsUnreadDivider
            ),
            entry: entry
        )
    }

    /// 基段入参版（2026-11-20 卡顿修复包）：行构
    /// 造点已为行修订建过同一基段时直喂本口——基
    /// 段只建一遍，中性尾段（点亮 false/样式键空）
    /// 在此接续，与上式逐字同键（字段枚举单点在
    /// entryBase，两路不许各列一份）
    @MainActor
    func entryMemoKey(
        baseRevision: ChatNativeRowRevision,
        entry: ChatEntry
    ) -> String {
        var revision = baseRevision
        revision.addFlag(false)
        revision.addText("")
        return "e|\(entry.id.uuidString)"
            + "|\(Self.revisionDigest(revision))"
            + "|\(entryFacetDigest(entry))"
            + "|\(environmentFingerprint)"
    }

    /// 适配器一趟（§331）：主线程快照 facet＋条
    /// 目后交核心——同步路径经此、量测工单在后
    /// 台以同形直调 entryHeightCore，两路同高由
    /// 对拍测试钉住
    @MainActor
    func entryHeightWithFacets(
        _ entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false
    ) -> CGFloat {
        var core = self
        if let ledger, let hubStore {
            core.facets = ChatNativeRowFacetSnapshotter
                .entryFacets(
                    for: entry, ledger: ledger,
                    hubStore: hubStore
                )
        }
        return core.entryHeightCore(
            ChatEntryHeightSnapshot(entry),
            dividerText: dividerText,
            showsUnreadDivider: showsUnreadDivider
        )
    }

    /// 条目行高总口（核心，线程无关）：时间分隔
    /// 槽（在席时 footnote 一行＋spacingS）＋
    /// bubble 本体——分流序与 ChatView.bubble
    /// 逐字同序（回响→审批锚→委派回响→工具卡→
    /// 用户→助手）
    func entryHeightCore(
        _ entry: ChatEntryHeightSnapshot,
        dividerText: String?,
        showsUnreadDivider: Bool = false
    ) -> CGFloat {
        var total: CGFloat = 0
        if let dividerText {
            total += plainHeight(
                dividerText, .footnote,
                width: contentWidth
            ) + OneDayMetrics.spacingS
        }
        if showsUnreadDivider {
            // 台账 148：NEW 分界槽与时间分隔槽同式
            // （徽标一行＋spacingS 行间隙）——呈现
            // 侧 ChatUnreadDividerView 的高由徽标文
            // 本单行决定、与本槽逐值同高
            total += plainHeight(
                L10n.string("新消息"), .footnote,
                width: contentWidth
            ) + OneDayMetrics.spacingS
        }
        if entry.traceKey != nil {
            return total + traceEchoHeight(entry)
        }
        if entry.approvalKey != nil {
            return total + approvalAnchorHeight(entry)
        }
        if entry.echoKey != nil {
            return total + echoHeight(entry)
        }
        if let card = entry.toolCard {
            return total + toolCardHeightUncached(
                card: card, width: contentWidth,
                expanded: facetExpansionOverride(
                    for: ChatRowStateKeys.toolEntry(
                        entry.id
                    )
                ) ?? false,
                plain: false
            )
        }
        if entry.role == "user" {
            return total + userEntryHeight(entry)
        }
        return total + assistantEntryHeight(entry)
    }

    /// 用户行高：HStack{Spacer(min 44)＋[失败钮
    /// 44]＋VStack(spacingXS, trailing)}——列宽
    /// ＝内容宽−栈间距−侧让位−（失败钮＋间距在
    /// 席时）；VStack 槽序与 bubble 用户支逐字
    /// 同序：引用块／本地图行／远端图×n／正文泡
    /// ／文件牌组／待发状态行
    private func userEntryHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        // §329 续修（拟合直测校准实证）：HStack 与
        // Spacer 相邻处不另计默认间距（Spacer 本身
        // 即间距、相邻 stack spacing 被吸收）——旧
        // 稿多扣 8pt 令正文宽窄一档、长文虚高 3 行；
        // 失败重发钮与正文列之间无 Spacer、默认间
        // 距 spacingS 照计
        var columnWidth = contentWidth
            - OneDayMetrics.bubbleSideInset
        if entry.sendFailed {
            columnWidth -= OneDayMetrics.spacingS
                + OneDayMetrics.minTapTarget
        }
        let textWidth = columnWidth
            - OneDayMetrics.bubblePaddingH * 2
        var slots: [CGFloat] = []
        if let quote = entry.quote {
            slots.append(messageQuoteHeight(
                name: MessageQuote.speakerName(
                    for: quote.role,
                    assistantName: agentDisplayName
                ),
                summary: quote.summary(maxLength: 80),
                columnWidth: columnWidth,
                nameSingleLine: false
            ))
        } else if let sourceQuote = entry.sourceQuote {
            let firstLine: String
            let summary: String
            switch sourceQuote {
            case .feed(let feedQuote):
                firstLine = feedQuote.mark.isEmpty
                    ? feedQuote.title
                    : "\(feedQuote.mark) \(feedQuote.title)"
                summary = feedQuote.summary(
                    maxLength: 80
                )
            case .idea(let ideaQuote):
                firstLine = ideaQuote.mark.isEmpty
                    ? ideaQuote.title
                    : "\(ideaQuote.mark) \(ideaQuote.title)"
                summary = ideaQuote.summary(
                    maxLength: 80
                )
            case .file(let fileQuote):
                firstLine = fileQuote.name
                summary = fileQuote.summary(
                    maxLength: 80
                )
            case .goal(let goalQuote):
                firstLine = goalQuote.title
                summary = goalQuote.summary(
                    maxLength: 80
                )
            }
            slots.append(messageQuoteHeight(
                name: firstLine, summary: summary,
                columnWidth: columnWidth,
                nameSingleLine: true
            ))
        }
        let localImageDatas = entry.imageDatas
        if !localImageDatas.isEmpty {
            // localImageRow：解码成功才出卡（同缓
            // 存同步读）、全失败整行 0——与视图同
            // 判（LocalImageDecodeCache 同源）
            let decoded = localImageDatas.indices
                .contains { index in
                    facetLocalImageDecoded(
                        entryID: entry.id, index: index,
                        data: localImageDatas[index]
                    )
                }
            slots.append(
                decoded ? ChatImageSizing.cardHeight : 0
            )
        }
        for _ in entry.remoteImagePaths {
            slots.append(ChatImageSizing.cardHeight)
        }
        if !entry.content.isEmpty {
            // 正文泡：plainRuns 整形拼装（与呈现/
            // 产物层同源）＋气泡内距 V 13×2
            let textHeight = memoized(
                "user", entry.content, textWidth
            ) {
                assembledHeight(
                    paragraphs: [
                        InlineTextParagraph(
                            runs: TextShaping.shapeRuns(
                                InlineRunBuilder
                                    .plainRuns(
                                        entry.content
                                    )
                            )
                        ),
                    ],
                    foreground: Palette.userBubbleText,
                    width: textWidth
                )
            }
            slots.append(
                textHeight
                    + OneDayMetrics.bubblePaddingV * 2
            )
        }
        if !entry.remoteFilePaths.isEmpty {
            var chips: CGFloat = 0
            for rawPath in entry.remoteFilePaths {
                let split = FileLineAnchor.split(
                    pathWithAnchor: rawPath
                )
                chips += fileChipHeight(
                    path: split.path,
                    width: columnWidth
                )
            }
            chips += OneDayMetrics.spacingXS
                * CGFloat(
                    entry.remoteFilePaths.count - 1
                )
            slots.append(chips)
        }
        if entry.isPendingSend {
            slots.append(spec(.caption1))
        }
        var total: CGFloat = 0
        if !slots.isEmpty {
            total = slots.reduce(0, +)
                + OneDayMetrics.spacingXS
                    * CGFloat(slots.count - 1)
        }
        if entry.sendFailed {
            total = max(
                total, OneDayMetrics.minTapTarget
            )
        }
        return total
    }

    /// 助手行高：VStack(spacingS, leading) 槽序
    /// 与 bubble 助手支逐字同序：思考块／远端图
    /// ×n／MEDIA 图×n／裸路径图×n／交付项×n／
    /// 整条裸路径／正文泡／文件牌组。摘行与派生
    /// 扫描全走 EntryScanMemo 同源（与视图同一
    /// 调用、同一备忘），存在性读 FileMetadata-
    /// Store 同源——视图怎么派生、合成怎么派生
    private func assistantEntryHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        let scans = EntryScanMemo.scans(
            entryID: entry.id,
            content: entry.content,
            remoteImagePaths: entry.remoteImagePaths
        )
        let deliverySplit = scans.delivery
        let mediaSplit = scans.media
        let wholePathRef = FileRefDetector
            .wholeMessagePath(in: mediaSplit.text)
        let inlineImages = scans.inlineCandidates
            .filter { $0.path != wholePathRef?.path }
        let mediaStandalonePaths = Set(
            scans.standalonePaths
        )
        let displayText = EntryScanMemo.displayText(
            entryID: entry.id,
            mediaText: mediaSplit.text,
            stripPaths: Set(
                inlineImages.filter {
                    $0.isStandaloneLine
                        && facetFileExistence($0.path)
                            == .exists
                }.map(\.path)
            ).union(
                mediaSplit.imagePaths.filter {
                    mediaStandalonePaths.contains($0)
                        && facetFileExistence($0)
                            == .exists
                }
            ).union(
                wholePathRef.map { [$0.path] } ?? []
            )
        )
        var slots: [CGFloat] = []
        if let reasoning = entry.reasoning,
           !reasoning.isEmpty {
            let expanded = facetExpansionOverride(
                for: ChatRowStateKeys.reasoningEntry(
                    entry.id
                )
            ) ?? ReasoningPresentation
                .defaultExpanded(phase: .finished)
            slots.append(reasoningHeight(
                text: reasoning, expanded: expanded
            ))
        }
        for _ in entry.remoteImagePaths {
            slots.append(ChatImageSizing.cardHeight)
        }
        // 图片槽占位（台账 185）：存在性未定先按
        // 190 占位、确证 missing 才塌 0——旧口径未
        // 定即 0、解析回来凭空长高 190（用户报
        // 「间距有时会变」的最吻合落点）。视图侧
        // AssistantMediaImage 未确证时整行不显
        // 示，占位期该槽为空白填充、确证存在图在
        // 原位填入
        for path in mediaSplit.imagePaths {
            slots.append(
                facetFileExistence(path) == .missing
                    ? 0 : ChatImageSizing.cardHeight
            )
        }
        for ref in inlineImages {
            slots.append(
                facetFileExistence(ref.path) == .missing
                    ? 0 : ChatImageSizing.cardHeight
            )
        }
        for deliveryID in deliverySplit.deliveryIDs {
            slots.append(
                deliveryItemHeight(id: deliveryID)
            )
        }
        if let wholePathRef {
            if FileRefDetector.isImagePath(
                wholePathRef.path
            ) {
                slots.append(ChatImageSizing.cardHeight)
            } else {
                slots.append(barePathFileCardHeight(
                    path: wholePathRef.path
                ))
            }
        }
        if !displayText.isEmpty
            || (mediaSplit.imagePaths.isEmpty
                && inlineImages.isEmpty
                && deliverySplit.deliveryIDs.isEmpty
                && wholePathRef == nil) {
            slots.append(
                markdownHeight(displayText)
                    + OneDayMetrics.bubblePaddingV * 2
            )
        }
        let fileRefs = FileRefDetector
            .detectStandaloneAnchored(
                in: entry.content,
                excluding: entry.remoteImagePaths
                    + mediaSplit.imagePaths
                    + inlineImages.map(\.path)
                    + (wholePathRef.map { [$0.path] }
                        ?? [])
            )
        if !fileRefs.isEmpty {
            var chips: CGFloat = 0
            for ref in fileRefs {
                chips += assistantFileChipHeight(
                    path: ref.path
                )
            }
            chips += OneDayMetrics.spacingXS
                * CGFloat(fileRefs.count - 1)
            slots.append(chips)
        }
        guard !slots.isEmpty else { return 0 }
        return slots.reduce(0, +)
            + OneDayMetrics.spacingS
                * CGFloat(slots.count - 1)
    }
}


/// 整行实算计数锁盒（§331）：NSLock 护裸 Int、
/// @unchecked Sendable 依据＝一切读写都在锁内
/// （与 OneDayCore ParseMemoBox 同式）
private final class LockedRowComputationCounter:
    @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = 0
        lock.unlock()
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
