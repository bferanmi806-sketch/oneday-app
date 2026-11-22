import Foundation

// MARK: - 反应浮排开关（DESIGN §343）

/// 反应浮排特性开关（反应浮排包第一步）：长按消息
/// 先浮出反应药丸排（Muse 形态），动作列表仍走
/// 系统面。UserDefaults 布尔键，**缺省 true**＝浮
/// 排开；显式 false 回 0.50.80 形态（反应走系统菜
/// 单「添加反应」子菜单）——回滚不发版：设置→外
/// 观→回复呈现可关。存取口径与 ChatStreaming-
/// Feature 同（键缺省与显式 true 同义、只有显式
/// false 才关）
public enum ChatReactionsFloatingBarFeature {
    public static let defaultsKey = "chat.reactions.floatingBar"

    public static func isEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil
        else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}

/// 长按呈现路由（纯函数单点）：开关开且本条可反
/// 应才走浮排；其余一律系统菜单原形态——不可反
/// 应条目（未钉桩/未落定）不因浮排开关改变呈现面
public enum ReactionBarRoute: Equatable, Sendable {
    case systemMenu
    case floatingBar
}

public enum ReactionBarRouting {
    public static func route(
        flagEnabled: Bool, canReact: Bool
    ) -> ReactionBarRoute {
        flagEnabled && canReact ? .floatingBar : .systemMenu
    }
}

// MARK: - 浮排呈现状态机

/// 浮排阶段：idle（无呈现）／bar（药丸排在场）／
/// actionSheet（已转交动作面、浮排已关）
public enum ReactionBarPhase: Equatable, Sendable {
    case idle, bar, actionSheet
}

/// 状态机迁移产出：视图/会话层据此执行呈现与投
/// 递——机内不碰数据与回调，反应投递由会话层在
/// 收到 deliverReaction 后调 data.onPickReaction
public enum ReactionBarEffect: Equatable, Sendable {
    case presentBar, presentActionSheet, deliverReaction
}

/// 反应浮排呈现状态机（纯值、无副作用）：长按进
/// bar（可反应）或直达 actionSheet（不可反应——
/// 路由层已先拦，本机保留完备迁移防误用）；bar
/// 内点药丸＝投递反应并回 idle；点快照/空白＝转
/// 交动作面；动作面关净回 idle。阶段不合的事件
/// 一律忽略（返回 nil），不许错序投递（防双投）
public struct ReactionBarStateMachine: Equatable, Sendable {
    public private(set) var phase: ReactionBarPhase = .idle

    public init() {}

    @discardableResult
    public mutating func longPress(
        canReact: Bool
    ) -> ReactionBarEffect? {
        guard phase == .idle else { return nil }
        if canReact {
            phase = .bar
            return .presentBar
        }
        phase = .actionSheet
        return .presentActionSheet
    }

    @discardableResult
    public mutating func pickReaction() -> ReactionBarEffect? {
        guard phase == .bar else { return nil }
        phase = .idle
        return .deliverReaction
    }

    @discardableResult
    public mutating func requestActions() -> ReactionBarEffect? {
        guard phase == .bar else { return nil }
        phase = .actionSheet
        return .presentActionSheet
    }

    /// 呈现被外部关闭（动作面关净/浮排被系统收
    /// 起）：任意非 idle 阶段回 idle；已 idle 返回
    /// false
    @discardableResult
    public mutating func dismiss() -> Bool {
        guard phase != .idle else { return false }
        phase = .idle
        return true
    }
}
