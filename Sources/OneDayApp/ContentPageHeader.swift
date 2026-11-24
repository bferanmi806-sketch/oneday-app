import OneDayCore
import OneDayDesign
import SwiftUI

/// 内容页页头簇（§486 立，审计 three-pages-20261124
/// §三总表）：动态/点子两页共用同一簇——左抽屉圆钮
/// ＋居中身份区（大头像 hero＋身份胶囊压下沿，与聊
/// 天页 headerIdentityHero 同构成同数值）＋右页专属
/// 圆钮。审计定因：五内容页页头/标题层此前无单源组
/// 件在管（点子页整簇缺失、动态页标题低一档），本件
/// 即单源；目标页/中枢页后续接入同件（各线合版时对
/// 齐），不在本节扩散。
/// 滚动收起（动态页，§486.4）：collapsed 时身份区与
/// 抽屉钮淡出、带高收到圆钮行（44），右侧动作钮留
/// 守——照 Muse 动态页滚动态（胶囊簇整簇收起、滑
/// 杆圆钮留守、标题＋字段钉顶）。点子页恒不收起。
struct ContentPageHeader<Trailing: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 滚动收起态（宿主以内容滚动偏移驱动，口径在
    /// 宿主页；本件只管形态）
    var collapsed: Bool = false
    var onOpenHub: () -> Void
    @ViewBuilder var trailing: Trailing

    /// 身份区总高（与聊天页同构成）：头像 67＋胶囊
    /// 44－重叠 8＝103
    private static var heroHeight: CGFloat { 103 }
    /// 收起后带高＝圆钮行 44
    private static var rowHeight: CGFloat {
        OneDayMetrics.minTapTarget
    }

    var body: some View {
        ZStack(alignment: .top) {
            hero
                .opacity(collapsed ? 0 : 1)
                .accessibilityHidden(collapsed)
            HStack(alignment: .top) {
                PageHeaderCircleButton(
                    symbol: "line.3.horizontal",
                    label: "会话列表"
                ) {
                    appState.router.drawerPresented = true
                }
                .opacity(collapsed ? 0 : 1)
                .accessibilityHidden(collapsed)
                Spacer()
                trailing
            }
            // 圆钮行与头像同心：钮 44 居头像 67 的中
            // 位（(67－44)/2≈12＝spacingSM）；收起后
            // 顶距归零、圆钮贴带顶留守（参照滚动态）
            .padding(
                .top, collapsed ? 0 : OneDayMetrics.spacingSM
            )
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.top, OneDayMetrics.spacingXS)
        .frame(
            height: (collapsed ? Self.rowHeight : Self.heroHeight)
                + OneDayMetrics.spacingXS
        )
        .clipped()
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: collapsed
        )
    }

    /// 居中身份区：与聊天页 headerIdentityHero 逐值
    /// 同构成（HubAvatarButton hero 档＋HubIdentity-
    /// Capsule 压下沿 8）——同件同数，不许在本件另
    /// 定一套。胶囊小字数据源与聊天页同路（§474 单
    /// 源方向：liveActivityPhrase 优先、回落连接状态
    /// 词；小字口径归 §474，本件只消费）
    private var hero: some View {
        ZStack(alignment: .bottom) {
            HubAvatarButton(
                avatar: appState.agentAvatarImage,
                displayName: appState.agentDisplayName,
                statusWord: statusWord,
                statusColor: statusColor,
                avatarPointSize: OneDayMetrics.avatarChatHero,
                onOpenHub: onOpenHub
            )
            .padding(.bottom, 36)

            HubIdentityCapsule(
                displayName: appState.agentDisplayName,
                statusWord: appState.liveActivityPhrase ?? statusWord,
                onOpenHub: onOpenHub
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// 连接状态词（与文件页 IdentityAnchor 同口径：
    /// config 缺位＝未连接）
    private var statusWord: String {
        appState.config == nil ? "未连接" : "在线"
    }

    private var statusColor: Color {
        appState.config == nil ? Palette.inkMuted : Palette.success
    }
}

/// 页头圆钮（与文件页 headerCircleButton／聊天页顶
/// 栏圆钮同族材质：系统玻璃盘 40＋命中域外扩 44）
struct PageHeaderCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(
                    size: HeaderButtonSpec.glyphPointSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: HeaderButtonSpec.diameter,
                    height: HeaderButtonSpec.diameter
                )
                .glassEffect(.regular, in: Circle())
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(label)
    }
}
