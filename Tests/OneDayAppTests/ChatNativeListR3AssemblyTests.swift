import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §325（B 档退役）单渲染路径装配回归——本文件
/// 前身为 R3 原生散文 cell 装配（⑪双形态对拍／
/// ⑫原生 cell 本体／⑬混合行集间距）：双 cell 形
/// 态整套退役后三例的断言对象不复存在，随形态
/// 一并退役；本文件改守 B 档验收门（类名沿用、
/// CI 对账不断链）：
/// ⑪′单路径结构断言——含散文/引用/结构段的落
/// 定行全体物化为同一种托管 cell（reuseID 单
/// 一），facet 只影响行内呈现、不决定 cell 类；
/// ⑫′多遍 apply 稳定性——同段对话同修订连过三
/// 遍 apply：帧逐值不动、间隙恒 24±1；一行动修
/// 订（正文变长）后只有该行高生长、其余行高逐
/// 值不变、间隙仍 24±1（无可见高度跳变的结构
/// 证据，代旧「滚动多遍」盲区）；
/// ⑬′修订值结构化派生——ChatNativeRowRevision
/// .entry 对条目全字段敏感：remoteFilePathsData
/// （§320 病灶字段）/正文/发送态任一变修订必
/// 变，全同则逐值相等；环境侧（分隔/点亮/样式
/// 键）同入账；
/// ⑭′键盘引导线重验（新宿主结构）——通知帧顶
/// 驱动舱落位成立的同时，keyboardLayoutGuide
/// 在本宿主（SwiftUI 托管内嵌）仍停静息值、不
/// 追踪通知帧：引导线换代不成立的模拟器结构证
/// 据（真机终验归用户清单），kbSnapshot 分发
/// 层据此不退役（见 §325 报告）。
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

    // MARK: - 真实行内容（生产视图、非占位）

    private func hostedRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(
                parts: [.text(text)]
            ),
            makeView: {
                AnyView(
                    MarkdownText(text)
                        .padding(
                            .horizontal,
                            OneDayMetrics.bubblePaddingH
                        )
                        .padding(
                            .vertical,
                            OneDayMetrics.bubblePaddingV
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                )
            }
        )
    }

    // MARK: - ⑪′ 全体行单形态（托管 cell 单一 reuseID）

    func testAllRowsMaterializeAsHostingCells() throws {
        assemble()
        let rows = [
            hostedRow(
                "r1",
                "普通散文一行——R3 时代这类行会下沉原生 cell。"
            ),
            hostedRow(
                "r2",
                "带引用的回复。\n\n> 引用一行，facet 在席。\n\n引用之后再接一段正文收尾。"
            ),
            hostedRow(
                "r3",
                "带结构段的回复。\n\n```swift\nlet x = 1\n```\n\n代码块之后还有正文。"
            ),
            hostedRow("r4", "最后一条短回复。"),
        ]
        apply(rows: rows)
        drain()
        for index in rows.indices {
            let itemCell = try XCTUnwrap(
                cell(at: index),
                "行 \(index) 须物化出 cell"
            )
            XCTAssertEqual(
                itemCell.reuseIdentifier,
                "ChatNativeHostingCell",
                "行 \(index) 须为唯一托管形态（单渲染路径），实得 \(String(describing: itemCell.reuseIdentifier))"
            )
            XCTAssertGreaterThan(
                try frame(at: index).height, 30,
                "行 \(index) 高须来自真实排版"
            )
        }
    }

    // MARK: - ⑫′ 多遍 apply：间隙恒定＋未变行帧稳定

    func testMultiPassApplyKeepsSpacingAndStableFrames()
        throws
    {
        assemble()
        let base = [
            hostedRow("m1", "第一条助手回复，内容不长。"),
            hostedRow("m2", "第二条，长度中等的一行回复。"),
            hostedRow("m3", "第三条收尾。"),
        ]
        apply(rows: base)
        drain()
        var firstFrames: [CGRect] = []
        for index in base.indices {
            firstFrames.append(try frame(at: index))
        }
        // 同修订连过两遍：帧逐值不动（无重配、无跳变）
        for _ in 0..<2 {
            apply(rows: base)
            drain(0.6)
            for index in base.indices {
                let now = try frame(at: index)
                XCTAssertEqual(
                    now, firstFrames[index],
                    "同修订重过 apply 后行 \(index) 帧须逐值不变，\(firstFrames[index]) → \(now)"
                )
            }
        }
        // 中间行正文变长（修订随之变）：只有该行生长
        let grown = [
            base[0],
            hostedRow(
                "m2",
                "第二条，长度中等的一行回复。\n\n现在它多了一整段：多遍 apply 之后行高收敛只许发生在真正变了的行身上，未变的行帧若跟着漂移，就是用户在 .65 真机上看到的间隙异常那一族。"
            ),
            base[2],
        ]
        apply(rows: grown)
        drain()
        let grownFrame1 = try frame(at: 1)
        XCTAssertGreaterThan(
            grownFrame1.height, firstFrames[1].height + 20,
            "变长行须按新内容生长，\(firstFrames[1].height) → \(grownFrame1.height)"
        )
        XCTAssertEqual(
            try frame(at: 0).height, firstFrames[0].height,
            accuracy: 0.5,
            "未变行（首行）高不许随邻行变化漂移"
        )
        XCTAssertEqual(
            try frame(at: 2).height, firstFrames[2].height,
            accuracy: 0.5,
            "未变行（末行）高不许随邻行变化漂移"
        )
        for index in 0..<(grown.count - 1) {
            let gap = try frame(at: index + 1).minY
                - frame(at: index).maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 2.0,
                "多遍 apply 后行 \(index)→\(index + 1) 间隙须 24±2，实测 \(gap)"
            )
        }
    }

    // MARK: - ⑬′ 修订值结构化派生（全字段敏感）

    func testEntryRevisionDerivedFromAllModelFields()
        throws
    {
        let entry = ChatEntry(
            role: "user", content: "能不能看到", thread: nil
        )
        func revision() -> ChatNativeRowRevision {
            ChatNativeRowRevision.entry(
                entry,
                dividerText: nil,
                highlighted: false,
                selectionActive: false,
                styleKey: "style-a"
            )
        }
        let base = revision()
        XCTAssertEqual(
            base, revision(),
            "同条目同环境连算两遍修订须逐值相等（派生确定性）"
        )
        // §320 病灶字段：文件回填落盘
        entry.remoteFilePathsData =
            try JSONEncoder().encode(["/opt/data/a.xlsx"])
        XCTAssertNotEqual(
            base, revision(),
            "remoteFilePathsData 变（文件回填）修订必须变——手折哈希漏折此项即 §320 病灶"
        )
        let withFile = revision()
        // 正文变
        entry.content = "能不能看到这个文件"
        XCTAssertNotEqual(withFile, revision())
        // 发送态变
        entry.sendFailed = true
        XCTAssertNotEqual(withFile, revision())
        // 环境侧：分隔/点亮/样式键任一变
        let envChanged = ChatNativeRowRevision.entry(
            entry,
            dividerText: "今天 09:41",
            highlighted: false,
            selectionActive: false,
            styleKey: "style-a"
        )
        XCTAssertNotEqual(revision(), envChanged)
        let styleChanged = ChatNativeRowRevision.entry(
            entry,
            dividerText: nil,
            highlighted: false,
            selectionActive: false,
            styleKey: "style-b"
        )
        XCTAssertNotEqual(revision(), styleChanged)
    }

    // MARK: - ⑭′ 引导线重验：通知驱动成立、引导线不追踪

    func testKeyboardGuideDoesNotTrackOnCurrentHost()
        throws
    {
        assemble()
        apply(rows: [hostedRow("only", "只有一条短回复。")])
        drain()
        let guideAtRest = try XCTUnwrap(
            controller.testKeyboardGuideTopInWindow,
            "入窗后引导线采样须有值"
        )
        // 投递生产驱动本体（willShow＋帧顶 545＋时长 0）
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: CGRect(
                        x: 0, y: 545, width: windowW,
                        height: windowH - 545
                    )),
                UIResponder.keyboardAnimationDurationUserInfoKey:
                    NSNumber(value: 0),
                UIResponder.keyboardAnimationCurveUserInfoKey:
                    NSNumber(value: 7),
            ]
        )
        window.layoutIfNeeded()
        drain(0.6)
        // 通知路成立：舱底＝帧顶 545（舱顶 491）
        let host = try XCTUnwrap(
            controller.composerHost, "舱子托管应已装配"
        )
        let composerBottom = host.view.convert(
            host.view.bounds, to: nil
        ).maxY
        XCTAssertEqual(
            composerBottom, 545, accuracy: 1.0,
            "通知帧顶须驱动舱底＝545（§302 路成立），实测 \(composerBottom)"
        )
        // 引导线不追踪：仍停静息值、与帧顶 545 无关
        let guideAfter = try XCTUnwrap(
            controller.testKeyboardGuideTopInWindow
        )
        XCTAssertEqual(
            guideAfter, guideAtRest, accuracy: 0.5,
            "引导线在本宿主仍停静息值（不追踪）——重验不成立的结构证据，实测 \(guideAtRest) → \(guideAfter)"
        )
        XCTAssertGreaterThan(
            abs(guideAfter - 545), 100,
            "引导线位置须与通知帧顶显著无关，实测 \(guideAfter)"
        )
    }
}
