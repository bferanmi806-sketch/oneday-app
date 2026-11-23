import Foundation

/// 发送舱右端状态机（0.25.0，交互与动效专包立）：
/// 胶囊右端在三态间切换——空输入出裸麦克风占位、
/// 有可发送内容出发送箭头、流式中出停止键。三态判
/// 定原散在 ChatView.trailingControl 的条件里，本枚
/// 举收敛为纯函数：视图只读它选形态与驱动切换动画
/// （mic↔发送/停止的 opacity 交叉淡化以本枚举为动画
/// 值），判定口径由单测把守。旧口径「流式优先于可
/// 发送——流式中即使输入框已有字，右端也必须是停止
/// 键」自修复包二锁一（§419）改判：流式中有字出双钮
/// （发送主键＋停止小钮），右端不再由停止键独占。
public enum ComposerTrailingState: Equatable, CaseIterable {
    /// 空输入：裸麦克风符号占位（语音未接入）
    case mic
    /// 有可发送内容（文字或附件）：发送箭头
    case send
    /// 流式生成中：停止键
    case stop
    /// 流式生成中且已有可发送内容：双钮态（修复包
    /// 二锁一）——主键仍是发送箭头（点按走排队落
    /// 位）、停止降为左侧裸符号小钮；流式中输入为
    /// 空仍归 .stop 单键，不出双钮
    case stopAndSend

    /// 判定序：流式且可发送 → 双钮；流式不可发送
    /// → 停止；非流式可发送 → 发送；否则占位（麦
    /// 克风）
    public static func resolve(
        isStreaming: Bool, canSend: Bool
    ) -> ComposerTrailingState {
        if isStreaming {
            return canSend ? .stopAndSend : .stop
        }
        return canSend ? .send : .mic
    }

    /// 是否为圆盘键形态（发送/停止/双钮的主键共用
    /// 同一颗圆盘键，内部符号以 symbolEffect 形变
    /// 切换；麦克风是裸符号、无圆盘）
    public var isDiscKey: Bool {
        self != .mic
    }
}
