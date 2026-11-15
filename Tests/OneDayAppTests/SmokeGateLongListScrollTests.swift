import Foundation
import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import OneDayApp

/// 出厂冒烟门·长会话回底（横扫 C 类「懒生成回底黑闪」
/// 的机器可验部分）：120 行长会话滚到顶→判别量验箭头
/// 渲染（列表底 inset 出现 ≈+52 台阶，第九轮定案）→
/// 编程滚底→断言落点贴底且末行真渲染在可见区（空白
/// 帧＝末行正文不在列表内或不在可见框内，断言即红）。
/// 箭头本体是纯 SwiftUI Button、进程内只以 AX 树元素
/// 形态存在，而该树在无 AX 客户端的进程内托管下整棵
/// 未生成（第七/八轮普查定案）——AX 激活在本例降为
/// 非阻断观察项，其等价验证迁 XCUIApplication UI 测
/// 形态为后续。黑闪是逐帧视觉现象，机器只能验「落点
/// ＋末行非空」，逐帧观感留发版门文档真机手验清单。
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

    /// 轮询读列表底 inset 落定值（第九轮判别量专用，
    /// 定案见 oneday-design-review/smoke-arrow-check
    /// -20261115.md §四第 1 条）：箭头行进出布局流让
    /// 发送区栈高变化 44＋spacingS 8＝52pt，经
    /// ComposerGuideHost 实测 pocketHeight→
    /// kbSnapshot.bottomSpace→旧承载列表底
    /// contentMargins（ChatView:3391）同值传导到平台
    /// 滚动面 adjustedContentInset.bottom。显隐带
    /// swap 动画、台阶可能渐变——全程轮询（≥5 秒）
    /// 不提前收，返回（落定值, 峰值）供证据行打印。
    private func pollBottomInset(
        _ list: UIScrollView, seconds: TimeInterval
    ) -> (settled: CGFloat, peak: CGFloat) {
        let deadline = Date().addingTimeInterval(seconds)
        var peak = list.adjustedContentInset.bottom
        while Date() < deadline {
            spin(seconds: 0.25)
            peak = max(peak, list.adjustedContentInset.bottom)
        }
        return (list.adjustedContentInset.bottom, peak)
    }

    /// 列表子树内非空 UITextView 收集（第八轮换锚，
    /// 定因见 oneday-design-review/smoke-gate-r8-
    /// diagnosis-20261115.md）：进程内托管时 SwiftUI
    /// 无障碍元素树由系统 AX 运行时懒生成、无 AX 客
    /// 户端连接时整棵未生成（第七轮普查 list=0
    /// window=0 实证），AX 通道不可作行身份判据；消
    /// 息正文一律落真实 UITextView，普查走视图层级
    /// 本身——照搬 ChatReliabilityOfflineTests
    /// .nonEmptyTextViewTexts 已证形态，作用域限被
    /// 滚列表子树（命中即证滚的是会话列表）。收
    /// (窗帧, 规范化文本) 对，帧供可见框相交判定，
    /// 文本规范化沿用 normalizedAxLabel 同口径（剥
    /// U+2060 等整形零宽字）。
    private func collectTextViews(
        in view: UIView,
        into: inout [(frame: CGRect, text: String)]
    ) {
        if let textView = view as? UITextView {
            let text = normalizedAxLabel(textView.text ?? "")
            if !text.isEmpty {
                into.append((
                    frame: textView.convert(
                        textView.bounds, to: nil
                    ),
                    text: text
                ))
            }
        }
        for sub in view.subviews {
            collectTextViews(in: sub, into: &into)
        }
    }

    private func listTextViews(
        in list: UIScrollView
    ) -> [(frame: CGRect, text: String)] {
        var out: [(frame: CGRect, text: String)] = []
        collectTextViews(in: list, into: &out)
        return out
    }

    /// 轮询等 UITextView 普查命中（渲染落定可滞后
    /// 于偏移落定）——超时返回最后一次查找结果。
    private func waitForTextView(
        timeout: TimeInterval,
        _ lookup: () -> (frame: CGRect, text: String)?
    ) -> (frame: CGRect, text: String)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let hit = lookup() { return hit }
            spin(seconds: 0.25)
        }
        return lookup()
    }

    /// 全窗 accessibilityElements 属性通道递归计数
    /// （census2 转储专用）：与第七轮 count/at: 通
    /// 道分开计，钉死「属性通道是否穿透 hosting 边
    /// 界／AX 树是否生成」两问；仅诊断打印、不作断
    /// 言。元素本身是视图时下钻其属性通道与子视图，
    /// 深度封顶 48 防自引用环。
    private func axPropertyCount(
        in view: UIView, depth: Int
    ) -> Int {
        guard depth <= 48 else { return 0 }
        var total = 0
        if let elements = view.accessibilityElements {
            total += elements.count
            for element in elements {
                if let elementView = element as? UIView {
                    total += axPropertyCount(
                        in: elementView, depth: depth + 1
                    )
                }
            }
        }
        for sub in view.subviews {
            total += axPropertyCount(
                in: sub, depth: depth + 1
            )
        }
        return total
    }

    /// 属性通道按 label 找元素（回底箭头双通道之
    /// 一）：递归 accessibilityElements 属性（姊妹
    /// 测试 onScreenTexts 在用通道），元素本身是视
    /// 图时继续下钻其属性与子视图；未命中退第七轮
    /// count/at: 通道（调用方 ?? 串联）。
    private func axElementViaProperty(
        in view: UIView, labelContaining needle: String,
        depth: Int
    ) -> NSObject? {
        guard depth <= 48 else { return nil }
        let target = normalizedAxLabel(needle)
        if let elements = view.accessibilityElements {
            for element in elements {
                guard let object = element as? NSObject
                else { continue }
                if normalizedAxLabel(object.accessibilityLabel)
                    .contains(target) {
                    return object
                }
                if let elementView = object as? UIView,
                   let hit = axElementViaProperty(
                       in: elementView,
                       labelContaining: needle,
                       depth: depth + 1
                   ) {
                    return hit
                }
            }
        }
        for sub in view.subviews {
            if let hit = axElementViaProperty(
                in: sub, labelContaining: needle,
                depth: depth + 1
            ) {
                return hit
            }
        }
        return nil
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
        // 装配改挂 scene（第八轮修法增益项，同
        // ChatPageAssemblyRegressionTests 键盘变体先
        // 例）：裸窗无 scene 时键盘引导线永不驱动、AX
        // 运行时亦少一个在场信号；有 scene 走
        // UIWindow(windowScene:) 并照先例重设帧，无
        // scene 退回原裸窗装配（宿主环境差异不许先
        // 于断言红）。其余装配一字不动。
        let window: SmokeWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window = SmokeWindow(windowScene: scene)
            window.frame = CGRect(
                x: 0, y: 0, width: 402, height: 874
            )
        } else {
            window = SmokeWindow(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
        }
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

        // 判别量基线（第九轮）：贴底稳态下箭头行不在
        // 布局流内（isNearBottom 种子 true＋距底 0），
        // 此刻的列表底 inset 即无箭头基线；滚顶后的台
        // 阶差以此为准。留 1 秒待发送区栈高落定再读。
        spin(seconds: 1)
        let insetBaseline = list.adjustedContentInset.bottom
        print("LONGLIST inset baseline=\(insetBaseline)")

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

        // 身份锚（第八轮换锚，定因见 smoke-gate-r8-
        // diagnosis-20261115.md）：第七轮普查实证整
        // 棵 AX 树为空（list=0 window=0）——树懒生成
        // 未触发时任何 AX 遍历都是 0，标签规范化与帧
        // 兜底无从施展。本轮改走 UITextView 普查（正
        // 文落真实 UITextView、不依赖 AX 树时序）：
        // 列表子树内命中首行文本即证滚的是会话列表，
        // 其窗帧与列表可见框相交证滚顶后真可见。
        // census2 转储无论红绿必打：axProp 钉死属性
        // 通道是否穿透、textViews/firstTV 钉死正文通
        // 道实数；第七轮 ax census 行保留作对照。
        let listScreenFrame = list.convert(list.bounds, to: nil)
        print("LONGLIST ax census list="
            + "\(axElements(in: list).count)"
            + " window=\(axElements(in: window).count)")
        let topTextViews = listTextViews(in: list)
        print("LONGLIST census2"
            + " axProp=\(axPropertyCount(in: window, depth: 0))"
            + " textViews=\(topTextViews.count)"
            + " firstTV=\(topTextViews.first?.text ?? "无")")
        let firstRow = try XCTUnwrap(
            waitForTextView(timeout: 5) {
                listTextViews(in: list).first {
                    $0.text.contains("冒烟长会话行 001")
                }
            },
            "滚到顶后首行正文应在列表子树的 UITextView 里（滚的须是会话列表）"
        )
        XCTAssertTrue(
            firstRow.frame.intersects(listScreenFrame),
            "首行帧应与列表可见框相交（滚顶后真可见）"
        )

        // 箭头判别量（第九轮定案，承 smoke-arrow-
        // check-20261115.md §四第 1 条）：箭头是纯
        // SwiftUI Button、在进程内只以 AX 树元素形
        // 态存在，而该树在无 AX 客户端的进程内托管
        // 下整棵未生成（第七轮普查 list=0 window=0、
        // 第八轮 census2 axProp=0 双通道复证）——
        // **AX 不可达就此定案，进程内箭头验证到此为
        // 止**，改以渲染链的布局传导指纹为判别量：
        // 箭头行进布局流→发送区栈高 +52（钮行 44＋
        // spacingS 8）→pocketHeight→bottomSpace→
        // 列表底 contentMargins→平台滚动面
        // adjustedContentInset.bottom 同值 +52。滚
        // 顶稳态后轮询 6 秒取落定差：出台阶＝喂入环
        // ＋判定环＋渲染全链无罪钉死；无台阶＝喂入
        // 环嫌疑（onScrollGeometryChange 在进程内
        // 托管下未把距底读数送进派生点），按核查报
        // 告口径停手报主线、本线不改产品码。
        let insetPoll = pollBottomInset(list, seconds: 6)
        let insetDelta = insetPoll.settled - insetBaseline
        print("LONGLIST insetStep baseline=\(insetBaseline)"
            + " settled=\(insetPoll.settled)"
            + " peak=\(insetPoll.peak)"
            + " delta=\(insetDelta)")
        XCTAssertTrue(
            abs(insetDelta - 52) <= 8,
            "滚顶后列表底 inset 应出现 ≈+52 台阶（箭头行"
                + "进布局流的传导指纹，实测 delta="
                + "\(insetDelta)）；无台阶即喂入环嫌疑——"
                + "按 smoke-arrow-check §四第 1 条停手报"
                + "主线、本线不改产品码"
        )

        // 箭头 AX 激活降为非阻断观察项（第九轮）：
        // 双通道查找与激活结果只打印、不设断言（AX
        // 树未生成定案内，查不到不构成失败）；激活
        // 的等价验证迁 XCUIApplication UI 测形态
        // （运行器本身是 AX 客户端、树必生成）为后
        // 续，见 smoke-gate-report 第九轮准备节。
        // label 含未读变体「回到底部，N 条新消息」
        // （ChatView 实证），按包含匹配。
        if let arrow = waitForAxElement(timeout: 5, {
            axElementViaProperty(
                in: window, labelContaining: "回到底部",
                depth: 0
            ) ?? axElement(
                in: window, labelContaining: "回到底部"
            )
        }) {
            let activated = arrow.accessibilityActivate()
            spin(seconds: 2.5)
            print("LONGLIST arrowAX found=true"
                + " activated=\(activated)"
                + " offsetAfter=\(list.contentOffset.y)")
        } else {
            print("LONGLIST arrowAX found=false"
                + "（非阻断观察项：AX 树未生成定案内）")
        }

        // 末行步与箭头解耦（第九轮）：末行可见验证
        // 改走编程滚底＋UITextView 普查，不再依赖箭
        // 头激活——第八轮末行即因箭头步先败被挡住未
        // 测（非测得失败）。滚底目标按当刻 inset 计
        // （箭头行在流内时底 inset 含 +52、贴底后箭
        // 头退出又回落 52），落点断言对每采样时刻的
        // 现行 maxOffset 判（±2pt），不取一次性快照。
        let tailTarget = list.contentSize.height
            + list.adjustedContentInset.bottom
            - list.bounds.height
        list.setContentOffset(
            CGPoint(x: 0, y: tailTarget), animated: false
        )
        list.layoutIfNeeded()
        let tailDeadline = Date().addingTimeInterval(5)
        var tailY = list.contentOffset.y
        var tailMax = tailTarget
        while Date() < tailDeadline {
            tailMax = list.contentSize.height
                + list.adjustedContentInset.bottom
                - list.bounds.height
            tailY = list.contentOffset.y
            if abs(tailY - tailMax) <= 2 { break }
            spin(seconds: 0.2)
        }
        print("LONGLIST tail offset=\(tailY)"
            + " max=\(tailMax)")
        XCTAssertLessThanOrEqual(
            abs(tailY - tailMax), 2,
            "编程滚底后落点应贴底（offset \(tailY)"
                + " vs 底 \(tailMax)）"
        )

        // 末行真渲染且落在可见框内（黑闪的机器可验
        // 部分：空白帧时末行正文不在列表内、或帧不在
        // 可见区）——同首行走 UITextView 普查（第八
        // 轮换锚，理由见首行段）
        let tail = try XCTUnwrap(
            waitForTextView(timeout: 5) {
                listTextViews(in: list).first {
                    $0.text.contains("冒烟长会话行 120")
                }
            },
            "落底后末行正文应在列表子树的 UITextView 里（已真渲染）"
        )
        XCTAssertTrue(
            tail.frame.intersects(listScreenFrame),
            "末行帧应与列表可见框相交（真可见、非空白）"
        )
    }
}
