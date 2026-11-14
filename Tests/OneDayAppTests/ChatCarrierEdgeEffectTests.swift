import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §260 新承载（gen3）滚动边缘效果恢复的装配层验
/// 收：0.50.46 真机反馈——开关开后上下朦胧感全
/// 失。定因＝§257 换承载时 §213 的两半一并漏接：
/// ①样式——旧承载挂 ChatView SwiftUI 列表的
/// .scrollEdgeEffectStyle(.soft)，修饰符够不到
/// representable 内的 UIKit 本体，承载控制器从
/// 未直设 topEdgeEffect/bottomEdgeEffect；②登
/// 记——两宿主的 UIScrollEdgeElementContainer-
/// Interaction 靠 ChatListScrollViewHandle 对齐
/// 本体，旧承载由内容栈登记锚喂入、新承载面无
/// 锚且句柄从未透传，interaction 恒绑不到。本
/// 套钉住修复后的装配事实：承载本体自带 .soft
/// 双边样式、本体经共享句柄登记、两宿主 inter-
/// action 随之绑到承载本体；ChatView 生产装配
/// 点（carrierListSurface 传句柄）由源码守护钉
/// 住。像素级双态验收（静止不可见/滚动朦胧在）
/// 仍由 EdgeEffectProbeTests 承接（旧承载面）。
@MainActor
final class ChatCarrierEdgeEffectTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// 与 ChatListCarrierReentrancyTests 同式装配：
    /// 控制器＋双句柄＋空回调，入窗口真加载
    private func mountCarrier(
        edgeHandle: ChatListScrollViewHandle
    ) -> ChatListCarrierViewController {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        windows.append(window)
        let controller = ChatListCarrierViewController()
        let carrierHandle = ChatListCarrierHandle()
        controller.handle = carrierHandle
        controller.callbacks = ChatListCarrierCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        controller.edgeScrollHandle = edgeHandle
        carrierHandle.controller = controller
        let wrapper = UIViewController()
        wrapper.addChild(controller)
        wrapper.view.addSubview(controller.view)
        controller.view.frame = wrapper.view.bounds
        controller.didMove(toParent: wrapper)
        window.rootViewController = wrapper
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.3)
        return controller
    }

    // MARK: - 样式（承载本体自带 .soft 双边）

    func testCarrierScrollViewCarriesSoftEdgeEffectStyles() {
        let controller = mountCarrier(
            edgeHandle: ChatListScrollViewHandle()
        )
        let scroll = controller.scrollView
        XCTAssertTrue(
            scroll.topEdgeEffect.style
                === UIScrollEdgeEffect.Style.soft,
            "新承载顶缘样式应为系统 .soft（与旧承载 "
                + ".scrollEdgeEffectStyle(.soft, for: .top) 同值）"
        )
        XCTAssertTrue(
            scroll.bottomEdgeEffect.style
                === UIScrollEdgeEffect.Style.soft,
            "新承载底缘样式应为系统 .soft（与旧承载 "
                + ".scrollEdgeEffectStyle(.soft, for: .bottom) 同值）"
        )
        XCTAssertFalse(scroll.topEdgeEffect.isHidden)
        XCTAssertFalse(scroll.bottomEdgeEffect.isHidden)
    }

    // MARK: - 登记链（本体→共享句柄→两宿主绑定）

    func testCarrierRegistersIntoSharedHandleAndBothHostsBind() {
        let edgeHandle = ChatListScrollViewHandle()
        let controller = mountCarrier(edgeHandle: edgeHandle)
        // 本体已登记进共享句柄（旧承载同一份）
        XCTAssertTrue(
            edgeHandle.scrollView === controller.scrollView,
            "新承载装配后共享句柄应指向承载本体"
        )
        // 顶宿主：赋值即绑定、edge=.top
        let topHost = TopBarGuideHostController()
        topHost.edgeScrollHandle = edgeHandle
        XCTAssertEqual(topHost.traceEdgeInteraction.edge, .top)
        XCTAssertTrue(
            topHost.traceEdgeInteraction.scrollView
                === controller.scrollView,
            "顶簇 interaction 应绑到新承载本体"
        )
        // 舱带宿主：赋值即绑定、edge=.bottom
        let composerHost = ComposerGuideHostController()
        composerHost.edgeScrollHandle = edgeHandle
        guard let bandContainer =
                composerHost.traceBandView as? EdgeBandContainerView
        else { return XCTFail("舱带不是注册容器") }
        XCTAssertEqual(bandContainer.traceInteraction.edge, .bottom)
        XCTAssertTrue(
            bandContainer.traceInteraction.scrollView
                === controller.scrollView,
            "舱带 interaction 应绑到新承载本体"
        )
    }

    // MARK: - 生产装配点源码守护

    private enum SourceGuardError: Error {
        case malformedCarrierCallExpression
    }

    /// 限定在 ChatView.carrierListSurface 的生产装
    /// 配点：截取有限片段、去注释后定位 ChatList-
    /// CarrierView( 的实参括号，核实共享句柄以
    /// edgeScrollHandle: listScrollHandle 传入。
    /// 删除该实参、改传他物或只把该行留在注释中
    /// 都会判红（与 TabBarFloatTests 的源码守护同
    /// 式：不托管真实 ChatView、不对全文件做无限
    /// 定的目标字符串搜）
    func testChatViewCarrierSurfacePassesSharedEdgeHandle()
        throws
    {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatViewURL = repositoryRoot.appendingPathComponent(
            "Sources/OneDayApp/ChatView.swift"
        )
        let raw = try String(
            contentsOf: chatViewURL, encoding: .utf8
        )
        let surfaceRange = try XCTUnwrap(
            raw.range(of: "private var carrierListSurface")
        )
        let segment = String(
            raw[surfaceRange.lowerBound...].prefix(6_000)
        )
        let code = Self.stripComments(segment)
        let callRange = try XCTUnwrap(
            code.range(of: "ChatListCarrierView(")
        )
        let argumentsStart = callRange.upperBound
        let argumentsEnd = try Self.scanBalanced(
            code, from: code.index(before: argumentsStart),
            opening: "(", closing: ")"
        )
        let arguments = code[argumentsStart..<argumentsEnd]
        XCTAssertTrue(
            arguments.contains("edgeScrollHandle: listScrollHandle"),
            "carrierListSurface 必须把 ChatView 的 "
                + "listScrollHandle 以 edgeScrollHandle "
                + "实参传给 ChatListCarrierView"
        )
    }

    private static func scanBalanced(
        _ text: String,
        from start: String.Index,
        opening: Character,
        closing: Character
    ) throws -> String.Index {
        var depth = 0
        var index = start
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        throw SourceGuardError.malformedCarrierCallExpression
    }

    private static func stripComments(_ source: String) -> String {
        var result = ""
        var index = source.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false
        var escaped = false

        func peekNext() -> Character? {
            let next = source.index(after: index)
            guard next < source.endIndex else { return nil }
            return source[next]
        }

        while index < source.endIndex {
            let character = source[index]
            let next = peekNext()
            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    result.append(character)
                }
                index = source.index(after: index)
                continue
            }
            if inBlockComment {
                if character == "*", next == "/" {
                    inBlockComment = false
                    index = source.index(index, offsetBy: 2)
                    continue
                }
                index = source.index(after: index)
                continue
            }
            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = source.index(after: index)
                continue
            }
            if character == "/", next == "/" {
                inLineComment = true
                index = source.index(index, offsetBy: 2)
                continue
            }
            if character == "/", next == "*" {
                inBlockComment = true
                index = source.index(index, offsetBy: 2)
                continue
            }
            if character == "\"" {
                inString = true
            }
            result.append(character)
            index = source.index(after: index)
        }
        return result
    }
}
