import OneDayCore
import SwiftUI
import XCTest
@testable import OneDayApp

/// 反应浮排包第一步验收（DESIGN §343）：开关口径
/// （缺省开/显式关回子菜单形态）、长按路由、呈现
/// 状态机全迁移、会话投递单点（错序不双投）、浮
/// 排定位、修饰符装配形态钉。真机观感（衔接帧/
/// 竞速/深色大字号）CI 无信号、归用户真机门
@MainActor
final class ReactionFloatingBarTests: XCTestCase {

    // MARK: - 开关口径

    private func scratchDefaults() -> UserDefaults {
        let suite = "test.reactionbar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testFlagDefaultsOnAndExplicitOff() {
        let defaults = scratchDefaults()
        let key = ChatReactionsFloatingBarFeature.defaultsKey
        XCTAssertEqual(key, "chat.reactions.floatingBar")
        XCTAssertTrue(
            ChatReactionsFloatingBarFeature.isEnabled(
                defaults: defaults
            ),
            "键缺省＝浮排开"
        )
        defaults.set(true, forKey: key)
        XCTAssertTrue(
            ChatReactionsFloatingBarFeature.isEnabled(
                defaults: defaults
            )
        )
        defaults.set(false, forKey: key)
        XCTAssertFalse(
            ChatReactionsFloatingBarFeature.isEnabled(
                defaults: defaults
            ),
            "显式 false＝回 0.50.80 子菜单形态"
        )
    }

    // MARK: - 路由（回退形态钉）

    func testRoutingTable() {
        XCTAssertEqual(
            ReactionBarRouting.route(
                flagEnabled: true, canReact: true
            ),
            .floatingBar
        )
        XCTAssertEqual(
            ReactionBarRouting.route(
                flagEnabled: true, canReact: false
            ),
            .systemMenu,
            "不可反应条目不因开关改变呈现面"
        )
        XCTAssertEqual(
            ReactionBarRouting.route(
                flagEnabled: false, canReact: true
            ),
            .systemMenu,
            "开关关＝回退系统菜单形态"
        )
        XCTAssertEqual(
            ReactionBarRouting.route(
                flagEnabled: false, canReact: false
            ),
            .systemMenu
        )
    }

    /// 修饰符装配钉：挂钩 nil＝纯系统菜单形态（回
    /// 退）、非 nil＝浮排生效——与 messageMenu 的路
    /// 由产物同口径
    func testModifierFormFollowsHook() {
        let plain = MessageMenuModifier(
            isEnabled: true,
            floatingBarHook: nil,
            makeData: { Self.dummyData() }
        )
        XCTAssertFalse(plain.usesFloatingBar)
        let hooked = MessageMenuModifier(
            isEnabled: true,
            floatingBarHook: { _ in },
            makeData: { Self.dummyData() }
        )
        XCTAssertTrue(hooked.usesFloatingBar)
    }

    // MARK: - 状态机

    func testMachineHappyPaths() {
        var machine = ReactionBarStateMachine()
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(
            machine.longPress(canReact: true), .presentBar
        )
        XCTAssertEqual(machine.phase, .bar)
        XCTAssertEqual(machine.pickReaction(), .deliverReaction)
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(
            machine.longPress(canReact: true), .presentBar
        )
        XCTAssertEqual(
            machine.requestActions(), .presentActionSheet
        )
        XCTAssertEqual(machine.phase, .actionSheet)
        XCTAssertTrue(machine.dismiss())
        XCTAssertEqual(machine.phase, .idle)
    }

    func testMachineDirectActionSheetAndIllegalEvents() {
        var machine = ReactionBarStateMachine()
        // idle 下的错序事件全忽略
        XCTAssertNil(machine.pickReaction())
        XCTAssertNil(machine.requestActions())
        XCTAssertFalse(machine.dismiss())
        // 不可反应长按直达动作面
        XCTAssertEqual(
            machine.longPress(canReact: false),
            .presentActionSheet
        )
        XCTAssertEqual(machine.phase, .actionSheet)
        // 动作面在场时再长按/点药丸全忽略（防双投）
        XCTAssertNil(machine.longPress(canReact: true))
        XCTAssertNil(machine.pickReaction())
        XCTAssertTrue(machine.dismiss())
        XCTAssertEqual(machine.phase, .idle)
        // bar 在场时重复长按忽略
        XCTAssertEqual(
            machine.longPress(canReact: true), .presentBar
        )
        XCTAssertNil(machine.longPress(canReact: true))
        XCTAssertEqual(machine.phase, .bar)
    }

    // MARK: - 会话投递（药丸回调钉）

    private static func dummyData(
        canReact: Bool = true,
        ownEmoji: String? = nil,
        onPickReaction: @escaping (String) -> Void = { _ in }
    ) -> ChatRowActionSheetData {
        ChatRowActionSheetData(
            plainText: "文本",
            canReact: canReact,
            ownEmoji: ownEmoji,
            onPickReaction: onPickReaction,
            onReply: {},
            onFork: {},
            onSelect: {},
            onShare: {}
        )
    }

    func testSessionPickDeliversOnceViaDataCallback() {
        var picked: [String] = []
        let session = ReactionBarSession(
            entryID: UUID(),
            data: Self.dummyData { picked.append($0) },
            sourceFrame: CGRect(
                x: 100, y: 300, width: 220, height: 60
            ),
            alignsTrailing: false
        )
        XCTAssertEqual(session.phase, .bar)
        XCTAssertTrue(session.pick("🔥"))
        XCTAssertEqual(picked, ["🔥"])
        XCTAssertEqual(session.phase, .idle)
        // 关后残留点按不双投
        XCTAssertFalse(session.pick("👍"))
        XCTAssertEqual(picked, ["🔥"])
    }

    func testSessionHandoffBlocksLaterPick() {
        var picked: [String] = []
        let session = ReactionBarSession(
            entryID: UUID(),
            data: Self.dummyData { picked.append($0) },
            sourceFrame: .zero,
            alignsTrailing: true
        )
        XCTAssertTrue(session.requestActions())
        XCTAssertEqual(session.phase, .actionSheet)
        // 已转交动作面：药丸投递关闭、不许再落反应
        XCTAssertFalse(session.pick("🔥"))
        XCTAssertTrue(picked.isEmpty)
        // 重复转交同为 no-op
        XCTAssertFalse(session.requestActions())
    }

    // MARK: - 定位

    func testPlacementAboveTrailingAndClamp() {
        let screen = CGSize(width: 402, height: 874)
        // 助手行（左对齐）、上方空间足 → 上方＋左对齐
        var origin = ReactionBarPlacement.barOrigin(
            sourceFrame: CGRect(
                x: 52, y: 400, width: 240, height: 60
            ),
            alignsTrailing: false,
            screenSize: screen
        )
        XCTAssertEqual(origin.x, 52)
        XCTAssertEqual(
            origin.y,
            400 - 8 - ReactionFloatingBarView.barHeight
        )
        // 用户行（右对齐）→ 右缘对齐
        origin = ReactionBarPlacement.barOrigin(
            sourceFrame: CGRect(
                x: 110, y: 400, width: 240, height: 60
            ),
            alignsTrailing: true,
            screenSize: screen
        )
        XCTAssertEqual(
            origin.x,
            350 - ReactionFloatingBarView.barWidth
        )
        // 贴顶 → 改置下方
        origin = ReactionBarPlacement.barOrigin(
            sourceFrame: CGRect(
                x: 52, y: 30, width: 240, height: 60
            ),
            alignsTrailing: false,
            screenSize: screen
        )
        XCTAssertEqual(origin.y, 30 + 60 + 8)
        // 左对齐帧出屏幕左界 → 夹回 8
        origin = ReactionBarPlacement.barOrigin(
            sourceFrame: CGRect(
                x: 2, y: 400, width: 240, height: 60
            ),
            alignsTrailing: false,
            screenSize: screen
        )
        XCTAssertEqual(origin.x, 8)
    }
}
