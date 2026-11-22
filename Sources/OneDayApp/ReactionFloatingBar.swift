import OneDayCore
import OneDayDesign
import SwiftUI

/// 反应浮排会话（DESIGN §343）：一次长按一份——
/// 呈现时刻组装的菜单数据（ChatView.makeData 单
/// 源产物）、挂载点全局帧（快照原位对齐的定位原
/// 点）、阶段状态机。点药丸的投递只经本类：状态
/// 机放行（deliverReaction）才调 data.onPick-
/// Reaction，错序点按（转交动作后残留点按等）不
/// 双投
@MainActor
final class ReactionBarSession: ObservableObject, Identifiable {
    let id = UUID()
    let entryID: UUID
    let data: ChatRowActionSheetData
    /// 长按挂载点在屏幕（.global）坐标系的帧
    let sourceFrame: CGRect
    /// 用户消息（右对齐气泡）：药丸排右缘对齐帧右缘
    let alignsTrailing: Bool

    private(set) var machine = ReactionBarStateMachine()

    init(
        entryID: UUID,
        data: ChatRowActionSheetData,
        sourceFrame: CGRect,
        alignsTrailing: Bool
    ) {
        self.entryID = entryID
        self.data = data
        self.sourceFrame = sourceFrame
        self.alignsTrailing = alignsTrailing
        // 会话只在浮排序由成立时创建（开关开＋可反
        // 应已由 ChatView.messageMenu 路由单点裁
        // 定），进场即 bar 阶段
        machine.longPress(canReact: true)
    }

    var phase: ReactionBarPhase { machine.phase }

    /// 点药丸：状态机放行才投递、返回 true（视图
    /// 层据此关浮排）；阶段不合返回 false、不投递
    func pick(_ emoji: String) -> Bool {
        guard machine.pickReaction() == .deliverReaction
        else { return false }
        data.onPickReaction(emoji)
        return true
    }

    /// 点快照/空白转交动作面：返回 true 表示已转
    /// 交（视图层关浮排后呈动作面）；阶段不合 false
    func requestActions() -> Bool {
        machine.requestActions() == .presentActionSheet
    }
}

/// 反应药丸浮排（DESIGN §343）：MessageReactions.
/// palette 全集单排陈列；自己的现反应以 primary-
/// Tint 底色标出（与 ChatReactionViews 悬挂 pill
/// 的 own 段同口径）；面色/描边/影与悬挂 pill 同
/// 族（Palette.surface＋pageBG 描边）。每枚带
/// VoiceOver 标签：未点走「反应：%@」、已点走悬
/// 挂 pill 既有口径「你的反应：%@，点按撤回」
/// （点按语义同为 toggle 撤回——ChatView.toggle-
/// Reaction 单点收口）
struct ReactionFloatingBarView: View {
    let ownEmoji: String?
    let onPick: (String) -> Void

    /// 单枚药丸边长（视觉 40＋排布凑点按面）
    static let pillSide: CGFloat = 40
    /// 浮排整体宽（全集单排＋左右内边距 6×2）
    static var barWidth: CGFloat {
        CGFloat(MessageReactions.palette.count) * pillSide + 12
    }
    /// 浮排整体高（药丸 40＋纵向内边距 4×2）
    static let barHeight: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MessageReactions.palette, id: \.self) { emoji in
                Button {
                    onPick(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 20))
                        .frame(
                            width: Self.pillSide,
                            height: Self.pillSide
                        )
                        .background(
                            emoji == ownEmoji
                                ? Palette.primaryTint
                                : Color.clear,
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: emoji))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Palette.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                Palette.pageBG, lineWidth: 1.5
            )
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
    }

    private func label(for emoji: String) -> String {
        emoji == ownEmoji
            ? L10n.format("你的反应：%@，点按撤回", emoji)
            : L10n.format("反应：%@", emoji)
    }
}

/// 浮排定位（纯函数）：药丸排优先置于快照上方
/// （间距 8），上方空间不足（原点 < 8 安全边）改
/// 置下方；横向按气泡对齐（用户行右对齐/助手行
/// 左对齐）后夹进屏幕左右 8pt 安全边
enum ReactionBarPlacement {
    static func barOrigin(
        sourceFrame: CGRect,
        alignsTrailing: Bool,
        screenSize: CGSize
    ) -> CGPoint {
        let width = ReactionFloatingBarView.barWidth
        var x = alignsTrailing
            ? sourceFrame.maxX - width
            : sourceFrame.minX
        x = min(
            max(x, 8),
            max(8, screenSize.width - width - 8)
        )
        let above = sourceFrame.minY - 8
            - ReactionFloatingBarView.barHeight
        let y = above >= 8 ? above : sourceFrame.maxY + 8
        return CGPoint(x: x, y: y)
    }
}
