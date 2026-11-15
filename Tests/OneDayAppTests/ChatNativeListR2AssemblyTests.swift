import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §292（原生重建 R2）原生承载真实装配回归（续
/// R1 装配壳、同窗同座）：行内容全是真实生产视
/// 图（MarkdownText／ToolCardView／Streaming-
/// BlockText），禁用固定高占位行作证据：
/// ⑦直播区逐项入快照——思考/工具/封存段/打开段
/// 各自独立 item、帧序与间距单源 24（施工图
/// §3.1 #9–11）；
/// ⑧块闭合单渲染（H4 的机器判据，蓝图 §6.2
/// ⑤）：93 事故原文（4640 段 A／4643 段 B＋工
/// 具边界）按确定性序列注入——闭合前 A 只在打
/// 开段 item 的渲染树、封段后 A 只在封存段
/// item、B 只在打开段 item，任一段文字在任一帧
/// 只出现在一个 item 内；
/// ⑨键盘换代装配（H8）：舱子托管底边＝容器
/// keyboardLayoutGuide 顶（同坐标系直读）、底
/// inset＝舱实测帧派生（帧底−舱顶＋边距）、引
/// 导线顶起 60 后舱随行/inset 同步 +60/短内容
/// 间距仍 24；
/// ⑩流式跟随：跟随命令（生产链同口）后打开段
/// 逐拍生长，距底恒达标、末行→舱顶恒 24——落
/// 点只认真实布局、收敛后钉底（H6）。
@MainActor
final class ChatNativeListR2AssemblyTests: XCTestCase {

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874
    private let composerHeight: CGFloat = 54
    private let fedTopInset: CGFloat = 122
    private let bottomMargin: CGFloat = 16
    private let bottomPadding: CGFloat = 8
    private let targetGap: CGFloat = 24

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

    private func composerContent() -> AnyView {
        AnyView(
            Rectangle()
                .fill(Color.gray)
                .frame(height: composerHeight)
        )
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
            composerView: composerContent(),
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

    private func composerTopInWindow() throws -> CGFloat {
        let host = try XCTUnwrap(
            controller.composerHost,
            "舱子托管应已装配"
        )
        return host.view.convert(
            host.view.bounds, to: nil
        ).minY
    }

    // MARK: - 真实行内容（生产视图、非占位）

    private func bubble<Content: View>(
        _ content: Content
    ) -> AnyView {
        AnyView(
            content
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

    private func settledRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil, version: 1,
            estimatedHeight: 80,
            makeView: { self.bubble(MarkdownText(text)) }
        )
    }

    private func streamRow(
        _ key: String, _ text: String, version: Int
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil, version: version,
            estimatedHeight: 120,
            makeView: {
                self.bubble(StreamingBlockText(text: text))
            }
        )
    }

    private func toolRow() -> ChatNativeRow {
        let card = ToolCard(
            id: "tool-colorize-1",
            toolName: "colorize_image",
            category: .vision,
            title: "彩色化图片",
            summary: "photo.png",
            result: "已生成彩色化结果",
            resultFailed: false
        )
        return ChatNativeRow(
            key: "live-tool-colorize-1",
            entryID: nil, version: 1,
            estimatedHeight: 96,
            makeView: { AnyView(ToolCardView(card: card)) }
        )
    }

    // MARK: - 无障碍渲染树文本采集（⑧判据面）

    /// 递归采集一棵视图树里全部可达文本：无障碍
    /// 标签（SwiftUI 元素经托管树的 accessibility-
    /// Elements 递出）＋平台文本视图/标签的正文。
    /// 第一轮 CI 实证：UIHostingConfiguration 的
    /// SwiftUI 内容只经 accessibilityElements 数组
    /// 采集时递不出（托管视图的元素经 UIAccessi-
    /// bilityContainer 协议按需生成）——故并行走
    /// 容器协议通道（accessibilityElementCount／
    /// at:），这是 AX 运行时自身的取数口；两通道
    /// 并集后按 cell 拼成整串再查标记（词元级标
    /// 签被切开时拼接后仍可命中，排除断言的误报
    /// 面只限「标记字符恰按序跨元素相邻」——对
    /// 本测试的判别标记 DeOldify／colorize.cc
    /// 而言即真渲染在场）
    private func renderTexts(in view: UIView) -> [String] {
        var out: [String] = []
        func walkElement(
            _ element: UIAccessibilityElement, depth: Int
        ) {
            if let label = element.accessibilityLabel,
               !label.isEmpty {
                out.append(label)
            }
            walkContainer(element, depth: depth + 1)
        }
        func walkContainer(_ object: Any, depth: Int) {
            guard depth <= 6,
                  let container = object
                    as? UIAccessibilityContainer
            else { return }
            let count = container
                .accessibilityElementCount()
            guard count > 0, count < 100_000 else {
                return
            }
            for index in 0..<count {
                guard let child = container
                    .accessibilityElement(at: index)
                else { continue }
                if let childView = child as? UIView {
                    walk(childView, depth: depth + 1)
                } else if let childElement = child
                    as? UIAccessibilityElement {
                    walkElement(
                        childElement, depth: depth + 1
                    )
                }
            }
        }
        func walk(_ object: Any, depth: Int = 0) {
            if let v = object as? UIView {
                if v.isAccessibilityElement,
                   let label = v.accessibilityLabel,
                   !label.isEmpty {
                    out.append(label)
                }
                if let textView = v as? UITextView {
                    if let text = textView.text,
                       !text.isEmpty {
                        out.append(text)
                    }
                    if let attributed =
                        textView.attributedText?.string,
                       !attributed.isEmpty {
                        out.append(attributed)
                    }
                }
                if let label = v as? UILabel,
                   let text = label.text, !text.isEmpty {
                    out.append(text)
                }
                if let elements = v.accessibilityElements {
                    elements.forEach {
                        walk($0, depth: depth + 1)
                    }
                }
                if !v.isAccessibilityElement {
                    walkContainer(v, depth: depth + 1)
                }
                v.subviews.forEach {
                    walk($0, depth: depth + 1)
                }
            } else if let element =
                        object as? UIAccessibilityElement {
                walkElement(element, depth: depth)
            }
        }
        walk(view)
        return out
    }

    /// 一个 cell 的全部可达文本拼成的整串
    private func renderText(in view: UIView) -> String {
        renderTexts(in: view).joined()
    }

    /// 含标记文本的可见 cell 数（同帧渲染树口径）
    private func cellsContaining(_ marker: String) -> Int {
        controller.collectionView.visibleCells.filter {
            cell in
            renderText(in: cell).contains(marker)
        }.count
    }

    // MARK: - ⑦ 直播逐项入快照

    func testLiveItemsOccupySeparateItems() throws {
        assemble()
        let rows = [
            settledRow("entry-1", "落定的一条助手回复。"),
            toolRow(),
            streamRow(
                "stream-u1#seg0",
                "封存段的内容，已经定稿不再变化。",
                version: 1
            ),
            streamRow(
                "stream-u1",
                "打开段正在生成，尾巴还在长。",
                version: 1
            ),
        ]
        apply(rows: rows)
        drain()
        let cv = controller.collectionView
        XCTAssertEqual(
            cv.numberOfItems(inSection: 0), rows.count,
            "直播逐项须各自成 item（非整段一块）"
        )
        var frames: [CGRect] = []
        for index in rows.indices {
            frames.append(try frame(at: index))
        }
        for index in rows.indices {
            XCTAssertGreaterThan(
                frames[index].height, 30,
                "行 \(index) 高度应来自真实排版而非占位"
            )
        }
        for index in 0..<(rows.count - 1) {
            let gap = frames[index + 1].minY
                - frames[index].maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 1.0,
                "直播 item \(index)→\(index + 1) 间距须＝单源 24，实测 \(gap)"
            )
        }
    }

    // MARK: - ⑧ 块闭合单渲染（93 原文回放）

    func testBlockClosureKeepsSegmentInExactlyOneItem() throws {
        assemble()
        // 93 事故原文（服务端落库定稿，见
        // stream-segment-carryover-20261115.md）：
        // A＝4640 段、B＝4643 段，中间隔一次工具调用
        let segmentA =
            "好，我换个更可靠的方式——用 Replicate 的公开 DeOldify 模型，不需要 API key 的那种，或者直接调一个免费的彩色化服务。"
        let segmentBPartial =
            "好，我直接用 colorize.cc 或 DeepAI 的免费接口，不需要注册。先试"
        let segmentB =
            "好，我直接用 colorize.cc 或 DeepAI 的免费接口，不需要注册。先试 DeepAI。"

        // 第一拍：A 已闭合、B 在尾块——同属打开段
        // 一个 item（A 只在该 item 的前缀渲染里）
        apply(rows: [
            streamRow(
                "stream-u1",
                segmentA + "\n\n" + segmentBPartial,
                version: 1
            ),
        ])
        drain()
        XCTAssertEqual(
            controller.collectionView
                .numberOfItems(inSection: 0),
            1,
            "闭合前须为打开段单 item（前缀＋尾块同 item 内分工）"
        )
        print(
            "R2-⑧ 第一拍渲染树："
                + controller.collectionView.visibleCells
                    .map { renderText(in: $0) }
                    .joined(separator: " | ")
        )
        XCTAssertEqual(
            cellsContaining("DeOldify"), 1,
            "闭合前 A 须只出现在打开段 item 一处渲染树"
        )
        XCTAssertEqual(
            cellsContaining("colorize.cc"), 1,
            "闭合前 B 须只出现在打开段 item 一处渲染树"
        )

        // 第二拍：工具边界封段——A 移入封存段
        // item、工具卡成 item、B 续写打开段 item。
        // 同帧互斥：A 只在封存段、B 只在打开段
        apply(rows: [
            streamRow(
                "stream-u1#seg0", segmentA, version: 1
            ),
            toolRow(),
            streamRow("stream-u1", segmentB, version: 2),
        ])
        drain()
        XCTAssertEqual(
            controller.collectionView
                .numberOfItems(inSection: 0),
            3,
            "封段后须为封存段/工具/打开段三 item"
        )
        XCTAssertEqual(
            cellsContaining("DeOldify"), 1,
            "封段后 A 须只出现在封存段 item 一处（同帧两份＝叠字构造形态）"
        )
        XCTAssertEqual(
            cellsContaining("colorize.cc"), 1,
            "封段后 B 须只出现在打开段 item 一处"
        )
        print(
            "R2-⑧ 第二拍渲染树："
                + controller.collectionView.visibleCells
                    .map { renderText(in: $0) }
                    .joined(separator: " | ")
        )
        // 互斥直证：封存段 cell 不含 B、打开段 cell
        // 不含 A
        let cells = controller.collectionView.visibleCells
        let sealedCell = try XCTUnwrap(
            cells.first {
                renderText(in: $0).contains("DeOldify")
            },
            "封存段 cell 须在场"
        )
        XCTAssertFalse(
            renderText(in: sealedCell)
                .contains("colorize.cc"),
            "封存段渲染树不许含打开段文字"
        )
        let tailCell = try XCTUnwrap(
            cells.first {
                renderText(in: $0).contains("colorize.cc")
            },
            "打开段 cell 须在场"
        )
        XCTAssertFalse(
            renderText(in: tailCell).contains("DeOldify"),
            "打开段渲染树不许残留已封段文字"
        )
    }

    // MARK: - ⑨ 键盘换代装配（H8）

    func testComposerGuidePinningAndDerivedInset() throws {
        assemble()
        let rows = [
            settledRow("only", "只有一条短回复的会话。")
        ]
        apply(rows: rows)
        drain()
        let host = try XCTUnwrap(
            controller.composerHost, "舱子托管应已装配"
        )
        let cv = controller.collectionView
        // 结构直证：舱底＝容器 keyboardLayoutGuide
        // 顶（同在容器视图坐标系、直读两帧）
        let guideTop = controller.view
            .keyboardLayoutGuide.layoutFrame.minY
        XCTAssertEqual(
            host.view.frame.maxY, guideTop, accuracy: 1.0,
            "舱底须钉 keyboardLayoutGuide 顶，舱底 "
                + "\(host.view.frame.maxY) vs 引导线顶 \(guideTop)"
        )
        // 派生直证：底 inset＝（列表帧底−舱顶）窗
        // 口实测＋单点边距，无第二来源
        let frameInWindow = controller.view.convert(
            controller.view.bounds, to: nil
        )
        let hostInWindow = host.view.convert(
            host.view.bounds, to: nil
        )
        let expected = frameInWindow.maxY
            - hostInWindow.minY + bottomMargin
        XCTAssertEqual(
            cv.contentInset.bottom, expected, accuracy: 1.0,
            "底 inset 须＝舱实测帧派生 \(expected)，实测 \(cv.contentInset.bottom)"
        )
        // 引导线顶起 60（附加安全区模拟键盘帧顶
        // 起）：舱随行同值、派生 inset 同步 +60、
        // 短内容末行→舱顶仍 24
        let insetBefore = cv.contentInset.bottom
        controller.additionalSafeAreaInsets.bottom += 60
        window.layoutIfNeeded()
        drain(0.6)
        XCTAssertEqual(
            host.view.frame.maxY,
            controller.view.keyboardLayoutGuide
                .layoutFrame.minY,
            accuracy: 1.0,
            "引导线顶起后舱底须仍钉其顶"
        )
        XCTAssertEqual(
            cv.contentInset.bottom, insetBefore + 60,
            accuracy: 1.5,
            "引导线顶起 60 后底 inset 须同步 +60，实测 \(cv.contentInset.bottom)"
        )
        let last = try frame(at: 0)
        let lastInWindow = cv.convert(last, to: nil)
        let gap = try composerTopInWindow()
            - lastInWindow.maxY
        XCTAssertEqual(
            gap, targetGap, accuracy: 1.0,
            "键盘等价位下末行底→舱顶须 24±1，实测 \(gap)"
        )
    }

    // MARK: - ⑩ 流式跟随钉底（H6）

    func testStreamingGrowthKeepsBottomPin() throws {
        assemble()
        let settled = settledRow(
            "u1", "帮我把这张老照片上色。"
        )
        let stages = [
            "好的，我先看一下照片内容。",
            "好的，我先看一下照片内容。\n\n照片里是一张全家福，背景是老屋的院子，人物衣着是七十年代的样式。",
            "好的，我先看一下照片内容。\n\n照片里是一张全家福，背景是老屋的院子，人物衣着是七十年代的样式。\n\n我先做一版温和的彩色化：肤色按自然暖调、衣着保留原布料的明暗关系、天空与院墙只做轻微提亮，避免把老照片修成新照片的质感。",
        ]
        for (index, text) in stages.enumerated() {
            // 跟随命令与生产链同口：流式增量经跟随
            // 闸放行后由 ChatView 下达贴底命令，本处
            // 以句柄命令同式复现其拍位
            if index > 0 {
                controller.scrollToBottom(animated: false)
            }
            apply(rows: [
                settled,
                streamRow(
                    "stream-u1", text, version: index + 1
                ),
            ])
            drain(1.0)
            XCTAssertLessThanOrEqual(
                handle.latestDistance, 2.5,
                "生长第 \(index + 1) 拍后距底须达标（收敛后钉底），实测 \(handle.latestDistance)"
            )
            let last = try frame(at: 1)
            let lastInWindow = controller.collectionView
                .convert(last, to: nil)
            let gap = try composerTopInWindow()
                - lastInWindow.maxY
            XCTAssertEqual(
                gap, targetGap, accuracy: 1.5,
                "生长第 \(index + 1) 拍后末行底→舱顶须 24，实测 \(gap)"
            )
        }
    }
}
