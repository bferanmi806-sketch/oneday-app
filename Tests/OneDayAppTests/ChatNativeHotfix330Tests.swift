import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §330（0.50.70 热修）三件的单元层验收：
/// 题 1 在途保护——落定拍/连发 apply 拍下，可见
/// cell 有识别器处 began/changed 时其 reconfigure
/// 延后、在途清零后一拍恰落写一次；高度-only 变
/// 化不触发 reconfigure（回归断言）；
/// 题 2 承载换代——cell 的 UIContextMenuInteraction
/// 点位否决（文本帧内→nil、非文本区→出菜单）＋菜单
/// 项集与 SwiftUI 承载逐项同（标题序＋图符在席）；
/// 题 3 整行备忘——真实形态行集（含表格/工具卡/
/// 引用/审批/交付）预填后重复多趟（模拟滚动期
/// body 求值＋合成器每趟现建）实算计数不涨、高
/// 度逐值不变；账本翻转只失效其行；245 行形态同
/// 口径。
/// 覆盖边界（诚实标注）：在途态以 KVC 强制识别器
/// 状态模拟（生产分流逻辑本体为被测物）；原生面
/// 手势的端到端真触摸序列 CI 无有效信号（基线红
/// 族＋AX 环境所限，定因报告题 2 对账在案），流
/// 式进行中的双击/长按终判归用户真机（交卷清单）
@MainActor
final class ChatNativeHotfix330Tests: XCTestCase {
    private var window: UIWindow?
    private var controller: ChatRootViewController?
    private var callbacks = ChatNativeListCallbacks()

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        super.tearDown()
    }

    private func assemble() {
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let root = ChatRootViewController()
        root.onScrollFrame = { [weak self] in
            self?.callbacks.scrollFrames.append($0)
        }
        root.onUserScrollIntent = { [weak self] in
            self?.callbacks.userScrollIntents += 1
        }
        root.onScrollSettled = { [weak self] in
            self?.callbacks.scrollSettleds += 1
        }
        root.onBottomOvershoot =
            { [weak self] velocity in
                self?.callbacks.bottomOvershoots
                    .append(velocity)
            }
        win.rootViewController = root
        win.makeKeyAndVisible()
        window = win
        controller = root
    }

    private func apply(_ rows: [ChatNativeRow]) {
        let composer = UIView(
            frame: CGRect(x: 0, y: 0, width: 402, height: 54)
        )
        composer.backgroundColor = .systemGray5
        let arrow = UIView(
            frame: CGRect(x: 0, y: 0, width: 36, height: 36)
        )
        arrow.isHidden = true
        controller?.apply(
            rows: rows,
            layout: ChatCarrierLayout(
                horizontalPadding: ChatLayoutTokens.pageGutter,
                topPadding: ChatLayoutTokens.spacingM,
                bottomPadding: 8,
                rowSpacing: ChatLayoutTokens.spacingL,
                arrowTrailing: 12,
                arrowGapAboveComposer: 10,
                arrowSize: 36
            ),
            topInset: 122,
            bottomMargin: 0,
            composerView: composer,
            arrowView: arrow
        )
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(
            description: "drain \(seconds)"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
    }

    private func hostingCell(
        at index: Int, file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ChatNativeHostingCell {
        let cell = controller?.collectionView
            .cellForItem(
                at: IndexPath(item: 0, section: index)
            )
        return try XCTUnwrap(
            cell as? ChatNativeHostingCell,
            "section \(index) 应有托管 cell",
            file: file, line: line
        )
    }

    private func textRow(
        _ key: String, text: String,
        height: CGFloat = 60
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, height: height,
            revision: .parts([.text(text)]),
            makeView: {
                AnyView(
                    Text(text)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                )
            }
        )
    }

    private func forceGestureState(
        _ recognizer: UIGestureRecognizer,
        _ state: UIGestureRecognizer.State
    ) {
        recognizer.setValue(
            state.rawValue, forKey: "state"
        )
    }

    // MARK: - 题 1：在途保护

    /// 落定语义下的一拍 apply：无在途行当拍落写、
    /// 在途行延后；识别器清零后经 0.3s 重试拍＋落
    /// 定拍 flush 恰落写一次（生产读口＝cell 配置
    /// 普查）
    func testInFlightCellReconfigureDeferredUntilGestureEnds()
        throws
    {
        assemble()
        var rows = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        apply(rows)
        drain(0.6)
        let cellB = try hostingCell(at: 1)
        let cellC = try hostingCell(at: 2)
        let baseB = cellB.configureCount
        let baseC = cellC.configureCount
        let press = UILongPressGestureRecognizer()
        cellB.contentView.addGestureRecognizer(press)
        forceGestureState(press, .began)
        rows[1] = textRow("b", text: "b-v2")
        rows[2] = textRow("c", text: "c-v2")
        apply(rows)
        XCTAssertEqual(
            cellC.configureCount, baseC + 1,
            "无在途行须当拍落写"
        )
        XCTAssertEqual(
            cellB.configureCount, baseB,
            "在途行 reconfigure 须延后、不冲手势"
        )
        forceGestureState(press, .ended)
        drain(1.2)
        XCTAssertEqual(
            cellB.configureCount, baseB + 1,
            "在途清零后须恰落写一次"
        )
        XCTAssertEqual(cellB.configuredKey, "b")
    }

    /// 流式工况的形状：连发三拍修订（模拟流式期
    /// body 求值连拍），在途行全程零重配、无在途
    /// 行逐拍落写；在途清零后在途行只补写一次
    /// （最新修订）
    func testStreamingPatsNeverReconfigureInFlightCell()
        throws
    {
        assemble()
        var rows = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        apply(rows)
        drain(0.6)
        let cellB = try hostingCell(at: 1)
        let cellC = try hostingCell(at: 2)
        let baseB = cellB.configureCount
        let baseC = cellC.configureCount
        let press = UILongPressGestureRecognizer()
        cellB.contentView.addGestureRecognizer(press)
        forceGestureState(press, .began)
        for version in 2...4 {
            rows[1] = textRow(
                "b", text: "b-v\(version)"
            )
            rows[2] = textRow(
                "c", text: "c-v\(version)"
            )
            apply(rows)
        }
        XCTAssertEqual(
            cellB.configureCount, baseB,
            "连发拍下在途行须零重配"
        )
        XCTAssertEqual(
            cellC.configureCount, baseC + 3,
            "无在途行须逐拍落写"
        )
        forceGestureState(press, .ended)
        drain(1.2)
        XCTAssertEqual(
            cellB.configureCount, baseB + 1,
            "清零后只补写一次（最新修订）"
        )
    }

    /// 高度-only 变化（同键同修订、仅高变）：不触
    /// 发任何 reconfigure、帧高经落定拍落写新值
    /// （§330 备忘下滚动期高频路径的回归断言）
    func testHeightOnlyChangeDoesNotReconfigure()
        throws
    {
        assemble()
        var rows = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        apply(rows)
        drain(0.6)
        let counts = try (0..<3).map {
            try hostingCell(at: $0).configureCount
        }
        rows[1] = textRow(
            "b", text: "b-v1", height: 140
        )
        apply(rows)
        drain(0.6)
        for index in 0..<3 {
            XCTAssertEqual(
                try hostingCell(at: index)
                    .configureCount,
                counts[index],
                "高度-only 变化不许重配 section \(index)"
            )
        }
        let frame = controller?.collectionView
            .layoutAttributesForItem(
                at: IndexPath(item: 0, section: 1)
            )?.frame
        XCTAssertEqual(
            frame?.height ?? 0, 140, accuracy: 1,
            "帧高须落写新值"
        )
    }

    // MARK: - 题 2：菜单承载换代

    private struct MenuProbeTextHost:
        UIViewRepresentable
    {
        func makeUIView(
            context: Context
        ) -> UITextView {
            let textView = UITextView()
            textView.text =
                "按你说的顺序来，这是一段可选中的文字。"
            textView.isScrollEnabled = false
            textView.isEditable = false
            return textView
        }

        func updateUIView(
            _ uiView: UITextView, context: Context
        ) {}
    }

    private func firstTextView(
        in view: UIView
    ) -> UITextView? {
        if let textView = view as? UITextView {
            return textView
        }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    /// §265 点位否决（生产 delegate 本体）：点落
    /// 文本视图帧内→不给行菜单；点落非文本区→给
    /// 菜单；菜单项集与 SwiftUI 承载逐项同序、图
    /// 符在席
    func testRowMenuVetoOnTextAndItemsMatchSwiftUICarrier()
        throws
    {
        assemble()
        let menu = ChatNativeRowContextMenu(
            plainText: "你好",
            onReply: {}, onFork: {},
            onSelect: {}, onShare: {}
        )
        let row = ChatNativeRow(
            key: "m", height: 72,
            revision: .parts([.text("m")]),
            makeView: {
                AnyView(
                    MenuProbeTextHost()
                        .frame(width: 180, height: 56)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                )
            },
            contextMenu: menu
        )
        apply([row])
        drain(0.8)
        let cell = try hostingCell(at: 0)
        let interaction = try XCTUnwrap(
            cell.interactions.compactMap {
                $0 as? UIContextMenuInteraction
            }.first,
            "带菜单描述的行 cell 须装 UIContextMenuInteraction"
        )
        let delegate = try XCTUnwrap(
            interaction.delegate
        )
        let textView = try XCTUnwrap(
            firstTextView(in: cell),
            "探针行须含 UITextView"
        )
        let textFrame = textView.convert(
            textView.bounds, to: cell
        )
        let onText = delegate.contextMenuInteraction(
            interaction,
            configurationForMenuAtLocation: CGPoint(
                x: textFrame.midX, y: textFrame.midY
            )
        )
        XCTAssertNil(
            onText, "文本帧内点位须否决行菜单（§265）"
        )
        let offText = delegate.contextMenuInteraction(
            interaction,
            configurationForMenuAtLocation: CGPoint(
                x: cell.bounds.maxX - 8,
                y: cell.bounds.midY
            )
        )
        XCTAssertNotNil(
            offText, "非文本区点位须给出行菜单"
        )
        let actions = menu.makeMenu().children
            .compactMap { $0 as? UIAction }
        XCTAssertEqual(
            actions.map(\.title),
            ["回复", "在旁聊里接着问", "复制", "选择", "分享"],
            "菜单项集/序须与 SwiftUI 承载逐项同"
        )
        XCTAssertTrue(
            actions.allSatisfy { $0.image != nil },
            "菜单图符须在席"
        )
    }

    // MARK: - 题 3：整行备忘

    private func makeComposer(
        ledger: ChatRowStateLedger =
            ChatRowStateLedger()
    ) -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ledger,
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    private func memoToolCardSample() -> ToolCard {
        ToolCard(
            id: "memo-tool-1", title: "运行命令",
            toolName: "terminal", status: "completed",
            summary: "ls ~/workspace",
            arguments: "{\"command\": \"ls\"}",
            result: "Documents\nDownloads",
            durationSeconds: 0.4
        )
    }

    /// 备忘行集：覆盖现行文本备忘未及的形态——表
    /// 格（网格/降级列表）/工具卡/引用/审批锚/交付/
    /// 远端文件/回响/委派回响/思考/代码/任务清单
    private func memoFacetEntries() -> [ChatEntry] {
        [
            ChatEntry(
                role: "user",
                content: "你好，今天服务器状态怎么样？",
                thread: nil
            ),
            ChatEntry(
                role: "user", content: "就按这个办",
                thread: nil,
                quote: MessageQuote(
                    role: "assistant",
                    content: "前文摘要：先备份，再迁移。"
                )
            ),
            ChatEntry(
                role: "user", content: "",
                thread: nil,
                remoteFilePaths: ["/opt/data/report.xlsx"]
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "状态正常。**粗体结论**先行，其后是说明"
                    + "文字，包含一段较长的叙述用来撑开多行"
                    + "排版，看看换行与行距是否稳定。",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "示例代码：\n\n```swift\n"
                    + "let value = compute(input)\n"
                    + "print(value)\n```",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "| 名称 | 状态 | 备注 |\n"
                    + "| --- | --- | --- |\n"
                    + "| 甲服务 | 正常 | 延迟 12ms |\n"
                    + "| 乙服务 | 异常 | 正在排查 |",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "| 甲 | 乙 | 丙 | 丁 | 戊 |\n"
                    + "| --- | --- | --- | --- | --- |\n"
                    + "| 一 | 二 | 三 | 四 | 五 |",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "- [x] 已完成的事项\n"
                    + "- [ ] 待办的事项\n"
                    + "- 普通列表项",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content: "思考后的正文。",
                thread: nil,
                reasoning: "先查内存，再看容器日志。",
                reasoningSeconds: 3.2
            ),
            ChatEntry(
                role: "tool", content: "",
                thread: nil,
                toolCard: memoToolCardSample()
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil,
                remoteImagePaths: ["/opt/data/img.png"]
            ),
            ChatEntry(
                role: "assistant",
                content: "[[deliver:dlv_memo_1]]",
                thread: nil
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil, traceKey: "trace-memo",
                traceSnapshot: TraceEchoSnapshot(
                    headline: "Hermes 已完成检索",
                    targetLabel: "会话甲",
                    openableSessionID: nil,
                    outcome: "找到 3 条结果",
                    isFailed: false
                )
            ),
            ChatEntry(
                role: "assistant",
                content: "目标进度已更新",
                thread: nil, echoKey: "goal-memo"
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil,
                approvalKey: "wg:skills:rec-memo-1"
            ),
        ]
    }

    private func heights(
        of entries: [ChatEntry],
        composer: ChatNativeRowHeightComposer
    ) -> [CGFloat] {
        entries.map {
            composer.entryHeight($0, dividerText: nil)
        }
    }

    /// 预填一趟后（每行恰实算一次），其后每趟以
    /// 新建合成器重算（镜像 ChatView.nativeRows
    /// 每趟现建合成器的生产口径）实算增量恒 0、
    /// 高度逐值不变——滚动期不再每趟重算整行高
    func testRowMemoHitsAcrossPassesWithFreshComposers() {
        let entries = memoFacetEntries()
        ChatNativeRowHeightComposer
            .resetRowComputationCount()
        let first = heights(
            of: entries, composer: makeComposer()
        )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            entries.count,
            "首趟每行恰实算一次"
        )
        for pass in 1...5 {
            let again = heights(
                of: entries, composer: makeComposer()
            )
            XCTAssertEqual(
                again, first,
                "第 \(pass) 趟高度须逐值不变"
            )
            XCTAssertEqual(
                ChatNativeRowHeightComposer
                    .rowComputationCount,
                entries.count,
                "第 \(pass) 趟须全命中、零实算"
            )
        }
    }

    /// 245 行形态（长会话量级）：预填后连过十趟
    /// 实算增量恒 0
    func testRowMemoScalesToLongConversation() {
        var entries: [ChatEntry] = []
        while entries.count < 245 {
            entries.append(contentsOf: memoFacetEntries())
        }
        entries = Array(entries.prefix(245))
        ChatNativeRowHeightComposer
            .resetRowComputationCount()
        let first = heights(
            of: entries, composer: makeComposer()
        )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            entries.count,
            "245 行预填每行恰实算一次"
        )
        for _ in 1...10 {
            let again = heights(
                of: entries, composer: makeComposer()
            )
            XCTAssertEqual(again, first)
        }
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            entries.count,
            "十趟滚动模拟须零新增实算"
        )
    }

    /// 账本翻转只失效其行：工具条目展开覆盖翻转
    /// →该行恰重算一次且高变（展开更高）；未翻转
    /// 的合成器口径仍命中旧值；工具组同口径
    func testRowMemoInvalidatesOnlyOnLedgerFlip() {
        let card = memoToolCardSample()
        guard
            let toolEntry = memoFacetEntries().first(
                where: { $0.toolCard != nil }
            )
        else {
            XCTFail("行集须含工具条目")
            return
        }
        let collapsedLedger = ChatRowStateLedger()
        let expandedLedger = ChatRowStateLedger()
        expandedLedger.setExpansion(
            true,
            for: ChatRowStateKeys.toolEntry(
                toolEntry.id
            )
        )
        ChatNativeRowHeightComposer
            .resetRowComputationCount()
        let collapsed = makeComposer(
            ledger: collapsedLedger
        ).entryHeight(toolEntry, dividerText: nil)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount, 1
        )
        let expanded = makeComposer(
            ledger: expandedLedger
        ).entryHeight(toolEntry, dividerText: nil)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount, 2,
            "翻转后该行恰重算一次"
        )
        XCTAssertGreaterThan(
            expanded, collapsed, "展开态须更高"
        )
        let collapsedAgain = makeComposer(
            ledger: collapsedLedger
        ).entryHeight(toolEntry, dividerText: nil)
        XCTAssertEqual(collapsedAgain, collapsed)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount, 2,
            "未翻转口径仍命中、不重算"
        )
        // 工具组：同卡同组键，组展开覆盖翻转同理
        let groupKey = "tg-memo"
        let groupLedger = ChatRowStateLedger()
        let groupCollapsed = makeComposer(
            ledger: groupLedger
        ).toolGroupHeight(cards: [card], groupKey: groupKey)
        let groupCountAfterFirst =
            ChatNativeRowHeightComposer
                .rowComputationCount
        let groupAgain = makeComposer(
            ledger: groupLedger
        ).toolGroupHeight(cards: [card], groupKey: groupKey)
        XCTAssertEqual(groupAgain, groupCollapsed)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            groupCountAfterFirst,
            "工具组未翻转须命中"
        )
        groupLedger.setExpansion(true, for: groupKey)
        _ = makeComposer(ledger: groupLedger)
            .toolGroupHeight(
                cards: [card], groupKey: groupKey
            )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            groupCountAfterFirst + 1,
            "工具组翻转后恰重算一次"
        )
    }

    /// 流式两行（思考/正文）同口径：同文同态重复
    /// 求值命中、零实算
    func testLiveRowsMemoized() {
        ChatNativeRowHeightComposer
            .resetRowComputationCount()
        let reasoning = makeComposer()
            .liveReasoningHeight(
                text: "正在整理思路……",
                contentStarted: false
            )
        let text = makeComposer().liveTextHeight(
            text: "第一批文字已经到达。",
            isUploading: false
        )
        let afterFirst =
            ChatNativeRowHeightComposer
                .rowComputationCount
        XCTAssertEqual(
            makeComposer().liveReasoningHeight(
                text: "正在整理思路……",
                contentStarted: false
            ),
            reasoning
        )
        XCTAssertEqual(
            makeComposer().liveTextHeight(
                text: "第一批文字已经到达。",
                isUploading: false
            ),
            text
        )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            afterFirst,
            "流式行同文同态须命中"
        )
    }
}
