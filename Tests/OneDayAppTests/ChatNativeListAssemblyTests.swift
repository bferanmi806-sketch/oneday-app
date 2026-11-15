import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §291（原生重建 R1）原生承载真实装配回归：把
/// ChatRootViewController 装进与 ChatListCarrier-
/// BottomGapTests 同构的真壳（窗口→页面→承载全
/// 窗出血→坞/键盘座位＋输入舱托管＋83 变换歪
/// 斜），行内容全是真实生产视图（MarkdownText
/// 助手泡＋SelectableInlineText 用户泡＋分隔条
/// 目）——禁用固定高占位行作证据（蓝图 §七）：
/// ①相邻 cell 帧间距＝单源 24（H1）；②短内容双
/// 键盘态末行底→舱顶＝24、落位只由 apply 链自产
/// （H3/H6）；③长会话进入即真底三数留档（con-
/// tentSize/offset/末行帧）＋距底 ≤1——顺带回填
/// 冒烟箭头例「开线程落底」的帧级定因（旧面 AX
/// 口径离底 vs 本面帧口径）；④程序化跳中段后距
/// 底读数与锚一致（H7 现测）；⑤托管高度与裸宿
/// 主（safeAreaRegions 清零）等价（H2 回退门）；
/// ⑥产物估算与 cell 实高带宽（H10）。
@MainActor
final class ChatNativeListAssemblyTests: XCTestCase {

    // MARK: - 真壳（与 BottomGapTests 同构）

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874
    private let dockHeight: CGFloat = 83
    private let keyboardTop: CGFloat = 545
    private let composerHeight: CGFloat = 54
    private let composerSkew: CGFloat = 83
    private let fedTopInset: CGFloat = 122
    private let bottomMargin: CGFloat = 16
    private let bottomPadding: CGFloat = 8
    private let targetGap: CGFloat = 24

    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!
    private var composerBar: UIView!
    private var composerBottom: NSLayoutConstraint!
    private var composerBottomOnKeyboard: NSLayoutConstraint!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        composerBar = nil
        super.tearDown()
    }

    /// 装壳：窗口→根→承载（全窗出血、topInset 喂
    /// 122）＋坞/键盘座位＋输入舱托管（变换歪斜
    /// 83，与真机同式）
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

        let dock = UIView()
        dock.backgroundColor = .systemGray5
        dock.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(dock)
        NSLayoutConstraint.activate([
            dock.leadingAnchor.constraint(
                equalTo: root.view.leadingAnchor
            ),
            dock.trailingAnchor.constraint(
                equalTo: root.view.trailingAnchor
            ),
            dock.bottomAnchor.constraint(
                equalTo: root.view.bottomAnchor
            ),
            dock.heightAnchor.constraint(
                equalToConstant: dockHeight
            ),
        ])

        composerBar = UIView()
        composerBar.backgroundColor = .systemGray4
        composerBar.translatesAutoresizingMaskIntoConstraints =
            false
        root.view.addSubview(composerBar)
        composerBottom = composerBar.bottomAnchor.constraint(
            equalTo: root.view.bottomAnchor,
            constant: -dockHeight + composerSkew
        )
        composerBottomOnKeyboard = composerBar.bottomAnchor
            .constraint(
                equalTo: root.view.topAnchor,
                constant: keyboardTop + composerHeight
                    + composerSkew
            )
        NSLayoutConstraint.activate([
            composerBar.leadingAnchor.constraint(
                equalTo: root.view.leadingAnchor
            ),
            composerBar.trailingAnchor.constraint(
                equalTo: root.view.trailingAnchor
            ),
            composerBar.heightAnchor.constraint(
                equalToConstant: composerHeight
            ),
            composerBottom,
        ])
        root.view.layoutIfNeeded()
    }

    /// 舱落座（false＝坞上、true＝键盘顶）＋回喂
    /// 入两数（舱顶窗口实测与回落空间，与生产链
    /// 同口：composerTopInWindow＝窗口高−舱底空
    /// 间、fallback＝座位顶起算＋舱高）
    private func seatComposer(onKeyboard: Bool) -> (
        top: CGFloat, fallback: CGFloat
    ) {
        composerBottom.isActive = !onKeyboard
        composerBottomOnKeyboard.isActive = onKeyboard
        window.layoutIfNeeded()
        let frameInWindow = composerBar.convert(
            composerBar.bounds, to: nil
        )
        let fallback = (
            windowH - (onKeyboard ? keyboardTop : windowH - dockHeight)
        ) + composerHeight
        return (frameInWindow.minY, fallback)
    }

    private func apply(
        rows: [ChatNativeRow], onKeyboard: Bool = false
    ) {
        let seat = seatComposer(onKeyboard: onKeyboard)
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
            composerTopInWindow: seat.top,
            fallbackBottomSpace: seat.fallback,
            bottomMargin: bottomMargin,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0,
            arrowView: AnyView(Color.clear)
        )
    }

    private func drain(_ seconds: TimeInterval = 1.2) {
        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window.layoutIfNeeded()
    }

    /// async 测试专用排空：expectation 的 wait 在
    /// async 测试里会堵住主队列（CI 第四轮实证：
    /// drain 超时而后续断言本身全过）——改以
    /// Task.sleep 挂起等拍，主队列照常跑落定拍
    private func drainAsync(
        _ seconds: TimeInterval = 1.2
    ) async {
        try? await Task.sleep(for: .seconds(seconds))
        window.layoutIfNeeded()
    }

    private func frame(at index: Int) throws -> CGRect {
        let attrs = controller.collectionView
            .layoutAttributesForItem(
                at: IndexPath(item: index, section: 0)
            )
        return try XCTUnwrap(attrs).frame
    }

    // MARK: - 真实行内容（生产视图、非占位）

    private func assistantContent(_ text: String) -> AnyView {
        AnyView(
            MarkdownText(text)
                .padding(
                    .horizontal, OneDayMetrics.bubblePaddingH
                )
                .padding(
                    .vertical, OneDayMetrics.bubblePaddingV
                )
                .background(
                    RoundedRectangle(
                        cornerRadius:
                            OneDayMetrics.assistantBubbleCorner
                    )
                    .fill(Palette.bubbleFill)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    private func assistantRow(
        _ key: String, _ text: String, entryID: UUID? = nil
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: entryID, version: 1,
            estimatedHeight: 80,
            makeView: { self.assistantContent(text) }
        )
    }

    private func userRow(
        _ key: String, _ text: String, entryID: UUID? = nil
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: entryID, version: 1,
            estimatedHeight: 80,
            makeView: {
                AnyView(
                    HStack {
                        Spacer(
                            minLength:
                                OneDayMetrics.bubbleSideInset
                        )
                        SelectableInlineText(
                            paragraphs: [.plain(text)],
                            foreground: Palette.onPrimary
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
                                    .assistantBubbleCorner
                            )
                            .fill(Palette.primary)
                        )
                    }
                )
            }
        )
    }

    /// 带时间分隔的条目行（与 entryRowContent 同
    /// 构：VStack(spacingS)｛分隔字＋气泡｝）
    private func dividerRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil, version: 1,
            estimatedHeight: 110,
            makeView: {
                AnyView(
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingS
                    ) {
                        Text("今天 09:41")
                            .font(.footnote)
                            .foregroundStyle(
                                Palette.inkSecondary
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .center
                            )
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
                    }
                )
            }
        )
    }

    // MARK: - ① 相邻行距单源 24

    func testAdjacentRealRowsKeepSingleSourceSpacing() throws {
        assemble()
        let rows = [
            assistantRow("a1", "第一条助手短回复。"),
            userRow("u1", "收到，这是一条用户短消息。"),
            dividerRow("d1", "带分隔的助手回复，内容稍长一点点。"),
            userRow(
                "u2",
                "最后一条用户消息，长度中等，用来收尾这一组四行。"
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
                "行 \(index) 高度应来自真实文本排版而非占位"
            )
        }
        for index in 0..<(rows.count - 1) {
            let gap = frames[index + 1].minY - frames[index].maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 1.0,
                "相邻行 \(index)→\(index + 1) 帧间距须＝单源 24，实测 \(gap)"
            )
        }
    }

    // MARK: - ② 短内容双键盘态

    func testShortContentGapKeyboardClosedAndOpen() throws {
        assemble()
        let rows = [assistantRow("only", "只有一条短回复的会话。")]
        apply(rows: rows, onKeyboard: false)
        drain()
        try assertShortGap(rows: rows, label: "键盘收起")
        apply(rows: rows, onKeyboard: true)
        drain()
        try assertShortGap(rows: rows, label: "键盘升起")
    }

    func testShortContentThreeRowsGap() throws {
        assemble()
        let rows = [
            assistantRow("s1", "三行短会话的第一行。"),
            userRow("s2", "第二行用户回复。"),
            assistantRow("s3", "第三行助手收尾。"),
        ]
        apply(rows: rows, onKeyboard: false)
        drain()
        try assertShortGap(rows: rows, label: "三行短会话")
    }

    /// 短内容断言：末行底（窗口坐标）→舱顶（窗
    /// 口实测）＝24±1；落位只由 apply 链自产（测
    /// 试全程不调任何滚动 API）
    private func assertShortGap(
        rows: [ChatNativeRow], label: String
    ) throws {
        let last = try frame(at: rows.count - 1)
        let lastInWindow = controller.collectionView.convert(
            last, to: nil
        )
        let composerTop = composerBar.convert(
            composerBar.bounds, to: nil
        ).minY
        let gap = composerTop - lastInWindow.maxY
        XCTAssertEqual(
            gap, targetGap, accuracy: 1.0,
            "\(label)：末行底→舱顶须 24±1，实测 \(gap)"
                + "（末行帧 \(last)、contentSize "
                + "\(controller.collectionView.contentSize)、"
                + "顶 inset "
                + "\(controller.collectionView.contentInset.top)）"
        )
    }

    // MARK: - ③ 长会话进入即真底（三数留档）

    func testLongThreadLandsAtRealBottom() throws {
        assemble()
        var rows: [ChatNativeRow] = []
        for index in 0..<40 {
            let long = index % 5 == 4
            let text = long
                ? "第 \(index + 1) 条是一段较长的回复：原生承载用系统集合视图与组合布局，行高由内容自适应决定，滚动几何只认布局实测——这一段故意写长，好让行高明显超过占位估算，检验落定拍在估算收敛后仍把末行钉到真底。"
                : "第 \(index + 1) 条短回复。"
            rows.append(
                index % 2 == 0
                    ? assistantRow(
                        "long-\(index)", text,
                        entryID: UUID()
                    )
                    : userRow(
                        "long-\(index)", text,
                        entryID: UUID()
                    )
            )
        }
        apply(rows: rows)
        drain(1.6)
        let cv = controller.collectionView
        let lastFrame = try frame(at: rows.count - 1)
        let distance = handle.latestDistance
        // 三数留档（CI 日志可查，报告回填）
        print(
            "NATIVE-LANDING contentSize=\(cv.contentSize.height)"
                + " offset=\(cv.contentOffset.y)"
                + " lastFrame=\(lastFrame)"
                + " bottomInset=\(handle.bottomInset)"
                + " distance=\(distance)"
                + " contentEndVisible=\(handle.contentEndVisible)"
        )
        XCTAssertLessThanOrEqual(
            distance, 1.0,
            "长会话进入距底须 ≤1（真实布局最大 offset），实测 \(distance)"
        )
        XCTAssertTrue(
            handle.contentEndVisible,
            "落底时内容真尾须在视口内（帧口径，非 AX 在场口径）"
        )
        // 末行底在窗口坐标下与舱顶的间距同样收 24
        // （长内容钉底与短内容派生顶 inset 两路同
        // 一口径）
        let lastInWindow = cv.convert(lastFrame, to: nil)
        let composerTop = composerBar.convert(
            composerBar.bounds, to: nil
        ).minY
        XCTAssertEqual(
            composerTop - lastInWindow.maxY, targetGap,
            accuracy: 1.5,
            "长会话钉底后末行底→舱顶须 24，实测 "
                + "\(composerTop - lastInWindow.maxY)"
        )
    }

    // MARK: - ④ 跳中段：距底现测＋锚一致

    func testMiddleJumpDistanceAndAnchorAgree() throws {
        assemble()
        var rows: [ChatNativeRow] = []
        var entryIDs: [UUID] = []
        for index in 0..<30 {
            let id = UUID()
            entryIDs.append(id)
            rows.append(
                assistantRow(
                    "mid-\(index)",
                    "中段检验第 \(index + 1) 条回复，内容长度适中。",
                    entryID: id
                )
            )
        }
        apply(rows: rows)
        drain(1.6)
        let cv = controller.collectionView
        // 程序化跳到中段（模拟用户滚离底部）
        cv.setContentOffset(
            CGPoint(x: 0, y: cv.contentSize.height / 2),
            animated: false
        )
        drain(0.8)
        let distance = handle.latestDistance
        XCTAssertGreaterThan(
            distance, 176,
            "跳中段后距底读数须现测为大值，实测 \(distance)"
        )
        let anchor = controller.captureAnchor()
        let unwrapped = try XCTUnwrap(
            anchor, "中段应能捕获恢复锚"
        )
        XCTAssertFalse(unwrapped.atBottom)
        // 期望锚条目＝帧口径第一个底边越过可见顶
        // 的条目行
        let visibleTop = cv.contentOffset.y
            + cv.contentInset.top
        var expected: UUID?
        for index in rows.indices {
            if try frame(at: index).maxY > visibleTop + 0.5 {
                expected = entryIDs[index]
                break
            }
        }
        XCTAssertEqual(
            unwrapped.entryID, expected,
            "锚条目须与帧口径首个可见条目一致"
        )
        // 回底命令后读数复位
        controller.scrollToBottom(animated: false)
        drain(1.0)
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 1.0,
            "回底后距底须 ≤1，实测 \(handle.latestDistance)"
        )
    }

    // MARK: - ⑤ 托管高度等价（H2 回退门）

    func testHostingHeightMatchesBareHost() throws {
        assemble()
        let text =
            "托管等价检验：同一段多行正文，在集合视图 cell 里经 UIHostingConfiguration 托管的高度，必须与裸 UIHostingController（宿主 safeAreaRegions 清零）在同宽下的自适应高度一致——若本断言红，说明配置式托管的拟合被安全区抬高，R1 按施工图回退 keyed 托管控制器方案。"
        let rows = [assistantRow("host-eq", text)]
        apply(rows: rows)
        drain()
        let cellHeight = try frame(at: 0).height

        let rowWidth = windowW
            - OneDayMetrics.pageGutter * 2
        let bare = UIHostingController(
            rootView: assistantContent(text)
        )
        bare.safeAreaRegions = []
        let bareWindow = UIWindow(
            frame: CGRect(
                x: 0, y: -2000, width: windowW, height: 400
            )
        )
        bareWindow.rootViewController = bare
        bareWindow.makeKeyAndVisible()
        bare.view.frame = CGRect(
            x: 0, y: 0, width: rowWidth, height: 400
        )
        bare.view.layoutIfNeeded()
        let bareHeight = bare.sizeThatFits(
            in: CGSize(
                width: rowWidth,
                height: .greatestFiniteMagnitude
            )
        ).height
        bareWindow.isHidden = true
        XCTAssertEqual(
            cellHeight, bareHeight, accuracy: 1.5,
            "cell 高 \(cellHeight) 与裸宿主高 \(bareHeight) 须等价（差 >1.5 触发 H2 回退）"
        )
    }

    // MARK: - ⑥ 产物估算带宽（H10）

    func testProductEstimateWithinBand() async throws {
        assemble()
        let text = """
            产物带宽检验第一段：排版产物在量测池里按真实字体与段落规格量出文本总高，行高模型再叠上气泡内边距组合成整行估算。

            第二段故意长一些，用来让文本在给定列宽下折成多行：集合视图 cell 的实高来自同一段正文的真实排版，两者之比应落进蓝图给定的带宽，而不是靠帧表或写死高度蒙混。

            第三段收尾。
            """
        let rows = [assistantRow("band", text)]
        apply(rows: rows)
        await drainAsync()
        let cellHeight = try frame(at: 0).height

        let textWidth = windowW
            - OneDayMetrics.pageGutter * 2
            - OneDayMetrics.bubblePaddingH * 2
        let style = LayoutStyleContext(
            sizeCategory: .large, boldText: false
        )
        let product = await LayoutProductService.shared
            .product(
                entryID: UUID(),
                renderedText: text,
                isUser: false,
                width: textWidth,
                style: style
            )
        let unwrapped = try XCTUnwrap(product, "产物应能现产")
        let lineFloor = InlineTextFonts.specLineHeight(
            textStyle: .body,
            category: .large,
            boldText: false
        )
        let dividerHeight = UIFont.preferredFont(
            forTextStyle: .footnote,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: .large
            )
        ).lineHeight
        let estimate = CGFloat(
            ChatRowHeightModel.rowHeight(
                ChatRowHeightModel.Input(
                    textTotalHeight: Double(
                        unwrapped.textTotalHeight
                    ),
                    textSegmentCount: unwrapped.segments.count,
                    structuralSegmentCount:
                        unwrapped.structuralSegmentCount,
                    measuredContentHeight: nil,
                    hasDivider: false,
                    bubblePaddingV: Double(
                        OneDayMetrics.bubblePaddingV
                    ),
                    segmentSpacing: Double(
                        OneDayMetrics.spacingS
                    ),
                    dividerHeight: Double(dividerHeight),
                    dividerSpacing: Double(
                        OneDayMetrics.spacingS
                    ),
                    lineHeightFloor: Double(lineFloor),
                    provisionalHeight: 56
                )
            )
        )
        let ratio = estimate / cellHeight
        print(
            "NATIVE-BAND estimate=\(estimate) cell=\(cellHeight) ratio=\(ratio)"
        )
        XCTAssertTrue(
            (0.55...1.8).contains(ratio),
            "产物估算/实高比须 ∈ [0.55, 1.8]，实测 \(ratio)"
        )
    }
}
