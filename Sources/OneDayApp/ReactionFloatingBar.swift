import OneDayCore
import OneDayDesign
import SwiftUI

/// 反应浮排会话（DESIGN §343／§346）：一次长按
/// 一份——呈现时刻组装的菜单数据（ChatView.
/// makeData 单源产物）、挂载点全局帧（快照原位对
/// 齐的定位原点）、阶段状态机。投递只经本类：状
/// 态机放行（deliverReaction/deliverAction）才调
/// data.onPickReaction／条目自带 action，错序点
/// 按（收起后残留点按等）不双投
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
        // 定），进场即 bar 阶段（三层同呈）
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

    /// 点动作卡条目：状态机放行才执行条目自带
    /// action（与系统菜单同一闭包路由）、返回
    /// true；阶段不合返回 false、不执行
    func pickAction(_ item: ChatRowActionItem) -> Bool {
        guard machine.pickAction() == .deliverAction
        else { return false }
        item.action()
        return true
    }
}

/// 反应药丸浮排（DESIGN §343／§346）：Message-
/// Reactions.palette 全集单排陈列＋排尾「＋」全
/// 集入口；自己的现反应以 primaryTint 底色标出
/// （与 ChatReactionViews 悬挂 pill 的 own 段同
/// 口径）；面色/描边/影与悬挂 pill 同族（Palette.
/// surface＋pageBG 描边）。每枚带 VoiceOver 标
/// 签：未点走「反应：%@」、已点走悬挂 pill 既有
/// 口径「你的反应：%@，点按撤回」（点按语义同为
/// toggle 撤回——ChatView.toggleReaction 单点收
/// 口）。「＋」开系统半页 sheet 呈 ReactionEmoji-
/// Catalog.morePalette 网格，选中经同一 onPick
/// 投递路落反应（sheet 关净后才投递、防两面同拍
/// 打架）
struct ReactionFloatingBarView: View {
    let ownEmoji: String?
    let onPick: (String) -> Void

    @State private var showsAllEmojis = false
    @State private var pendingPick: String?

    /// 单枚药丸边长（视觉 40＋排布凑点按面）
    static let pillSide: CGFloat = 40
    /// 浮排整体宽（palette 全集＋「＋」一格＋左右
    /// 内边距 6×2）
    static var barWidth: CGFloat {
        CGFloat(MessageReactions.palette.count + 1)
            * pillSide + 12
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
            plusButton
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
        .sheet(
            isPresented: $showsAllEmojis,
            onDismiss: deliverPendingPick
        ) {
            ReactionEmojiPickerView(ownEmoji: ownEmoji) { emoji in
                pendingPick = emoji
                showsAllEmojis = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    /// 「＋」全集入口（Muse 同位：排右端独立圆面）
    private var plusButton: some View {
        Button {
            showsAllEmojis = true
        } label: {
            ZStack {
                Circle().fill(Palette.pageBG)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 34, height: 34)
            .frame(
                width: Self.pillSide,
                height: Self.pillSide
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("更多反应"))
    }

    /// 半页选中先暂存、sheet 关净再投递（投递即关
    /// 整个呈现，两面同拍收起会打架）；取消半页
    /// （pendingPick 为空）不投递、浮排仍在场
    private func deliverPendingPick() {
        guard let emoji = pendingPick else { return }
        pendingPick = nil
        onPick(emoji)
    }

    private func label(for emoji: String) -> String {
        emoji == ownEmoji
            ? L10n.format("你的反应：%@，点按撤回", emoji)
            : L10n.format("反应：%@", emoji)
    }
}

/// 反应全集半页（DESIGN §346）：ReactionEmoji-
/// Catalog.morePalette 网格陈列；自己的现反应以
/// primaryTint 底色标出（与药丸同口径）；选中即
/// 回调（投递时序由浮排的 sheet onDismiss 收口）
struct ReactionEmojiPickerView: View {
    let ownEmoji: String?
    let onPick: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 44), spacing: 4)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("全部反应"))
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(
                        ReactionEmojiCatalog.morePalette,
                        id: \.self
                    ) { emoji in
                        Button {
                            onPick(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 26))
                                .frame(width: 44, height: 44)
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
                .padding(12)
            }
        }
    }

    private func label(for emoji: String) -> String {
        emoji == ownEmoji
            ? L10n.format("你的反应：%@，点按撤回", emoji)
            : L10n.format("反应：%@", emoji)
    }
}

/// 动作卡（DESIGN §346）：与药丸排同呈的自绘动
/// 作面——条目/顺序/图标/危险色逐项走 ChatRow-
/// ActionSheetData.actionItems() 单源（图标随项
/// 自带 systemImage、危险项 isDestructive 走
/// Palette.danger）；卡面与药丸同族（Palette.
/// surface＋pageBG 描边＋同款影）。行高 44（HIG
/// 点按面）、宽＝视口宽 ×0.625（Muse 量测约六成
/// 屏宽）
struct ReactionActionCardView: View {
    let items: [ChatRowActionItem]
    let onPick: (ChatRowActionItem) -> Void

    static let rowHeight: CGFloat = 44
    static let verticalPadding: CGFloat = 6
    static let widthFraction: CGFloat = 0.625

    static func cardSize(
        itemCount: Int, viewportWidth: CGFloat
    ) -> CGSize {
        CGSize(
            width: viewportWidth * widthFraction,
            height: verticalPadding * 2
                + rowHeight * CGFloat(itemCount)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    onPick(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 17))
                            .frame(width: 24)
                        Text(item.title)
                            .font(.system(size: 17))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(
                        item.isDestructive
                            ? Palette.danger
                            : Palette.ink
                    )
                    .padding(.horizontal, 16)
                    .frame(height: Self.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: 24, style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24, style: .continuous
            )
            .strokeBorder(Palette.pageBG, lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
    }
}

/// 浮排布局产物（DESIGN §346）：药丸原点／动作卡
/// 原点与尺寸／快照可见带（全局坐标）＋两端裁切
/// 标记（视图层据此挂渐隐 mask）
struct ReactionBarLayout: Equatable {
    var barOrigin: CGPoint
    var cardOrigin: CGPoint
    var cardSize: CGSize
    var snapshotVisibleRect: CGRect
    var clipsTop: Bool
    var clipsBottom: Bool
}

/// 浮排定位（纯函数）：
/// - barOrigin（§343 第一步）：只按消息框＋屏幕
///   尺寸算——优先上方（间距 8）、上方不足改下
///   方；横向按气泡对齐后夹进屏幕 8pt 安全边。
///   本函数逐值保留作回归锚（短消息在安全区内时
///   与 layout 的纵向结果一致）
/// - layout（§346 立、§386 改纵向求解）：入参
///   补安全区视口矩形，一次算齐药丸/动作卡/快
///   照带，三层互不重叠且完整落在安全区内。纵
///   向改顺序求解：药丸先独立锚定预览（上方贴
///   合／钉安全顶二态、不被卡否决），动作卡后
///   从属求解（贴消息下方→钉安全底→药丸上方成
///   摞→退化硬钳）；§346 的联合求解与「卡恒在
///   药丸下方」不变量自 §386 起退役
enum ReactionBarPlacement {
    /// 层间与对消息的统一间距（现行 8pt 口径）
    static let gap: CGFloat = 8

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

    static func layout(
        sourceFrame: CGRect,
        alignsTrailing: Bool,
        viewport: CGRect,
        itemCount: Int
    ) -> ReactionBarLayout {
        let barW = ReactionFloatingBarView.barWidth
        let barH = ReactionFloatingBarView.barHeight
        let cardSize = ReactionActionCardView.cardSize(
            itemCount: itemCount,
            viewportWidth: viewport.width
        )
        let cardH = cardSize.height
        let safeTop = viewport.minY
        let safeBottom = viewport.maxY

        // 横向：药丸按气泡对齐、卡左对齐消息左缘，
        // 各自夹进视口左右 8pt
        var barX = alignsTrailing
            ? sourceFrame.maxX - barW
            : sourceFrame.minX
        barX = min(
            max(barX, viewport.minX + gap),
            max(
                viewport.minX + gap,
                viewport.maxX - gap - barW
            )
        )
        var cardX = sourceFrame.minX
        cardX = min(
            max(cardX, viewport.minX + gap),
            max(
                viewport.minX + gap,
                viewport.maxX - gap - cardSize.width
            )
        )

        // 药丸纵位（DESIGN §386：独立锚定预览、先
        // 行定死）：上方贴合（帧顶 − gap − 药丸
        // 高，与第一步口径同值）；上方不足（预览
        // 顶出屏或贴顶）钉安全区顶部。药丸不读卡
        // 尺寸、不被卡落位否决——§346 联合求解下
        // 贴顶短消息药丸落消息下方、中下段消息药
        // 丸被钉屏顶脱离预览，两偏差本包收掉
        let yAbove = sourceFrame.minY - gap - barH
        let finalBarY = yAbove >= safeTop
            ? yAbove
            : safeTop + gap
        let pillBottom = finalBarY + barH

        // 动作卡纵位（从属求解、恒不与药丸重
        // 叠）：C1 贴消息下方 → C2 钉安全区底部
        // 上方 → C3 药丸上方成摞（贴底消息：下方
        // 与钉底都被药丸占位否决时卡退到药丸上
        // 方、预览带不让位）→ C4 退化硬钳（视口
        // 高不足药丸＋卡＋间距、横屏＋多项数才
        // 达：沿 §346 兜底，两层夹回视口、贴合
        // 让位入屏）
        let yBelow = sourceFrame.maxY + gap
        /// 卡钉安全区底部上方
        let cardPinBottom = safeBottom - gap - cardH
        var cardY: CGFloat?
        if yBelow + cardH <= safeBottom - gap,
           yBelow >= pillBottom + gap {
            cardY = yBelow
        } else if cardPinBottom >= pillBottom + gap {
            cardY = cardPinBottom
        } else if finalBarY - gap - cardH >= safeTop {
            cardY = finalBarY - gap - cardH
        }
        let finalCardY = cardY ?? min(
            max(cardPinBottom, pillBottom + gap),
            max(safeTop, safeBottom - cardH)
        )

        // 快照可见带：帧∩视口的纵向跨度去掉药丸/
        // 卡的占位段（各向外扩 gap），取最长段——
        // 长文时即药丸与卡之间，溢出两端裁切
        let lo = max(sourceFrame.minY, safeTop)
        let hi = min(sourceFrame.maxY, safeBottom)
        var segments: [(CGFloat, CGFloat)] =
            hi > lo ? [(lo, hi)] : []
        for span in [
            (finalBarY - gap, finalBarY + barH + gap),
            (finalCardY - gap, finalCardY + cardH + gap),
        ] {
            segments = segments.flatMap { seg in
                if span.1 <= seg.0 || span.0 >= seg.1 {
                    return [seg]
                }
                var out: [(CGFloat, CGFloat)] = []
                if span.0 > seg.0 {
                    out.append((seg.0, span.0))
                }
                if span.1 < seg.1 {
                    out.append((span.1, seg.1))
                }
                return out
            }
        }
        let best = segments.max {
            ($0.1 - $0.0) < ($1.1 - $1.0)
        }
        let visible: CGRect
        if let best {
            visible = CGRect(
                x: sourceFrame.minX,
                y: best.0,
                width: sourceFrame.width,
                height: best.1 - best.0
            )
        } else {
            // 帧在视口内已无净空段（极端贴边行）：
            // 快照全钳（高 0），药丸与卡功能不受影响
            visible = CGRect(
                x: sourceFrame.minX,
                y: min(
                    max(sourceFrame.minY, safeTop),
                    safeBottom
                ),
                width: sourceFrame.width,
                height: 0
            )
        }
        return ReactionBarLayout(
            barOrigin: CGPoint(x: barX, y: finalBarY),
            cardOrigin: CGPoint(x: cardX, y: finalCardY),
            cardSize: cardSize,
            snapshotVisibleRect: visible,
            clipsTop: visible.minY
                > sourceFrame.minY + 0.5,
            clipsBottom: visible.maxY
                < sourceFrame.maxY - 0.5
        )
    }
}
