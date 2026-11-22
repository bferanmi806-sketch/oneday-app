import OneDayCore
import SwiftUI
import XCTest
@testable import OneDayApp

/// 反应浮排验收（DESIGN §343／§346）：开关口径
/// （缺省开/显式关回子菜单形态）、长按路由、呈现
/// 状态机（§346 三层同呈语义）、会话投递单点
/// （错序不双投）、浮排定位（第一步旧函数回归锚
/// ＋§346 视口钳制布局）、全集目录与卡量测钉。
/// 真机观感（长文三层/衔接帧/竞速/深色大字号）
/// CI 无信号、归用户真机门
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

    // MARK: - 状态机（§346 同呈语义）

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
        XCTAssertEqual(machine.pickAction(), .deliverAction)
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(
            machine.longPress(canReact: true), .presentBar
        )
        XCTAssertTrue(machine.dismiss())
        XCTAssertEqual(machine.phase, .idle)
    }

    func testMachineIllegalEvents() {
        var machine = ReactionBarStateMachine()
        // idle 下的错序事件全忽略
        XCTAssertNil(machine.pickReaction())
        XCTAssertNil(machine.pickAction())
        XCTAssertFalse(machine.dismiss())
        // 不可反应长按不进呈现（路由层先拦、§346
        // 起本机无直达动作面迁移）
        XCTAssertNil(machine.longPress(canReact: false))
        XCTAssertEqual(machine.phase, .idle)
        // bar 在场时重复长按忽略
        XCTAssertEqual(
            machine.longPress(canReact: true), .presentBar
        )
        XCTAssertNil(machine.longPress(canReact: true))
        XCTAssertEqual(machine.phase, .bar)
        // 投递后回 idle、后续点按全忽略（防双投）
        XCTAssertEqual(machine.pickAction(), .deliverAction)
        XCTAssertNil(machine.pickReaction())
        XCTAssertNil(machine.pickAction())
    }

    // MARK: - 会话投递（药丸/动作卡回调钉）

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

    /// 动作卡条目：经会话单点执行条目自带 action
    /// （与系统菜单同一闭包路由）、只执行一次；执
    /// 行后药丸投递与再点条目全关（防双投）
    func testSessionActionExecutesOnceAndBlocksLaterPick() {
        var picked: [String] = []
        var acted = 0
        let session = ReactionBarSession(
            entryID: UUID(),
            data: Self.dummyData { picked.append($0) },
            sourceFrame: CGRect(
                x: 100, y: 300, width: 220, height: 60
            ),
            alignsTrailing: false
        )
        let item = ChatRowActionItem(
            kind: .reply, title: "回复",
            systemImage: "arrowshape.turn.up.left",
            action: { acted += 1 }
        )
        XCTAssertTrue(session.pickAction(item))
        XCTAssertEqual(acted, 1)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(session.pick("🔥"))
        XCTAssertFalse(session.pickAction(item))
        XCTAssertEqual(acted, 1)
        XCTAssertTrue(picked.isEmpty)
    }

    /// 先落反应则动作路关死（互斥单投）
    func testSessionPickBlocksLaterAction() {
        var acted = 0
        let session = ReactionBarSession(
            entryID: UUID(),
            data: Self.dummyData(),
            sourceFrame: .zero,
            alignsTrailing: true
        )
        let item = ChatRowActionItem(
            kind: .copy, title: "复制",
            systemImage: "doc.on.doc",
            action: { acted += 1 }
        )
        XCTAssertTrue(session.pick("🔥"))
        XCTAssertFalse(session.pickAction(item))
        XCTAssertEqual(acted, 0)
    }

    // MARK: - 定位（第一步旧函数·回归锚）

    func testPlacementAboveTrailingAndClamp() {
        let screen = CGSize(width: 402, height: 874)
        // 助手行（左对齐）、上方空间足 → 上方＋左对齐
        // （§346：排宽随「＋」增至 372，x=52 时右缘
        // 出屏→按原夹屏规则夹到 22；纵向逐值不变）
        var origin = ReactionBarPlacement.barOrigin(
            sourceFrame: CGRect(
                x: 52, y: 400, width: 240, height: 60
            ),
            alignsTrailing: false,
            screenSize: screen
        )
        XCTAssertEqual(origin.x, 22)
        XCTAssertEqual(
            origin.y,
            400 - 8 - ReactionFloatingBarView.barHeight
        )
        // 用户行（右对齐）→ 右缘对齐（同因排宽增
        // 长、右对齐原点出左界→夹回 8）
        origin = ReactionBarPlacement.barOrigin(
            sourceFrame: CGRect(
                x: 110, y: 400, width: 240, height: 60
            ),
            alignsTrailing: true,
            screenSize: screen
        )
        XCTAssertEqual(origin.x, 8)
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

    // MARK: - 视口钳制布局（§346）

    /// 测试视口：402×874 机型安全区（top 59 /
    /// bottom 34）
    private var testViewport: CGRect {
        CGRect(x: 0, y: 59, width: 402, height: 781)
    }

    /// 正常中屏短消息：药丸纵向与第一步旧函数逐值
    /// 一致、卡贴消息下方、快照全帧无裁切
    func testLayoutNormalAboveMatchesLegacyY() {
        let frame = CGRect(
            x: 52, y: 400, width: 240, height: 60
        )
        let layout = ReactionBarPlacement.layout(
            sourceFrame: frame,
            alignsTrailing: false,
            viewport: testViewport,
            itemCount: 5
        )
        let legacy = ReactionBarPlacement.barOrigin(
            sourceFrame: frame,
            alignsTrailing: false,
            screenSize: CGSize(width: 402, height: 874)
        )
        XCTAssertEqual(layout.barOrigin.y, legacy.y)
        XCTAssertEqual(layout.barOrigin.y, 344)
        XCTAssertEqual(layout.barOrigin.x, 22)
        XCTAssertEqual(
            layout.cardOrigin, CGPoint(x: 52, y: 468)
        )
        XCTAssertEqual(
            layout.cardSize,
            CGSize(width: 251.25, height: 232)
        )
        XCTAssertEqual(layout.snapshotVisibleRect, frame)
        XCTAssertFalse(layout.clipsTop)
        XCTAssertFalse(layout.clipsBottom)
    }

    /// 长文顶出屏：药丸钉安全区顶部、卡钉安全区底
    /// 部上方、快照钳在两层之间两端裁切
    func testLayoutTallTopOutPinsBarAndCard() {
        let frame = CGRect(
            x: 52, y: -300, width: 240, height: 900
        )
        let layout = ReactionBarPlacement.layout(
            sourceFrame: frame,
            alignsTrailing: false,
            viewport: testViewport,
            itemCount: 5
        )
        XCTAssertEqual(
            layout.barOrigin, CGPoint(x: 22, y: 67)
        )
        XCTAssertEqual(
            layout.cardOrigin, CGPoint(x: 52, y: 600)
        )
        XCTAssertEqual(
            layout.snapshotVisibleRect,
            CGRect(x: 52, y: 123, width: 240, height: 469)
        )
        XCTAssertTrue(layout.clipsTop)
        XCTAssertTrue(layout.clipsBottom)
    }

    /// 长文底出屏（顶在屏内）：药丸仍取消息上方、
    /// 卡钉底、快照只裁下端
    func testLayoutBottomOutKeepsBarAbove() {
        let frame = CGRect(
            x: 52, y: 500, width: 240, height: 700
        )
        let layout = ReactionBarPlacement.layout(
            sourceFrame: frame,
            alignsTrailing: false,
            viewport: testViewport,
            itemCount: 5
        )
        XCTAssertEqual(
            layout.barOrigin, CGPoint(x: 22, y: 444)
        )
        XCTAssertEqual(
            layout.cardOrigin, CGPoint(x: 52, y: 600)
        )
        XCTAssertEqual(
            layout.snapshotVisibleRect,
            CGRect(x: 52, y: 500, width: 240, height: 92)
        )
        XCTAssertFalse(layout.clipsTop)
        XCTAssertTrue(layout.clipsBottom)
    }

    /// 贴顶短消息：上方放不下→药丸置消息下方（与
    /// 第一步下方口径同值）、卡顺次其下、快照全帧
    func testLayoutNearTopShortGoesBelow() {
        let frame = CGRect(
            x: 52, y: 100, width: 240, height: 60
        )
        let layout = ReactionBarPlacement.layout(
            sourceFrame: frame,
            alignsTrailing: false,
            viewport: testViewport,
            itemCount: 5
        )
        XCTAssertEqual(
            layout.barOrigin, CGPoint(x: 22, y: 168)
        )
        XCTAssertEqual(
            layout.cardOrigin, CGPoint(x: 52, y: 224)
        )
        XCTAssertEqual(layout.snapshotVisibleRect, frame)
        XCTAssertFalse(layout.clipsTop)
        XCTAssertFalse(layout.clipsBottom)
    }

    /// 贴底消息：上方容不下卡→药丸钉顶、卡让位到
    /// 消息上方，三层仍隔离、快照全帧
    func testLayoutBottomMessageCardAboveFrame() {
        let frame = CGRect(
            x: 52, y: 700, width: 240, height: 130
        )
        let layout = ReactionBarPlacement.layout(
            sourceFrame: frame,
            alignsTrailing: false,
            viewport: testViewport,
            itemCount: 4
        )
        XCTAssertEqual(
            layout.barOrigin, CGPoint(x: 22, y: 67)
        )
        XCTAssertEqual(
            layout.cardOrigin, CGPoint(x: 52, y: 504)
        )
        XCTAssertEqual(layout.snapshotVisibleRect, frame)
        XCTAssertFalse(layout.clipsTop)
        XCTAssertFalse(layout.clipsBottom)
    }

    /// 整框出屏（上下皆出）：药丸钉顶、卡钉底、快
    /// 照取中间带
    func testLayoutWholeFrameOut() {
        let frame = CGRect(
            x: 52, y: -100, width: 240, height: 1200
        )
        let layout = ReactionBarPlacement.layout(
            sourceFrame: frame,
            alignsTrailing: false,
            viewport: testViewport,
            itemCount: 6
        )
        XCTAssertEqual(
            layout.barOrigin, CGPoint(x: 22, y: 67)
        )
        XCTAssertEqual(
            layout.cardOrigin, CGPoint(x: 52, y: 556)
        )
        XCTAssertEqual(layout.cardSize.height, 276)
        XCTAssertEqual(
            layout.snapshotVisibleRect,
            CGRect(x: 52, y: 123, width: 240, height: 425)
        )
        XCTAssertTrue(layout.clipsTop)
        XCTAssertTrue(layout.clipsBottom)
    }

    /// 不变量帧矩阵：任意帧/对齐/项数下——药丸与
    /// 卡完整落在视口内、卡恒在药丸下方留 gap、可
    /// 见带与两层纵向隔离（留 gap）
    func testLayoutInvariantsAcrossFrames() {
        let frames: [CGRect] = [
            CGRect(x: 52, y: 400, width: 240, height: 60),
            CGRect(x: 110, y: 400, width: 240, height: 60),
            CGRect(x: 52, y: -300, width: 240, height: 900),
            CGRect(x: 52, y: 500, width: 240, height: 700),
            CGRect(x: 52, y: -100, width: 240, height: 1200),
            CGRect(x: 52, y: 100, width: 240, height: 60),
            CGRect(x: 52, y: 700, width: 240, height: 130),
            CGRect(x: 20, y: 59, width: 300, height: 781),
            CGRect(x: 52, y: 115, width: 240, height: 45),
            CGRect(x: 300, y: 200, width: 90, height: 40),
        ]
        for frame in frames {
            for trailing in [false, true] {
                for count in [4, 5, 6] {
                    let layout = ReactionBarPlacement.layout(
                        sourceFrame: frame,
                        alignsTrailing: trailing,
                        viewport: testViewport,
                        itemCount: count
                    )
                    let ctx = "\(frame) trailing=\(trailing) n=\(count)"
                    let bar = CGRect(
                        origin: layout.barOrigin,
                        size: CGSize(
                            width: ReactionFloatingBarView.barWidth,
                            height: ReactionFloatingBarView.barHeight
                        )
                    )
                    let card = CGRect(
                        origin: layout.cardOrigin,
                        size: layout.cardSize
                    )
                    XCTAssertTrue(
                        testViewport.contains(bar), ctx
                    )
                    XCTAssertTrue(
                        testViewport.contains(card), ctx
                    )
                    XCTAssertGreaterThanOrEqual(
                        card.minY, bar.maxY + 8 - 0.5, ctx
                    )
                    let vis = layout.snapshotVisibleRect
                    XCTAssertEqual(vis.minX, frame.minX, ctx)
                    XCTAssertEqual(vis.width, frame.width, ctx)
                    XCTAssertGreaterThanOrEqual(
                        vis.minY, testViewport.minY - 0.5, ctx
                    )
                    XCTAssertLessThanOrEqual(
                        vis.maxY, testViewport.maxY + 0.5, ctx
                    )
                    if vis.height > 0 {
                        XCTAssertTrue(
                            vis.maxY <= bar.minY - 8 + 0.5
                                || vis.minY >= bar.maxY + 8 - 0.5,
                            ctx
                        )
                        XCTAssertTrue(
                            vis.maxY <= card.minY - 8 + 0.5
                                || vis.minY >= card.maxY + 8 - 0.5,
                            ctx
                        )
                    }
                }
            }
        }
    }

    // MARK: - 全集目录与卡量测（§346）

    func testExtendedCatalogShape() {
        let catalog = ReactionEmojiCatalog.morePalette
        XCTAssertGreaterThanOrEqual(catalog.count, 80)
        XCTAssertEqual(
            Set(catalog).count, catalog.count,
            "目录无重复"
        )
        XCTAssertTrue(
            Set(catalog).isDisjoint(
                with: MessageReactions.palette
            ),
            "与药丸排样板集不重复"
        )
    }

    /// Muse 量测对位：4 项卡高 ≈187、宽 ≈屏宽
    /// 0.625；药丸排含「＋」总宽 372（量测 ≈372）
    func testCardMetricsAgainstMuseMeasure() {
        let size = ReactionActionCardView.cardSize(
            itemCount: 4, viewportWidth: 402
        )
        XCTAssertEqual(size.height, 188, accuracy: 1)
        XCTAssertEqual(size.width, 402 * 0.625)
        XCTAssertEqual(
            ReactionFloatingBarView.barWidth, 372
        )
    }
}
