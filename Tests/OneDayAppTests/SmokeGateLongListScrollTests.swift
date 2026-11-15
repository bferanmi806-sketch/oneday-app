import Foundation
import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import OneDayApp

/// 出厂冒烟门·长会话回底（横扫 C 类「懒生成回底黑闪」
/// 的机器可验部分）：120 行长会话滚动到顶→回底箭头出
/// 现→无障碍激活真触发滚动→断言落点贴底且末行真渲染
/// 在可见区（空白帧＝末行不在树里或不在可见框内，断言
/// 即红）。黑闪是逐帧视觉现象，机器只能验「落点＋末行
/// 非空」，逐帧观感留发版门文档真机手验清单。
/// 装配范式同 ChatPageAssemblyRegressionTests（进程内
/// 托管 RootView＋钦定主线）。
@MainActor
final class SmokeGateLongListScrollTests: XCTestCase {

    private final class SmokeWindow: UIWindow {
        override var intrinsicContentSize: CGSize {
            CGSize(width: 402, height: 874)
        }
    }

    /// 同步泵 RunLoop（同 ChatPageAssemblyRegressionTests
    /// 的 spinRunLoop 口径：期望等待而非 RunLoop.run 直调，
    /// 后者在 async 上下文被编译器禁）
    private func spin(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func allScrollViews(
        _ view: UIView, into: inout [UIScrollView]
    ) {
        if let scroll = view as? UIScrollView {
            into.append(scroll)
        }
        for sub in view.subviews {
            allScrollViews(sub, into: &into)
        }
    }

    /// 无障碍标签规范化：正文渲染前过 TextShaping
    /// .prettyWrap（VisualRules 实证：段尾字形逐对插
    /// 零宽 WORD JOINER U+2060 绑定），「冒烟长会话
    /// 行 001」在真实标签里是「…00⁠1」——按原文子串
    /// 永远匹配不到（run 43650912503 首行断言即此，
    /// 与 §74 真呈现路径数字串内插 U+2060 同族）。
    /// 比对前两侧一律剥零宽字符。
    private func normalizedAxLabel(_ label: String?) -> String {
        guard let label else { return "" }
        return label.filter {
            $0 != "\u{2060}" && $0 != "\u{200B}"
                && $0 != "\u{FEFF}"
        }
    }

    /// 递归收集无障碍元素：子视图下钻＋每层
    /// UIAccessibilityContainer 供出的元素双路并走、
    /// ObjectIdentifier 去重、深度封顶。旧法只读
    /// window.accessibilityElementCount() 扁平表——
    /// 全仓唯一用法，同仓范式 ChatPageAssembly-
    /// RegressionTests 全程走视图层级遍历；该扁平表
    /// 在进程内宿主（裸 UIWindow、无 scene）能否穿
    /// 过 UIHostingController 边界从未被证实（run
    /// 43650912503：首行与箭头同表双失、机制未分
    /// 清）。本法自根双路下钻，不依赖窗口扁平化。
    private func collectAxElements(
        in view: UIView, depth: Int,
        into: inout [NSObject], seen: inout Set<ObjectIdentifier>
    ) {
        guard depth <= 48 else { return }
        if view.isAccessibilityElement {
            addAxObject(
                view as NSObject, depth: depth,
                into: &into, seen: &seen
            )
        }
        let count = view.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for index in 0..<count {
                if let element = view.accessibilityElement(
                    at: index
                ) as? NSObject {
                    addAxObject(
                        element, depth: depth,
                        into: &into, seen: &seen
                    )
                }
            }
        }
        for sub in view.subviews {
            collectAxElements(
                in: sub, depth: depth + 1,
                into: &into, seen: &seen
            )
        }
    }

    /// 去重登记一个元素；元素本身是视图时继续下钻
    /// （容器供出的 SwiftUI 平台视图子树同路）
    private func addAxObject(
        _ object: NSObject, depth: Int,
        into: inout [NSObject], seen: inout Set<ObjectIdentifier>
    ) {
        guard seen.insert(ObjectIdentifier(object)).inserted
        else { return }
        into.append(object)
        if let view = object as? UIView {
            collectAxElements(
                in: view, depth: depth + 1,
                into: &into, seen: &seen
            )
        }
    }

    private func axElements(in root: UIView) -> [NSObject] {
        var elements: [NSObject] = []
        var seen: Set<ObjectIdentifier> = []
        collectAxElements(
            in: root, depth: 0, into: &elements, seen: &seen
        )
        return elements
    }

    /// 按 label 包含找元素（两侧规范化后比对；
    /// VoiceOver 同路：SwiftUI 钮在进程内只能经无
    /// 障碍面触发）
    private func axElement(
        in root: UIView, labelContaining needle: String
    ) -> NSObject? {
        let target = normalizedAxLabel(needle)
        return axElements(in: root).first {
            normalizedAxLabel($0.accessibilityLabel)
                .contains(target)
        }
    }

    /// 找会话行：先限被滚的列表子树（命中即证滚的
    /// 是会话列表），未命中退全窗（身份由调用方以
    /// 帧相交兜底）
    private func findChatRow(
        _ needle: String, list: UIScrollView, window: UIWindow
    ) -> NSObject? {
        axElement(in: list, labelContaining: needle)
            ?? axElement(in: window, labelContaining: needle)
    }

    /// 轮询等偏移量落到目标（±2pt）——直接读
    /// UIScrollView 实测值，不靠 SwiftUI 状态；
    /// 超时返回最后实测值供断言打印。
    private func waitForOffset(
        _ list: UIScrollView, targetY: CGFloat,
        timeout: TimeInterval
    ) -> CGFloat {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if abs(list.contentOffset.y - targetY) <= 2 {
                return list.contentOffset.y
            }
            spin(seconds: 0.2)
        }
        return list.contentOffset.y
    }

    /// 轮询等无障碍元素出现（AX 树刷新可滞后于状态
    /// 翻转，单次查找会误判）——超时返回最后一次
    /// 查找结果。
    private func waitForAxElement(
        timeout: TimeInterval,
        _ lookup: () -> NSObject?
    ) -> NSObject? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = lookup() { return element }
            spin(seconds: 0.25)
        }
        return lookup()
    }

    func testLongConversationScrollToBottomLandsWithTailVisible()
        throws
    {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let context = container.mainContext
        let base = Date().timeIntervalSince1970 - 7_200
        let thread = ChatThread(title: "冒烟长会话")
        thread.createdAt = Date(timeIntervalSince1970: base)
        context.insert(thread)
        for index in 1...120 {
            let entry = ChatEntry(
                role: index.isMultiple(of: 2)
                    ? "assistant" : "user",
                content: String(
                    format: "冒烟长会话行 %03d", index
                ),
                thread: thread
            )
            entry.createdAt = Date(timeIntervalSince1970:
                base + TimeInterval(index * 30))
            context.insert(entry)
        }
        try context.save()

        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        appState.sideChats.designateMainThread(thread.id)

        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        let window = SmokeWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        spin(seconds: 3)

        var scrolls: [UIScrollView] = []
        allScrollViews(window, into: &scrolls)
        let list = try XCTUnwrap(
            scrolls.max {
                $0.contentSize.height < $1.contentSize.height
            },
            "会话列表滚动面应在场"
        )
        XCTAssertGreaterThan(
            list.contentSize.height, list.bounds.height * 3,
            "120 行长会话内容高应远超视口（fixture 真长）"
        )

        // 先显式贴底并验偏移：不论出现贴底做没做成，
        // 起点必须实测在底——否则「滚到顶」可能是原地
        // 不动（第五轮即因此红：位移从未验证，只凭
        // 1.2 秒固定等待就查箭头）。
        let bottomTarget = list.contentSize.height
            + list.adjustedContentInset.bottom
            - list.bounds.height
        list.setContentOffset(
            CGPoint(x: 0, y: bottomTarget), animated: false
        )
        list.layoutIfNeeded()
        let bottomY = waitForOffset(
            list, targetY: bottomTarget, timeout: 5
        )
        print("LONGLIST bottom offset=\(bottomY)"
            + " target=\(bottomTarget)"
            + " contentSize=\(list.contentSize.height)")
        XCTAssertGreaterThan(
            bottomY, list.bounds.height,
            "显式贴底后偏移应远离顶部（位移须实测）"
        )

        // 滚到顶：回底箭头应出现——偏移须实测落在顶
        let topY = -list.adjustedContentInset.top
        list.setContentOffset(
            CGPoint(x: 0, y: topY), animated: false
        )
        list.layoutIfNeeded()
        let settledY = waitForOffset(
            list, targetY: topY, timeout: 5
        )
        print("LONGLIST top offset=\(settledY)"
            + " target=\(topY)"
            + " contentSize=\(list.contentSize.height)")
        XCTAssertLessThanOrEqual(
            abs(settledY - topY), 2,
            "滚到顶后偏移应落在顶（位移须实测）"
        )

        // 身份锚（第七轮换锚，定因见 normalizedAxLabel
        // 与 collectAxElements 注）：先在被滚的列表子
        // 树内找行（命中即证滚的是会话列表），未命中
        // 退全窗找、并以帧与列表可见框相交兜底身份；
        // 普查打印入日志，下一轮无论红绿都能分清机
        // 制（整形零宽字／扁平表不穿透／行未生成）。
        let listScreenFrame = list.convert(list.bounds, to: nil)
        let listCensus = axElements(in: list)
        let smokeLabels = listCensus
            .map { normalizedAxLabel($0.accessibilityLabel) }
            .filter { $0.contains("冒烟") }
        print("LONGLIST ax census list=\(listCensus.count)"
            + " window=\(axElements(in: window).count)"
            + " smokeRows=\(smokeLabels.count)"
            + " first=\(smokeLabels.first ?? "无")")
        let firstRow = try XCTUnwrap(
            waitForAxElement(timeout: 5) {
                findChatRow(
                    "冒烟长会话行 001", list: list, window: window
                )
            },
            "滚到顶后首行应在无障碍树里（滚的须是会话列表）"
        )
        XCTAssertTrue(
            firstRow.accessibilityFrame
                .intersects(listScreenFrame),
            "首行帧应与列表可见框相交（滚顶后真可见）"
        )

        // 箭头插入与 AX 树刷新可滞后于状态翻转，轮询等；
        // label 含未读变体「回到底部，N 条新消息」
        // （ChatView 实证），按包含匹配
        let arrow = try XCTUnwrap(
            waitForAxElement(timeout: 5) {
                axElement(in: window, labelContaining: "回到底部")
            },
            "离底后回底箭头应出现（无障碍 label「回到底部」）"
        )
        XCTAssertTrue(
            arrow.accessibilityActivate(),
            "回底箭头无障碍激活应真触发滚动"
        )
        spin(seconds: 2.5)

        let maxOffset = list.contentSize.height
            + list.adjustedContentInset.bottom
            - list.bounds.height
        XCTAssertLessThanOrEqual(
            abs(list.contentOffset.y - maxOffset), 2,
            "激活回底后落点应贴底（offset \(list.contentOffset.y)"
                + " vs 底 \(maxOffset)）"
        )

        // 末行真渲染且落在可见框内（黑闪的机器可验部分：
        // 空白帧时末行不在无障碍树里、或帧不在可见区）
        let tail = try XCTUnwrap(
            findChatRow(
                "冒烟长会话行 120", list: list, window: window
            ),
            "落底后末行应在无障碍树里（已真生成）"
        )
        XCTAssertTrue(
            tail.accessibilityFrame.intersects(listScreenFrame),
            "末行帧应与列表可见框相交（真可见、非空白）"
        )
    }
}
