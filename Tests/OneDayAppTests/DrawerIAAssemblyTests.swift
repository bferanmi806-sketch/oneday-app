import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 194 装配回归钉（2026-11-21）：0.50.77 真
/// 机报抽屉「点子/动态/目标/资源库不见了、全部对
/// 话/主聊没有归类、顺序不对」——事后 diff 定案：
/// 入口行并非 192 视觉包所丢，而是结构归位第二批
/// （fc93ea8）在装配层整组退役；当时装配层无任何
/// 断言钉住入口行集合与分组归属，CI 全绿照样出
/// 包。本套件以**真 DrawerView**（直挂宿主、与
/// DrawerSafeAreaRealRootTests 同款环境注入）渲
/// 染，收无障碍元素标签＋帧顶 y，钉三件事：
/// - 入口行全集在场：「选项卡」组头＋主线聊天／
///   动态／点子／目标／资源库／全部对话六行＋
///   「频道」「旁聊」两组头，一个不许缺
/// - 分组归属与次序：六行全在「选项卡」组头与
///   「频道」组头之间（按帧顶 y 全序断言），组序
///   为选项卡→频道→旁聊
/// - 折叠态：「选项卡」组折叠后四导航行与全部对
///   话行退出无障碍树、组头与另两组仍在场（折叠
///   两态与 192 口径一致的装配面留证）
/// 窗高取 1100（非真机口径）：本套件只钉装配、
/// 不钉几何，名单全行须同帧在场供帧序断言；安
/// 全区覆写与 SafeArea 套件同值（顶 59／底 34）
@MainActor
final class DrawerIAAssemblyTests: XCTestCase {

    private final class TallWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: TallWindow!
    private var appState: AppState!
    private var container: ModelContainer!
    /// §184：容器租约——见 SwiftDataTestMount
    private var swiftDataMount = SwiftDataTestMount()

    override func setUp() async throws {
        try await super.setUp()
        // 折叠账归零：两态断言都从全展开基线出发，
        // 不许被同进程其他套件的落盘污染
        UserDefaults.standard.removeObject(
            forKey: SectionCollapseStorageKeys.drawerSections
        )
        appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        window = TallWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 1100)
        )
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(
            forKey: SectionCollapseStorageKeys.drawerSections
        )
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        container = nil
        appState = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func mountDrawer() {
        let appState = appState!
        let host = UIHostingController(
            rootView: DrawerView(
                width: 317,
                currentTab: .chat,
                onSelectTab: { _ in },
                onClose: {},
                onOpenChannel: { _ in }
            )
            .environment(appState)
            .environment(\.modelContext, container.mainContext)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .boldTextMapping()
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        host.view.layoutIfNeeded()
    }

    /// 无障碍元素普查：标签 → 最小帧顶 y（同标签多
    /// 元素取最高一处；帧无效的只记在场、y 记为
    /// +∞ 不参与序断言）
    private func collectLabelMinY() -> [String: CGFloat] {
        var result: [String: CGFloat] = [:]
        func record(label: String?, frame: CGRect) {
            guard let label, !label.isEmpty else { return }
            let y = frame.height > 0 ? frame.minY : CGFloat.infinity
            result[label] = min(result[label] ?? .infinity, y)
        }
        func visitObject(_ object: NSObject) {
            record(
                label: object.accessibilityLabel,
                frame: object.accessibilityFrame
            )
        }
        func visit(view: UIView) {
            if let label = view.accessibilityLabel {
                let frame = view.accessibilityFrame.height > 0
                    ? view.accessibilityFrame
                    : view.convert(view.bounds, to: nil)
                record(label: label, frame: frame)
            }
            if let elements = view.accessibilityElements {
                for element in elements {
                    if let elementView = element as? UIView {
                        visit(view: elementView)
                    } else if let object = element as? NSObject {
                        visitObject(object)
                    }
                }
            }
            for sub in view.subviews {
                visit(view: sub)
            }
        }
        if let root = window.rootViewController?.view {
            visit(view: root)
        }
        return result
    }

    private func dumpLabels(_ map: [String: CGFloat]) -> String {
        map.keys.sorted().joined(separator: " | ")
    }

    /// 入口行全集＋分组归属＋次序（台账 194 本体）
    func testDrawerAssemblyHasTabGroupWithAllEntryRows() {
        mountDrawer()
        let y = collectLabelMinY()
        let pinned = [
            "选项卡", "主线聊天", "动态", "点子",
            "目标", "资源库", "全部对话", "频道", "旁聊",
        ]
        for label in pinned {
            XCTAssertNotNil(
                y[label],
                "抽屉装配缺「\(label)」——入口行/组头退场"
                    + "（台账 194 回归形态）；在屏标签："
                    + dumpLabels(y)
            )
        }
        // 全序：选项卡组头 < 六行（组内序）< 频道组
        // 头 < 旁聊组头——六行被两组头夹住即归类成
        // 立，组序与行序一并钉死
        for index in 1..<pinned.count {
            let previous = pinned[index - 1]
            let current = pinned[index]
            guard let previousY = y[previous],
                  let currentY = y[current] else { continue }
            XCTAssertLessThan(
                previousY, currentY - 1,
                "抽屉装配次序/归类不对：「\(previous)」"
                    + "(y=\(previousY)) 应在「\(current)」"
                    + "(y=\(currentY)) 之上；在屏标签："
                    + dumpLabels(y)
            )
        }
    }

    /// 折叠态：选项卡组折叠后组内行退出、组头与另
    /// 两组在场（194 恢复的折叠两态留证）
    func testDrawerTabGroupCollapsedHidesEntryRows() {
        let collapsed = SectionCollapseState.encode(
            [DrawerSectionKey.navigation: true]
        )
        UserDefaults.standard.set(
            collapsed,
            forKey: SectionCollapseStorageKeys.drawerSections
        )
        mountDrawer()
        let y = collectLabelMinY()
        for label in ["主线聊天", "动态", "点子", "目标", "资源库", "全部对话"] {
            XCTAssertNil(
                y[label],
                "选项卡组折叠后「\(label)」仍在场——折叠"
                    + "内容未随组头收起；在屏标签："
                    + dumpLabels(y)
            )
        }
        for label in ["选项卡", "频道", "旁聊"] {
            XCTAssertNotNil(
                y[label],
                "折叠态下组头「\(label)」缺失；在屏标签："
                    + dumpLabels(y)
            )
        }
    }
}
