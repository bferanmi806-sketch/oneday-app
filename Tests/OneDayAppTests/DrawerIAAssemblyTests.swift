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
/// 包。本套件以**真 DrawerView**（经容器 drawer-
/// Builder 注入、与生产桥 apply() 同款环境，与
/// DrawerSafeAreaRealRootTests 同装配）渲染，收
/// 无障碍元素标签＋帧顶 y，钉三件事：
/// - 入口行全集在场：「选项卡」组头＋主线聊天／
///   动态／点子／目标／资源库／全部对话六行＋
///   「频道」「旁聊」两组头，一个不许缺
/// - 分组归属与次序：六行全在「选项卡」组头与
///   「频道」组头之间（按帧顶 y 全序断言），组序
///   为选项卡→频道→旁聊
/// - 折叠态：「选项卡」组折叠后组内行退出无障碍
///   树、组头与另两组仍在场（折叠两态与 192 口径
///   一致的装配面留证）
/// 采集口径：SwiftUI 无障碍树为懒生成——挂载后
/// 足时自旋并重试采集至非空（上限约 6 秒），最
/// 终断言仍按全集严格判，生成时序不作缺行借口
/// （首轮 CI 实证 0.6 秒短自旋采到空树、断言全
/// 红，采集办法已按本注修正）
@MainActor
final class DrawerIAAssemblyTests: XCTestCase {

    /// 与 SafeArea 套件同口径的设备窗（402×874、
    /// 安全区覆写顶 59／底 34）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
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
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
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

    /// 与生产桥 apply() 同款装配（逐字沿 Drawer-
    /// SafeAreaRealRootTests 的 assembleDrawer-
    /// Controller）：真 DrawerView 经 drawerBuilder
    /// 注入真容器、开态落位
    private func assembleDrawerController() -> DrawerContainerController {
        let controller = DrawerContainerController()
        let appState = appState!
        let modelContext = container.mainContext
        controller.drawerBuilder = { width in
            AnyView(
                DrawerView(
                    width: width,
                    currentTab: .chat,
                    onSelectTab: { _ in },
                    onClose: {},
                    onOpenChannel: { _ in }
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .boldTextMapping()
            )
        }
        controller.contentRoot = AnyView(Text("content替身"))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return controller
    }

    /// 无障碍元素普查：标签 → 最小帧顶 y（同标签多
    /// 元素取最高一处；帧无效的只记在场、y 记为
    /// +∞ 不参与序断言）。UILabel 文本一并收（与
    /// ChatReliabilityOfflineTests 的在屏文本口径
    /// 同源）
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
            if let label = view as? UILabel, let text = label.text {
                record(
                    label: text,
                    frame: view.convert(view.bounds, to: nil)
                )
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
        visit(view: window)
        return result
    }

    /// 采集至必备标签齐备：无障碍树懒生成且分批到
    /// 达，自旋重试（每轮 1 秒、上限 6 轮）；6 轮仍
    /// 缺则原样返回，由断言按缺行判红并倾卸诊断
    private func collectLabelMinYSettled(
        requiring labels: [String]
    ) -> [String: CGFloat] {
        var map = collectLabelMinY()
        var rounds = 0
        while labels.contains(where: { map[$0] == nil })
                && rounds < 6 {
            spinRunLoop(seconds: 1)
            map = collectLabelMinY()
            rounds += 1
        }
        return map
    }

    private func dumpLabels(_ map: [String: CGFloat]) -> String {
        map.keys.sorted().joined(separator: " | ")
    }

    /// 入口行全集＋分组归属＋次序（台账 194 本体）
    func testDrawerAssemblyHasTabGroupWithAllEntryRows() {
        let controller = assembleDrawerController()
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        let pinned = [
            "选项卡", "主线聊天", "动态", "点子",
            "目标", "资源库", "全部对话", "频道", "旁聊",
        ]
        let y = collectLabelMinYSettled(requiring: pinned)
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
        let controller = assembleDrawerController()
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        let y = collectLabelMinYSettled(
            requiring: ["选项卡", "频道", "旁聊"]
        )
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
