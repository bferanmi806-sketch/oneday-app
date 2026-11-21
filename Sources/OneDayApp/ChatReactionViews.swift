import OneDayCore
import OneDayDesign
import SwiftUI

/// 反应几何单源（台账 187）：pill 高 28、压气泡底
/// 角半身悬出（悬出净深 14）、行高为悬出再留 2pt
/// 呼吸共预留 16——呈现（本文件 pill 与 ChatView
/// 两支的 overlay 偏移）与行高合成器（ChatNative-
/// RowHeight.reactionReserve）同读本匣，不许两处
/// 各写一份数字（§329 行高单权威的 facet 纪律：
/// 预留与实际悬出必须逐值同源，差一像素即行高与
/// 渲染打架）
enum ChatReactionMetrics {
    static let pillHeight: CGFloat = 28
    static let hangDepth: CGFloat = 14
    static let rowReserve: CGFloat = 16
    /// pill 沿气泡底边向内让位（不贴死角）
    static let cornerInset: CGFloat = 8
}

/// 反应 pill（台账 187，照 OpenBot 气泡底角形态）：
/// 悬挂于气泡底角·朝中线侧（§334 正名：AI 行右
/// 下、用户行左下；挂载点在 ChatView 两支的
/// overlay）；面色走既有 surface 令
/// 牌、描边走页面底色（在气泡上切出悬挂感）、色
/// 调与 184 气泡档同源（自己的段以 primaryTint 轻
/// 染标示）。双 author 都渲染：自己的段可点撤回
/// （走 ChatView.applyReaction 单写口），助手段只
/// 读；两段各有 VoiceOver 标签（读屏发现性，设计
/// 报告无障碍行口径）
struct ReactionPillView: View {
    let reactions: [MessageReaction]
    /// 点自己的段（撤回自己的反应）
    let onClearOwn: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(
                Array(reactions.enumerated()),
                id: \.offset
            ) { _, reaction in
                segment(reaction)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: ChatReactionMetrics.pillHeight)
        .background(
            Palette.surface, in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                Palette.pageBG, lineWidth: 1.5
            )
        }
        .shadow(
            color: .black.opacity(0.10), radius: 4, y: 1
        )
    }

    @ViewBuilder
    private func segment(
        _ reaction: MessageReaction
    ) -> some View {
        if reaction.isOwn {
            Button(action: onClearOwn) {
                Text(reaction.emoji)
                    .font(.system(size: 14))
                    .padding(.horizontal, 4)
                    .background(
                        Palette.primaryTint, in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                L10n.format(
                    "你的反应：%@，点按撤回", reaction.emoji
                )
            )
        } else {
            Text(reaction.emoji)
                .font(.system(size: 14))
                .padding(.horizontal, 4)
                .accessibilityLabel(
                    L10n.format("助手反应：%@", reaction.emoji)
                )
        }
    }
}
