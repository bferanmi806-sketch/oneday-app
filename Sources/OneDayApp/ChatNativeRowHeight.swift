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
@MainActor
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
    let ledger: ChatRowStateLedger
    let hubStore: AgentHubStore
    let agentDisplayName: String
    let emptyStateAvatarSize: CGFloat

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
        var height = SelectableTextRepresentable
            .referenceHeight(
                attributed: attributed, width: width
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

    /// 自然单行宽（表格列宽/回响时间列宽用）
    private func naturalWidth(
        _ text: String, font: UIFont
    ) -> CGFloat {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        return SelectableTextRepresentable.measuredSize(
            attributed: attributed,
            proposal: ProposedViewSize(
                width: nil, height: nil
            )
        ).width
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
        return SelectableTextRepresentable
            .referenceHeight(
                attributed: assembled, width: width
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

    private static let textCache =
        NSCache<NSString, NSNumber>()

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
            // 文本（横滚不折行、等宽 footnote 自然
            // 宽量高＝行数×行高）
            let codeHeight = SelectableTextRepresentable
                .referenceHeight(
                    attributed: NSAttributedString(
                        string: code,
                        attributes: [
                            .font: monospacedFont(.footnote),
                        ]
                    ),
                    width: nil
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
        // Grid：列宽＝该列各格自然宽的最大值、封
        // 顶 maxColumnWidth；格文本 .callout（strong
        // 段 bold）在列宽内折行；行高＝行内最高格；
        // 行间 verticalSpacing spacingXS；表头行与
        // 数据行之间一行 GroupDivider（gridCell-
        // Columns 占整行）
        let columnCap = CGFloat(
            MarkdownTablePresentation.maxColumnWidth
        )
        var columnWidths = [CGFloat](
            repeating: 0, count: header.count
        )
        func cellAttributed(_ cell: String) -> NSAttributedString {
            tableCellAttributed(cell)
        }
        for (column, cell) in header.enumerated() {
            columnWidths[column] = max(
                columnWidths[column],
                naturalWidth(
                    cell, font: weightedFont(
                        .callout, .bold
                    )
                )
            )
        }
        for row in rows {
            for (column, cell) in row.enumerated()
            where column < header.count {
                columnWidths[column] = max(
                    columnWidths[column],
                    naturalWidth(
                        cell, font: plainFont(.callout)
                    )
                )
            }
        }
        for index in columnWidths.indices {
            columnWidths[index] = min(
                columnWidths[index], columnCap
            )
        }
        func rowHeight(_ cells: [String]) -> CGFloat {
            var height: CGFloat = 0
            for (column, cell) in cells.enumerated()
            where column < header.count {
                let cellHeight = SelectableTextRepresentable
                    .referenceHeight(
                        attributed: cellAttributed(cell),
                        width: columnWidths[column]
                    )
                height = max(height, cellHeight)
            }
            return height
        }
        let dividerHeight = 1 / max(displayScale, 1)
        var total = rowHeight(header) + dividerHeight
        for row in rows {
            total += rowHeight(row)
        }
        let gridRows = rows.count + 2
        total += OneDayMetrics.spacingXS
            * CGFloat(gridRows - 1)
        return total
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
                    spec(.footnote), valueHeight
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
            size: FileMetadataStore.shared
                .metadata(for: path)?.size,
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
    /// 性门同判据（FileMetadataStore 同源读）
    func assistantFileChipHeight(
        path: String
    ) -> CGFloat {
        if FileMetadataStore.shared.existence(
            for: path
        ) == .exists {
            return fileChipHeight(
                path: path, width: contentWidth
            )
        }
        return plainHeight(
            path, .callout, width: contentWidth
        )
    }

    /// BarePathFileCard：确证不在出失效卡（无菜
    /// 单、几何与 FileChip 同族），其余走 FileChip
    func barePathFileCardHeight(
        path: String
    ) -> CGFloat {
        guard FileMetadataStore.shared.existence(
            for: path
        ) == .missing else {
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
    /// 态机同判）：meta 未到＝0（EmptyView）、查
    /// 无＝标记原文 .callout、gone＝一行 .callout、
    /// image＝§130 定高卡 190、其余＝封面卡
    func deliveryItemHeight(id: String) -> CGFloat {
        switch DeliveryStore.shared.metaResult(
            for: id
        ) {
        case nil:
            return 0
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
        let synthetic = WorkspaceFileEntry(
            name: meta.name, path: meta.path,
            isDirectory: false, size: meta.size,
            mtime: nil, mimeType: meta.mime
        )
        let coverForm = meta.cover.cover
            || DeliveryStore.shared.hasCachedImage(
                id: meta.id, variant: .cover
            )
            || FileThumbnailStore.shared
                .hasCachedThumbnail(
                    for: synthetic, targetPixelSize: 720
                )
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
                plainHeight(
                    text, .footnote, width: bodyWidth
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

    /// 卡行本体高：max(图标盒 36, 标题行＋副行)
    private func toolCardRowHeight(
        _ card: ToolCard
    ) -> CGFloat {
        var textHeight = spec(.subheadline)
        if !toolCardSubtitle(card).isEmpty {
            textHeight += OneDayMetrics.spacingMicro
                + spec(.caption1)
        }
        return max(36, textHeight)
    }

    /// 详情字段高：标签 caption＋spacingMicro＋
    /// 正文（caption，等宽档走等宽量测）
    private func toolDetailFieldHeight(
        text: String, monospaced: Bool, width: CGFloat
    ) -> CGFloat {
        let textHeight = monospaced
            ? measurePlain(
                text,
                font: monospacedFont(.caption1),
                width: width
            )
            : plainHeight(text, .caption1, width: width)
        return spec(.caption1)
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
        var total = fields.reduce(0, +) + spec(.caption1)
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

    /// ToolCardView 高：plain（组内嵌）无自家内
    /// 距、独立卡内距 15；展开＋spacingS＋发丝线
    /// 1＋spacingS＋详情区
    func toolCardHeight(
        card: ToolCard, width: CGFloat,
        expanded: Bool, plain: Bool
    ) -> CGFloat {
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

    /// ToolCardGroupView 高：内距 15＋组头行 36；
    /// 展开＋顶距 spacingS＋逐卡 plain 高＋卡间
    /// 分隔（发丝线 1＋纵内距 spacingS×2）
    func toolGroupHeight(
        cards: [ToolCard], groupKey: String
    ) -> CGFloat {
        var total = 30 + max(36, spec(.subheadline))
        let groupExpanded = ledger.expansionOverride(
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
            total += toolCardHeight(
                card: card,
                width: contentWidth - 30,
                expanded: ledger.expansionOverride(
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
        if let note = hubStore.cardNotes[record.id] {
            items.append(plainHeight(
                note, .caption1, width: innerWidth
            ))
        }
        // 详情区：收起＝SmoothExpand 零高一项；展
        // 开按四态分（加载行／内容＋收起行／错误
        // ＋收起行，内容与收起行各带顶距 spacingS
        // 且同为 face 的 VStack 子项）
        let detail = ledger.approvalDetail(
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
        if hubStore.decidingIDs.contains(record.id) {
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
        _ entry: ChatEntry
    ) -> CGFloat {
        let recordID = ApprovalAnchor.recordID(
            fromKey: entry.approvalKey ?? ""
        ) ?? ""
        switch hubStore.anchorRowState(
            recordID: recordID
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

    /// 审批区行高（ChatApprovalZone）：非 ready
    /// ＝0；ready＝未锚定待批卡＋未锚定已决行、
    /// VStack spacingM
    func approvalZoneHeight() -> CGFloat {
        guard case .ready(let records)
            = hubStore.approvalState
        else { return 0 }
        let anchored = hubStore.anchoredRecordIDs
        var items: [CGFloat] = []
        for record in records
        where !anchored.contains(record.id) {
            items.append(approvalCardHeight(
                record: record, width: contentWidth
            ))
        }
        for line in hubStore.resolvedLines
        where !anchored.contains(line.id) {
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
        _ entry: ChatEntry
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
    func echoHeight(_ entry: ChatEntry) -> CGFloat {
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
    /// contentStarted 相位），账本覆盖优先
    func liveReasoningHeight(
        text: String, contentStarted: Bool
    ) -> CGFloat {
        let phase: ReasoningPhase = contentStarted
            ? .contentStarted : .streaming
        let expanded = ledger.expansionOverride(
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
    /// 非空＝气泡内 StreamingBlockText（闭合前
    /// 缀 MarkdownText＋尾块 StreamingText、段间
    /// spacingSM）＋气泡纵内距 26。尾块词元流高
    /// 以同字阶纯文本量测近似（直播行瞬态、落
    /// 定即被落定行替换，§329 口径）
    func liveTextHeight(
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
        let prefix = StreamingBlockSegmenter
            .closedPrefix(of: blocks)
        let tail = StreamingBlockSegmenter
            .tailSource(of: blocks)
        var parts: [CGFloat] = []
        if !prefix.isEmpty {
            parts.append(markdownHeight(prefix))
        }
        if tail.isEmpty {
            // 尾块空：只剩流式光标一元、占一行
            parts.append(spec(.body))
        } else {
            parts.append(memoized(
                "stream", tail, assistantTextWidth
            ) {
                plainHeight(
                    tail, .body,
                    width: assistantTextWidth
                )
            })
        }
        var total = parts.reduce(0, +)
        if parts.count > 1 {
            total += OneDayMetrics.spacingSM
                * CGFloat(parts.count - 1)
        }
        return total + bubbleVertical
    }

    // MARK: - 条目行（与 ChatView.bubble 分流同序）

    /// 条目行高总口：时间分隔槽（在席时 foot-
    /// note 一行＋spacingS）＋bubble 本体——分流
    /// 序与 ChatView.bubble 逐字同序（回响→审批
    /// 锚→委派回响→工具卡→用户→助手）
    func entryHeight(
        _ entry: ChatEntry, dividerText: String?
    ) -> CGFloat {
        var total: CGFloat = 0
        if let dividerText {
            total += plainHeight(
                dividerText, .footnote,
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
            return total + toolCardHeight(
                card: card, width: contentWidth,
                expanded: ledger.expansionOverride(
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
        _ entry: ChatEntry
    ) -> CGFloat {
        let stackGap: CGFloat = 8
        var columnWidth = contentWidth
            - stackGap - OneDayMetrics.bubbleSideInset
        if entry.sendFailed {
            columnWidth -= stackGap
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
        let localImageDatas = entry.allImageDatas
        if !localImageDatas.isEmpty {
            // localImageRow：解码成功才出卡（同缓
            // 存同步读）、全失败整行 0——与视图同
            // 判（LocalImageDecodeCache 同源）
            let decoded = localImageDatas.indices
                .contains { index in
                    LocalImageDecodeCache.shared.image(
                        entryID: entry.id, index: index,
                        data: localImageDatas[index]
                    ) != nil
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
        _ entry: ChatEntry
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
                        && FileMetadataStore.shared
                            .existence(for: $0.path)
                            == .exists
                }.map(\.path)
            ).union(
                mediaSplit.imagePaths.filter {
                    mediaStandalonePaths.contains($0)
                        && FileMetadataStore.shared
                            .existence(for: $0)
                            == .exists
                }
            ).union(
                wholePathRef.map { [$0.path] } ?? []
            )
        )
        var slots: [CGFloat] = []
        if let reasoning = entry.reasoning,
           !reasoning.isEmpty {
            let expanded = ledger.expansionOverride(
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
        for path in mediaSplit.imagePaths {
            slots.append(
                FileMetadataStore.shared.existence(
                    for: path
                ) == .exists
                    ? ChatImageSizing.cardHeight : 0
            )
        }
        for ref in inlineImages {
            slots.append(
                FileMetadataStore.shared.existence(
                    for: ref.path
                ) == .exists
                    ? ChatImageSizing.cardHeight : 0
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
