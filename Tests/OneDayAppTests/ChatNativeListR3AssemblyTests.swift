import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §293（原生重建 R3）原生散文 cell 真实装配回
/// 归（续 R1/R2 装配壳、同窗同座）：行内容全是
/// 真实生产拼装（ChatNativeProseAssembly 段拼
/// 装单源／MarkdownText 托管形态），禁用固定高
/// 占位行作证据：
/// ⑪同条目双形态行高对拍（施工图 §6.2⑥）：
/// 同一助手多段散文（段落＋标题＋列表＋引用）
/// 与同一用户正文，托管形态（assistantBubble
/// 几何复刻＋MarkdownText／SelectableInline-
/// Text）与原生散文 cell 的 cell 实高逐值比
/// 对，差须 ≤1；
/// ⑫原生 cell 装配本体断言：文本视图即 §168
/// 本体（TK2/关编辑/开选择/关滚动/T4 探测开
/// 集）、整行菜单交互挂气泡面且点位否决守文
/// 本区、右滑桥识别器真装上集合视图且合成位
/// 移走完触发链、选区回报与链接出口走委托本
/// 体、选区在场时同段重配置不换文本视图（段
/// 身份短路＝选区不自毁）；
/// ⑬混合行集间距：原生/托管行交错时相邻帧间
/// 距恒单源 24（H1 在下沉行上续守）。
@MainActor
final class ChatNativeListR3AssemblyTests: XCTestCase {

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874
    private let composerHeight: CGFloat = 54
    private let fedTopInset: CGFloat = 122
    private let bottomMargin: CGFloat = 16
    private let bottomPadding: CGFloat = 8

    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    private func assemble() {
        window = UIWindow(
            frame: CGRect(
                x: 0, y: 0, width: windowW, height: windowH
            )
        )
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()

        handle = ChatNativeListHandle()
        controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = ChatListCarrierCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        root.view.layoutIfNeeded()
    }

    private func apply(rows: [ChatNativeRow]) {
        controller.apply(
            rows: rows,
            layout: ChatCarrierLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: bottomPadding,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: fedTopInset,
            bottomMargin: bottomMargin,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: composerHeight)
            ),
            arrowView: AnyView(Color.clear)
        )
        window.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval = 1.2) {
        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window.layoutIfNeeded()
    }

    private func frame(at index: Int) throws -> CGRect {
        let attrs = controller.collectionView
            .layoutAttributesForItem(
                at: IndexPath(item: index, section: 0)
            )
        return try XCTUnwrap(attrs).frame
    }

    private func cell(at index: Int) -> UICollectionViewCell? {
        controller.collectionView.cellForItem(
            at: IndexPath(item: index, section: 0)
        )
    }

    // MARK: - 拼装（生产单源，测试只供环境与回调记账）

    /// 回调记账盒（断言注入链真达）
    private final class Recorder {
        var menuReply = false
        var menuFork = false
        var menuSelect = false
        var swipeReply = false
        var selectionEvents: [Bool] = []
        var openedURL: URL?
    }

    /// 与 ChatView.nativeProseSpec 同源的环境读
    /// 法：字号档/字重走窗口 trait、墨色经 Envi-
    /// ronmentValues 按窗口明暗解析——拼装本体
    /// 只此一份（ChatNativeProseAssembly），测
    /// 试不复制拼装逻辑
    private func makeSpec(
        isUser: Bool, content: String,
        dividerText: String? = nil,
        swipeEnabled: Bool = true,
        recorder: Recorder
    ) -> ChatNativeProseSpec {
        let traits = window.traitCollection
        let category =
            traits.preferredContentSizeCategory
        let boldText = traits.legibilityWeight == .bold
        var env = EnvironmentValues()
        env.colorScheme = traits.userInterfaceStyle
            == .dark ? .dark : .light
        func resolve(_ color: Color) -> UIColor {
            UIColor(
                cgColor: color.resolve(in: env).cgColor
            )
        }
        func components(_ color: Color) -> String {
            color.resolve(in: env).cgColor.components?
                .map { "\($0)" }.joined(separator: ",")
                ?? ""
        }
        let styleKey = [
            category.rawValue, boldText ? "b" : "r",
            components(Palette.bodyInk),
            components(Palette.inkSecondaryOnFill),
            components(Palette.userBubbleText),
        ].joined(separator: "|")
        let segments = ChatNativeProseAssembly.segments(
            isUser: isUser,
            content: content,
            styleKey: styleKey,
            baseFont: InlineTextFonts.baseFont(
                textStyle: .body, category: category,
                boldText: boldText
            ),
            overrideFont: { style in
                InlineTextFonts.baseFont(
                    textStyle: style, category: category,
                    boldText: boldText
                )
            },
            textColor: resolve(
                isUser
                    ? Palette.userBubbleText
                    : Palette.bodyInk
            ),
            dimmedColor: resolve(
                Palette.inkSecondaryOnFill
            ),
            quoteTextColor: resolve(
                Palette.inkSecondaryOnFill
            )
        )
        return ChatNativeProseSpec(
            dividerText: dividerText,
            isUser: isUser,
            segments: segments ?? [],
            linkColor: resolve(Palette.primary),
            bubbleFill: resolve(
                isUser
                    ? Palette.userBubbleFill
                    : Palette.bubbleFill
            ),
            dividerColor: resolve(Palette.inkSecondary),
            quoteBarColor: resolve(Palette.inkMuted),
            highlightColor: resolve(Palette.primaryTint),
            highlighted: false,
            arrowIdleFill: resolve(Palette.fieldFill),
            arrowArmedFill: resolve(Palette.primaryPale),
            arrowIdleTint: resolve(Palette.inkSecondary),
            arrowArmedTint: resolve(Palette.onPrimary),
            menuPlainText: content,
            onMenuReply: { recorder.menuReply = true },
            onMenuFork: { recorder.menuFork = true },
            onMenuSelect: { recorder.menuSelect = true },
            swipeEnabled: swipeEnabled,
            onSwipeReply: { recorder.swipeReply = true },
            onSelectionChange: {
                recorder.selectionEvents.append($0)
            },
            openURL: { recorder.openedURL = $0 }
        )
    }

    private func proseRow(
        _ key: String, isUser: Bool, _ content: String,
        dividerText: String? = nil,
        recorder: Recorder
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil, version: 1,
            estimatedHeight: 120,
            proseSpec: makeSpec(
                isUser: isUser, content: content,
                dividerText: dividerText,
                recorder: recorder
            ),
            makeView: { AnyView(EmptyView()) }
        )
    }

    // MARK: - 托管形态 fixture（生产几何复刻）

    /// assistantBubble 的几何复刻（§263：屏宽比
    /// 左缘/列宽＋泡内边距＋背景圆角）——与 R2
    /// 装配的 bubble 复刻同例：几何常量全出
    /// OneDayMetrics/Palette 单源，内容是生产
    /// MarkdownText 本体
    private func assistantHostedRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        let screenWidth = UIScreen.main.bounds.width
        let columnCap = screenWidth
            * OneDayMetrics.assistantTextWidthFraction
            + OneDayMetrics.bubblePaddingH * 2
        let leading = screenWidth
            * OneDayMetrics.assistantTextLeadingFraction
            - OneDayMetrics.pageGutter
            - OneDayMetrics.bubblePaddingH
        return ChatNativeRow(
            key: key, entryID: nil, version: 1,
            estimatedHeight: 120,
            makeView: {
                AnyView(
                    HStack(alignment: .top) {
                        MarkdownText(text)
                            .padding(
                                .horizontal,
                                OneDayMetrics.bubblePaddingH
                            )
                            .padding(
                                .vertical,
                                OneDayMetrics.bubblePaddingV
                            )
                            .background(
                                RoundedRectangle(
                                    cornerRadius: OneDayMetrics
                                        .assistantBubbleCorner
                                )
                                .fill(Palette.bubbleFill)
                            )
                            .frame(
                                maxWidth: columnCap,
                                alignment: .leading
                            )
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, leading)
                )
            }
        )
    }

    /// 用户泡托管形态复刻（bubble() 用户分支的
    /// 几何子集：Spacer 让位＋正文泡）
    private func userHostedRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil, version: 1,
            estimatedHeight: 80,
            makeView: {
                AnyView(
                    HStack {
                        Spacer(
                            minLength: OneDayMetrics
                                .bubbleSideInset
                        )
                        SelectableInlineText(
                            paragraphs: [
                                InlineTextParagraph(
                                    runs: TextShaping
                                        .shapeRuns(
                                            InlineRunBuilder
                                                .plainRuns(text)
                                        )
                                )
                            ],
                            textStyle: .body,
                            foreground:
                                Palette.userBubbleText
                        )
                        .padding(
                            .horizontal,
                            OneDayMetrics.bubblePaddingH
                        )
                        .padding(
                            .vertical,
                            OneDayMetrics.bubblePaddingV
                        )
                        .background(
                            RoundedRectangle(
                                cornerRadius: OneDayMetrics
                                    .bubbleCorner
                            )
                            .fill(Palette.userBubbleFill)
                        )
                    }
                )
            }
        )
    }

    // MARK: - ⑪ 双形态行高对拍

    func testProseHeightParityWithHostedForm() throws {
        assemble()
        let assistantText =
            "值班电话 13800138000，状态页 https://example.org/status ，邮箱 oncall@example.org。\n\n## 处理顺序\n\n- 先重启网关，再看日志确认恢复\n- 把结果同步到值班群\n\n> 备注：夜间窗口只有二十分钟，超时先回滚再排查。"
        let userText =
            "好，就按你说的顺序来。先重启网关，恢复之后把日志结论发我一份，我明早到单位再细看。"
        let recorder = Recorder()

        apply(rows: [
            assistantHostedRow("host-a", assistantText),
            userHostedRow("host-u", userText),
        ])
        drain()
        let hostedAssistant = try frame(at: 0).height
        let hostedUser = try frame(at: 1).height
        XCTAssertGreaterThan(
            hostedAssistant, 100,
            "托管助手行应为多段真实排版高，实测 \(hostedAssistant)"
        )

        apply(rows: [
            proseRow(
                "prose-a", isUser: false, assistantText,
                recorder: recorder
            ),
            proseRow(
                "prose-u", isUser: true, userText,
                recorder: recorder
            ),
        ])
        drain()
        let proseAssistant = try frame(at: 0).height
        let proseUser = try frame(at: 1).height
        print(
            "R3-⑪ 对拍：助手 托管=\(hostedAssistant)"
                + " 原生=\(proseAssistant)；用户 托管="
                + "\(hostedUser) 原生=\(proseUser)"
        )
        XCTAssertEqual(
            proseAssistant, hostedAssistant, accuracy: 1.0,
            "助手散文双形态行高须逐值一致（托管 \(hostedAssistant) vs 原生 \(proseAssistant)）"
        )
        XCTAssertEqual(
            proseUser, hostedUser, accuracy: 1.0,
            "用户正文双形态行高须逐值一致（托管 \(hostedUser) vs 原生 \(proseUser)）"
        )
        // 原生形态结构直证：两行均为原生 cell
        XCTAssertTrue(
            cell(at: 0) is ChatNativeProseCell,
            "助手散文行须落原生 cell"
        )
        XCTAssertTrue(
            cell(at: 1) is ChatNativeProseCell,
            "用户正文行须落原生 cell"
        )
    }

    // MARK: - ⑫ 原生装配本体断言

    func testNativeProseCellAssembly() throws {
        assemble()
        let content =
            "值班电话 13800138000，状态页 https://example.org/status ，邮箱 oncall@example.org。"
        let recorder = Recorder()
        let spec = makeSpec(
            isUser: false, content: content,
            recorder: recorder
        )
        apply(rows: [
            ChatNativeRow(
                key: "prose-1", entryID: nil, version: 1,
                estimatedHeight: 80, proseSpec: spec,
                makeView: { AnyView(EmptyView()) }
            ),
        ])
        drain()
        let proseCell = try XCTUnwrap(
            cell(at: 0) as? ChatNativeProseCell,
            "散文行须落原生 cell"
        )
        let rowView = proseCell.rowView

        // 文本本体：§168 同装配（TK2 子类/关编辑/
        // 开选择/关滚动/零 inset/T4 探测开集）
        let textView = try XCTUnwrap(
            rowView.testTextViews.first,
            "原生 cell 须含文本视图本体"
        )
        XCTAssertTrue(
            textView is SelectableUITextView,
            "文本本体须为 §168 SelectableUITextView"
        )
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isScrollEnabled)
        XCTAssertEqual(textView.textContainerInset, .zero)
        XCTAssertEqual(
            textView.dataDetectorTypes,
            [.phoneNumber, .link],
            "T4 探测开集须随本体迁移＝[.phoneNumber, .link]"
        )
        XCTAssertTrue(
            (textView.text ?? "").contains("13800138000"),
            "文本视图须承载正文实文"
        )

        // S3 挂载面：菜单交互在气泡面、不在文本面
        XCTAssertTrue(
            rowView.testBubbleView.interactions.contains {
                $0 is UIContextMenuInteraction
            },
            "整行菜单交互须挂气泡铬件面"
        )
        // 点位否决：文本区内点位→nil（归文本体
        // 系）；边距带点位→出配置（整行菜单）
        let interaction = UIContextMenuInteraction(
            delegate: rowView
        )
        let bubble = rowView.testBubbleView
        let textFrameInBubble = textView.convert(
            textView.bounds, to: bubble
        )
        let textPoint = CGPoint(
            x: textFrameInBubble.midX,
            y: textFrameInBubble.midY
        )
        XCTAssertNil(
            rowView.contextMenuInteraction(
                interaction,
                configurationForMenuAtLocation: textPoint
            ),
            "文本区点位须否决整行菜单（S3 仲裁）"
        )
        let bandPoint = CGPoint(
            x: textFrameInBubble.minX - 8,
            y: textFrameInBubble.midY
        )
        XCTAssertNotNil(
            rowView.contextMenuInteraction(
                interaction,
                configurationForMenuAtLocation: bandPoint
            ),
            "气泡边距带点位须出整行菜单"
        )

        // 右滑桥：识别器真装上宿主集合视图、合成
        // 位移走完「过线触发＋触觉点同一回调」链、
        // 收尾回位
        let installer = rowView.testInstaller
        let recognizer = try XCTUnwrap(
            installer.installedRecognizer,
            "右滑桥识别器须已安装"
        )
        XCTAssertTrue(
            controller.collectionView.gestureRecognizers?
                .contains(recognizer) ?? false,
            "右滑识别器须装在集合视图（宿主滚动视图）上"
        )
        installer.processPanTranslation(80)
        XCTAssertTrue(
            recorder.swipeReply,
            "过线位移须触发引用回调（Core 判据 60）"
        )
        XCTAssertGreaterThan(
            rowView.testSwipeOffsetX, 0,
            "拖动中行内容须有显形位移"
        )
        installer.processPanEnd()
        drain(0.5)
        XCTAssertEqual(
            rowView.testSwipeOffsetX, 0, accuracy: 0.5,
            "收尾后行内容须回位"
        )

        // 链接出口：委托本体拦截 tel 链接、恒返
        // 回 false、URL 交注入出口
        let tel = try XCTUnwrap(
            URL(string: "tel:13800138000")
        )
        let delegate = try XCTUnwrap(textView.delegate)
        let allowed = delegate.textView?(
            textView, shouldInteractWith: tel,
            in: NSRange(location: 5, length: 11),
            interaction: .invokeDefaultAction
        ) ?? true
        XCTAssertFalse(
            allowed, "链接点按不许系统直开（出口拦截）"
        )
        XCTAssertEqual(recorder.openedURL, tel)

        // 选区回报＋段身份短路：置选区→回报 true；
        // 以同段新规格（右滑门控翻转）重配置后文
        // 本视图实例与选区均须原样存续
        let fullText = (textView.text ?? "") as NSString
        let numberRange = fullText.range(
            of: "13800138000"
        )
        textView.selectedRange = numberRange
        delegate.textViewDidChangeSelection?(textView)
        XCTAssertEqual(
            recorder.selectionEvents, [true],
            "选区形成须回报 true"
        )
        let gatedSpec = makeSpec(
            isUser: false, content: content,
            swipeEnabled: false, recorder: recorder
        )
        proseCell.configure(with: gatedSpec)
        XCTAssertTrue(
            rowView.testTextViews.first === textView,
            "同段重配置不许换文本视图（段身份短路）"
        )
        XCTAssertEqual(
            textView.selectedRange, numberRange,
            "同段重配置后选区须原样存续（不自毁）"
        )
        XCTAssertNil(
            installer.installedRecognizer,
            "选区在场（右滑门控关）时桥识别器须摘除"
        )
    }

    // MARK: - ⑬ 混合行集间距单源

    func testMixedRowsKeepSingleSourceSpacing() throws {
        assemble()
        let recorder = Recorder()
        let rows = [
            proseRow(
                "prose-1", isUser: false,
                "第一条助手回复，内容不长。",
                recorder: recorder
            ),
            assistantHostedRow(
                "host-1", "中间一条托管形态的助手回复。"
            ),
            proseRow(
                "prose-2", isUser: true,
                "好，就按你说的顺序来。",
                dividerText: "今天 09:41",
                recorder: recorder
            ),
            proseRow(
                "prose-3", isUser: false,
                "最后一条原生散文回复，收尾。",
                recorder: recorder
            ),
        ]
        apply(rows: rows)
        drain()
        var frames: [CGRect] = []
        for index in rows.indices {
            frames.append(try frame(at: index))
        }
        for index in rows.indices {
            XCTAssertGreaterThan(
                frames[index].height, 30,
                "行 \(index) 高须来自真实排版"
            )
        }
        for index in 0..<(rows.count - 1) {
            let gap = frames[index + 1].minY
                - frames[index].maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 1.0,
                "混合行 \(index)→\(index + 1) 间距须＝单源 24，实测 \(gap)"
            )
        }
        XCTAssertTrue(cell(at: 0) is ChatNativeProseCell)
        XCTAssertFalse(
            cell(at: 1) is ChatNativeProseCell,
            "托管行须仍是托管 cell（形态分发不串）"
        )
        XCTAssertTrue(cell(at: 2) is ChatNativeProseCell)
        XCTAssertTrue(cell(at: 3) is ChatNativeProseCell)
    }

    // MARK: - 拼装资格（结构段不下沉）

    func testAssemblyRejectsStructuralSegments() {
        assemble()
        let recorder = Recorder()
        let traits = window.traitCollection
        let category =
            traits.preferredContentSizeCategory
        let boldText = traits.legibilityWeight == .bold
        func segments(_ content: String)
            -> [ChatNativeProseSpec.Segment]? {
            ChatNativeProseAssembly.segments(
                isUser: false, content: content,
                styleKey: "test",
                baseFont: InlineTextFonts.baseFont(
                    textStyle: .body, category: category,
                    boldText: boldText
                ),
                overrideFont: { style in
                    InlineTextFonts.baseFont(
                        textStyle: style,
                        category: category,
                        boldText: boldText
                    )
                },
                textColor: .label,
                dimmedColor: .secondaryLabel,
                quoteTextColor: .secondaryLabel
            )
        }
        XCTAssertNil(
            segments("正文一段。\n\n```swift\nlet x = 1\n```"),
            "含代码块的行不许下沉（结构段留托管）"
        )
        XCTAssertNil(
            segments("| A | B |\n| - | - |\n| 1 | 2 |"),
            "含表格的行不许下沉"
        )
        let mixed = segments(
            "正文一段。\n\n> 引用一行。\n\n后续一段。"
        )
        XCTAssertNotNil(mixed, "散文＋引用须可下沉")
        XCTAssertEqual(mixed?.count, 3)
        _ = recorder
    }
}
