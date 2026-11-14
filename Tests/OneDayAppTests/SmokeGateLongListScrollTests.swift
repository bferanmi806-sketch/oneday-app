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

    /// 全窗无障碍扁平表里按 label 精确找元素（VoiceOver
    /// 同路：SwiftUI 钮在进程内只能经无障碍面触发）
    private func axElement(
        in window: UIWindow, label: String
    ) -> NSObject? {
        let count = window.accessibilityElementCount()
        guard count != NSNotFound, count > 0 else { return nil }
        for index in 0..<count {
            guard let element = window.accessibilityElement(
                at: index
            ) as? NSObject else { continue }
            if element.accessibilityLabel == label {
                return element
            }
        }
        return nil
    }

    private func axElement(
        in window: UIWindow, labelContaining needle: String
    ) -> NSObject? {
        let count = window.accessibilityElementCount()
        guard count != NSNotFound, count > 0 else { return nil }
        for index in 0..<count {
            guard let element = window.accessibilityElement(
                at: index
            ) as? NSObject else { continue }
            if element.accessibilityLabel?.contains(needle)
                == true
            {
                return element
            }
        }
        return nil
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

        // 首行在树里＝滚的确实是会话列表（防取错滚动面）
        let firstRow = waitForAxElement(timeout: 5) {
            axElement(
                in: window, labelContaining: "冒烟长会话行 001"
            )
        }
        XCTAssertNotNil(
            firstRow,
            "滚到顶后首行应在无障碍树里（滚的须是会话列表）"
        )

        // 箭头插入与 AX 树刷新可滞后于状态翻转，轮询等
        let arrow = try XCTUnwrap(
            waitForAxElement(timeout: 5) {
                axElement(in: window, label: "回到底部")
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
            axElement(
                in: window, labelContaining: "冒烟长会话行 120"
            ),
            "落底后末行应在无障碍树里（已真生成）"
        )
        let listScreenFrame = list.convert(list.bounds, to: nil)
        XCTAssertTrue(
            tail.accessibilityFrame.intersects(listScreenFrame),
            "末行帧应与列表可见框相交（真可见、非空白）"
        )
    }
}
