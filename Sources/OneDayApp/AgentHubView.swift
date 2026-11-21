import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 枢纽页分段（规格 phase3-hub-spec §1 #9/#10）：图标
/// 纯符号、无文字；VoiceOver 读段名（Label 自带）。
/// §217（2026-11-13 用户拍板收段）：七段收四段——
/// 活动／定时／浏览器／身份（顺序即此）。任务、审
/// 核、监测三段撤出分段栏，内容并入活动段：任务与
/// 审批本就在工作台账里有同源条目（伴生采集器
/// kanban／write-gate 两源），下钻在台账详情里补齐
/// （任务详情、审批改动与原对话锚点）；审批规则本
/// 体已按 §244 归设置页权限区、本段只留审批记录
/// （归位合流 2026-11-20 注释订正）；
/// 监测变化由客户端合成同形条目（LedgerMonitor-
/// Synthesis）。三段的 Section 视图与各自 store 的
/// 段内呈现随之退役，数据面（KanbanStore/Monitors-
/// Store/AgentHubStore）保留供活动段下钻与聊天卡用。
enum HubSegment: String, CaseIterable, Identifiable {
    case activity
    case cron
    case browser
    case identity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "活动"
        case .cron: return "定时"
        case .browser: return "浏览器"
        case .identity: return "身份"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "list.bullet"
        case .cron: return "clock"
        case .browser: return "display"
        case .identity: return "touchid"
        }
    }
}

/// 智能体枢纽页（三期，规格 phase3-hub-spec）：页头
/// （圆钮行/头像/名/状态行）→ 分段 → 段内容（模型常
/// 驻区已随结构归位包撤除，见文末新注）。本视图自带
/// NavigationStack，呈现方不要再包一层。
/// 段切换只换内容区，页头常驻不动（规格 §0）。
/// 0.6.0 转正（蓝图 §4 一期）：枢纽页从「胶囊点开的
/// sheet」转正为活动格本体——mode=.activity 时留
/// 活动/任务/审核三段（任务段 0.10.0 增、监测段
/// 0.12.0 增）、撤页头
/// 圆钮行与模型常驻区（换模型
/// 入口在聊天页胶囊的模型段 Menu，硬规格不回退）；
/// mode=.sheet 保留五段全量形态，但聊天页胶囊已改道
/// 活动格、不再有 sheet 入口（不双份维护同一 UI）。
/// 0.17.0（真机五修⑤）：活动格撤销——mode=.activity
/// 改由聊天页胶囊/回告卡以 sheet 呈现（本视图自带导
/// 航栈、呈现方不外包，口径不变；下滑关 sheet 走系
/// 统拖拽指示器）；mode=.sheet 五段全量形态仍无入口、
/// 与 0.6.0 起的口径一致。
/// 0.36.22（枢纽页对齐包，用户点名学 Muse 智能体
/// 页）：呈现改整页 fullScreenCover（ChatView 侧，
/// DESIGN-V4 §89）——页头圆钮行（✕/分享）两模式统
/// 一常驻、左边缘右滑返回走系统边缘识别器桥、头像
/// 徽章改本地档案菜单（更换虚拟形象/编辑名称）；分
/// 段与段内容、数据面一律不动。
/// §155（HUB-1 枢纽全量接通，用户 2026-11-11 拍板
/// 「死面接入真实的」）：ChatView 呈现改 .sheet 全量
/// 形态转正——七段全开＋模型常驻区，默认落活动段；
/// .activity 四段形态自此无入口（Mode 定义与段集留
/// 一版防回滚，下线归后续收口）。
/// §217（2026-11-13 枢纽收段＋呈现对齐，用户拍板）：
/// 分段七收四（活动/定时/浏览器/身份，任务/审核/
/// 监测并入活动，见 HubSegment 头注）；呈现由
/// fullScreenCover 改系统 sheet 大 detent 卡片式
/// （ChatView 侧 .sheet＋hubSheetPresentation()，
/// 对齐 Muse 枢纽的圆角卡浮起形态：初态留边圆
/// 角、后景压暗、落定近全屏；关闭反向回缩淡出走
/// 系统弹簧）。本视图的内容与导航栈不变，枢纽内
/// 自带 sheet（分享/模型/档案编辑）为嵌套呈现、
/// 与外层 sheet 互不相干。
/// §222（2026-11-14 枢纽页全页对 Muse 重建，用
/// 户总评「和人家的 UI 设计差远了」）：分段控件改自
/// 绘胶囊条对齐基准量测（系统 segmented 反相且尺寸
/// 钉死，见 segmentPicker 注）、撤条下 Divider、页
/// 头纵向节奏放开（头像→名字 16／名字→状态 8）；四
/// 段口径、模型常驻区、呈现形态（sheet 大 detent）
/// 一律不动，头像组件归头像呈现包、身份段正文提炼
/// 归专包。全档＝hub-page-muse-parity-report-
/// 20261114。
/// 结构归位包（2026-11-20，纲要 D4-1/D4-2，用户亲
/// 批「按纲要逐页归位」）：①页头状态行改「活动优
/// 先、状态兜底」——台账有进行中条目时显其人话标题
/// （多件显「正在进行 N 件 · 标题」，派生与进展胶
/// 囊同源 ProgressCapsule.derive、枢纽看全局不剔
/// 除任何会话），无进行中回落现行连接状态词；活动
/// 态图标换系统转圈、兜底保留圆点（落法＝hub-
/// muse-benchmark §3.2）。②段外「会话模型行」整
/// 区撤除：枢纽回归只读档案面，模型切换正主＝聊天
/// 页胶囊模型段 Menu 与模型设置页（本行自始即与
/// 胶囊同面同账的第二入口，撤之不丢功能）。
/// 台账 199（2026-11-21，全 App 收敛）：§155 留置
/// 的 Mode.activity 孤儿形态整段下线——Mode 枚举、
/// mode 属性与段集分支全删，本面只剩全量形态一种；
/// 上文 0.6.0/0.17.0/§155 各段关于 Mode 的记述自此
/// 均为历史。
struct AgentHubView: View {
    /// 审批终态回调（活动格据此刷新总览桥角标）
    var onApprovalChanged: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var store: AgentHubStore?
    @State private var segment: HubSegment = .activity
    /// 根页边缘拖退出已触发旗（0.36.27 §97 件五）：
    /// 整段拖动只许 dismiss 一次，松手复位防重入
    @State private var edgeDismissTriggered = false
    /// 头像/名称编辑面（0.36.22 档案菜单两项）
    @State private var showAvatarEditor = false
    @State private var showNameEditor = false
    /// 分享名片（0.36.22）：名片图离屏渲染产物，随档
    /// 案修订/页头名/域名变化重算；未就绪时分享钮回
    /// 落纯文本名片
    @State private var shareItem: AgentShareItem?

    /// 可见段：四段全量（§217 收段后口径）。旧
    /// .activity 单段形态（活动格）自 §155 起无入
    /// 口、「留一版防回滚」的 Mode 定义已随台账
    /// 199 整段删除——本面自此只有全量一种形态
    var availableSegments: [HubSegment] {
        HubSegment.allCases
    }

    /// 通知落点的段位改道（§217）：原指向任务/审核/
    /// 监测三撤段的落点全部改落活动段——三段内容已
    /// 并入活动（审批聚焦与监测深链字段仍由 AppState
    /// 携带、活动段内对号消费），落点语义一条不丢。
    /// 纯函数收口于此供单测钉死（HubSegmentsConsoli-
    /// dationTests）
    static func segment(
        for destination: NotificationDestination
    ) -> HubSegment {
        switch destination {
        case .approvalDecision, .approvalHome,
             .monitorChange, .monitorsHome:
            return .activity
        case .approvalAnchor, .approvalThread, .none:
            // §165：锚点落点不在枢纽、本函数不被这类
            // 落点调用；防御性回落活动段
            return .activity
        }
    }

    /// 分享名片重算键：档案修订（改名/换头像）＋页头
    /// 名＋域名任一变，名片图就重渲染
    private var shareRenderKey: String {
        "\(appState.agentProfileStore.revision)"
            + "|\(store?.displayName ?? "")"
            + "|\(appState.serverShareHost ?? "")"
    }

    /// 根页左缘右滑退出手势（0.36.27 §97 件五）：起
    /// 始点须落在左缘 28pt 内（.global 坐标判），只
    /// 消费横向分量、途中过 60 即 dismiss（整段只触
    /// 发一次、旗防重入，松手复位）；浏览器段排除
    /// （与退役探针的 segment 门一致，网页自有横移
    /// 手势优先）。纵向拖动横向分量≈0、永不过线，
    /// 枢纽内纵滚不受扰
    private var hubEdgeDismissGesture: some Gesture {
        DragGesture(
            minimumDistance: HubEdgeSwipe.minimumDistance,
            coordinateSpace: .global
        )
        .onChanged { value in
            guard segment != .browser, !edgeDismissTriggered
            else { return }
            if HubEdgeSwipe.shouldTrigger(
                startGlobalX: value.startLocation.x,
                translationX: value.translation.width
            ) {
                edgeDismissTriggered = true
                dismiss()
            }
        }
        .onEnded { _ in
            edgeDismissTriggered = false
        }
    }

    var body: some View {
        ZStack {
            // 整页底色先行：sheet 升起/退下与内容切换
            // 的空位是页底色而不是系统黑
            // （0.36.27 前此注的「边缘右滑跟手横移」已
            // 随整桥退役作废——新边缘拖不带页面跟手）
            Palette.pageBG.ignoresSafeArea()
            // 0.36.27（§97 件五）：栈绑回无参——0.36.26
            // 的 path 绑定深度门控已被真机证伪（path
            // 不追踪目标式推入、恒空），整桥退役后栈内
            // 页右滑返回全归系统 pop，不再需要栈深
            NavigationStack {
                Group {
                    if let store {
                        content(store)
                    } else {
                        ProgressView()
                    }
                }
                .background(Palette.pageBG)
                // 根页左缘右滑退出（0.36.27 §97 件五）：
                // 挂点＝栈根内容本体——推入页覆盖其上、
                // 触摸不达此处，「仅根页生效」由挂点天
                // 然成立；构造与聊天右滑引用同族（同宿
                // 主已真机证明），判读走 Core HubEdge-
                // Swipe 阈值小件
                .simultaneousGesture(hubEdgeDismissGesture)
            }
        }
        .sheet(isPresented: $showAvatarEditor) {
            AgentAvatarEditorView()
        }
        .sheet(isPresented: $showNameEditor) {
            AgentNameEditorView(
                initialName: appState.identityName ?? ""
            )
        }
        .task(id: shareRenderKey) {
            shareItem = AgentShareItem.make(
                name: store?.displayName ?? appState.agentDisplayName,
                host: appState.serverShareHost,
                avatarImage: appState.agentAvatarImage
            )
        }
        .task {
            // 身份呈现跟随（末写胜包）：枢纽是看身份的
            // 面——每次打开先重拉名字与头像，服务器刚
            // 被 AI 改过当场跟上（节流在 AppState 内）
            await appState.refreshIdentitySurfaces()
            if store == nil {
                // 0.36.21：store 改走 AppState 共享单例
                // （就地审批卡与枢纽共用同一份 /pending
                // 数据与裁决路径，规格 §6）；审批终态回
                // 调仍在此注入（本视图是全 App 唯一呈现
                // 枢纽的入口）
                let shared = appState.sharedHubStore()
                shared.onApprovalChanged = onApprovalChanged
                store = shared
            }
            await store?.loadInitial()
            // 页头状态行消费台账进行中集（结构归位
            // 包，§3.2）：开枢纽时先踢一脚共享台账店
            // 加载——与活动段 .task 的加载同店同守卫
            // （在飞即跳过），不新增轮询回路；后续新
            // 鲜度由活动段可见轮询同拍供给
            await appState.sharedLedgerStore()
                .load(appState: appState)
            // 共享 store 后 loadApproval 默认可复用缓存
            // （chat 刷新刚拉过会跳过），枢纽语义是「每
            // 次打开必刷新」——强制重拉保住（§155 起全
            // 量模式同口径，不再只限 .activity）
            await store?.loadApproval(force: true)
            // §123（H2）：通知落点消费——按落点切到对
            // 应段（聚焦字段由对应段自己消费），消费后
            // 清零，不许陈年请求在下次手动开枢纽时复
            // 活。§217 收段后落点改道走 segment(for:)
            // 单点映射：原任务/审核/监测落点全部落活
            // 动段，聚焦字段（hubApprovalFocusID/
            // monitorDeepLink）由活动段对号消费
            if let destination = appState.router.hubDestinationRequest {
                switch destination {
                case .approvalAnchor, .approvalThread:
                    // §165：锚点落点不在枢纽（在原对话
                    // 里），本请求恒不经枢纽分发——防御
                    // 性落空，不切段
                    break
                case .none:
                    break
                default:
                    segment = Self.segment(for: destination)
                }
                appState.router.hubDestinationRequest = nil
            }
        }
    }

    private func content(_ store: AgentHubStore) -> some View {
        VStack(spacing: 0) {
            header(store)
            segmentPicker
            segmentContent(store)
        }
        .onChange(of: segment) { _, newSegment in
            Task { await loadSegment(newSegment, store: store) }
        }
    }

    private func loadSegment(_ segment: HubSegment, store: AgentHubStore) async {
        switch segment {
        case .activity:
            break // 台账段自持 LedgerStore（段内 .task 驱动）；审批数据由开枢纽时的强制重拉保鲜（见 body .task），§217 后不再有独立审核段的切段加载
        case .cron:
            break // 定时段自持共享 CronStore（段内 .task 驱动，台账 198 收敛）
        case .browser:
            break // 0.9.0：浏览器面自带盒桥轮询（面内 .task 驱动）
        case .identity:
            await store.loadIdentityIfNeeded()
        }
    }

    // MARK: - 页头（规格 §2）

    /// 分享圆钮（0.36.22）：内容换代为智能体名片——
    /// 名称＋头像＋服务器域名（仅 host），红线不含任
    /// 何凭据（AgentShareCard）；名片图未渲染就绪时
    /// 回落纯文本名片，按钮永不假装。旧 shareText
    /// （含当前模型、无域名）自此退出分享面
    @ViewBuilder
    private func shareButton(_ store: AgentHubStore) -> some View {
        if let shareItem {
            ShareLink(item: shareItem.fileURL) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            // 第 83 条（命中域收口）：玻璃盘 36 不变（样
            // 式按标签帧成盘）、命中域在钮外层外扩 44；
            // 负内边距抵消外扩、页头行布局不动
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Rectangle())
            .padding(-(OneDayMetrics.minTapTarget - 36) / 2)
            .accessibilityLabel("分享智能体名片")
        } else {
            ShareLink(
                item: AgentShareCardText.make(
                    name: store.displayName,
                    host: appState.serverShareHost
                )
            ) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            // 第 83 条（命中域收口）：玻璃盘 36 不变（样
            // 式按标签帧成盘）、命中域在钮外层外扩 44；
            // 负内边距抵消外扩、页头行布局不动
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Rectangle())
            .padding(-(OneDayMetrics.minTapTarget - 36) / 2)
            .accessibilityLabel("分享智能体名片")
        }
    }

    private func header(_ store: AgentHubStore) -> some View {
        // §222（枢纽页对 Muse 重建）：纵向节奏对齐基准
        // 量测——头像→名字 ≈16、名字→状态 ≈8（旧版统一
        // spacingS 8 全程紧排，页头显挤）；名字字阶不动
        // （.title 28 bold 是 HIG Title1 用户定版口径，
        // 与基准量测同档，见 parity 报告 §1）
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                avatarBlock
                // 圆钮行（✕ 关闭＋分享名片）：0.36.22 起
                // 两模式统一常驻——整页呈现下活动模式同
                // 样需要显式关闭与分享落点（学 Muse 智
                // 能体页）；0.6.0 的「活动模式撤圆钮行」
                // 口径由整页化覆盖
                HStack {
                    // 页头圆钮（L1，用户定案③：照样板形态、
                    // 用系统玻璃原生件拼装）
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    // 第 83 条（命中域收口）：玻璃盘 36 不
                    // 变（样式按标签帧成盘）、命中域在钮外
                    // 层外扩 44；负内边距抵消外扩、页头行
                    // 布局不动
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
                    .padding(-(OneDayMetrics.minTapTarget - 36) / 2)
                    .accessibilityLabel("关闭")

                    Spacer()

                    shareButton(store)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
            }

            Text(store.displayName)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(1)
                .padding(.top, OneDayMetrics.spacingM)

            // 状态行（结构归位包，D4-1）：第一语义＝
            // 当前活动——台账有进行中条目时显活动行
            // （转圈＋人话标题），连接状态降为兜底
            // （无进行中时回落圆点＋现行状态词）
            HStack(spacing: OneDayMetrics.rowInnerGap) {
                if let activityLine = hubActivityLine {
                    ProgressView()
                        .controlSize(.mini)
                    Text(activityLine)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                } else {
                    Circle()
                        .fill(store.isOnline ? Palette.success : Palette.inkMuted)
                        .frame(width: 8, height: 8)
                    Text(store.statusText)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, OneDayMetrics.spacingS)
        }
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// 大头像＋编辑徽章（L2，用户定案④打包）：头像
    /// 0.6.0 换三狗搭档款定版图（蓝图 §3.10：吉祥物用
    /// 自有 IP，不借 OpenMuse 水豚；素材源
    /// ~/workspace/ip-design/STYLE-partner.webp 裁头入
    /// SangouPartner 资产）；服务端人设的编辑在身份段
    /// 内的人设编辑面（§155 前旧注「跳 ProfilesView」
    /// 是空跳、已销账）。
    /// 0.36.22（枢纽页对齐包，用户新定案覆盖上段徽章
    /// 口径）：头像改读本地档案（AppState 单一出口：
    /// 预置/符号盘/相册自定义图）；徽章两模式统一改
    /// 档案菜单——「更换虚拟形象」「编辑名称」改的是
    /// 本机档案（AgentProfileStore），不是服务器身份；
    /// 身份段仍在段列里、服务端身份编辑口径不变。
    private var avatarBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            appState.agentAvatarImage
                .resizable()
                .scaledToFill()
                .frame(
                    width: OneDayMetrics.avatarPageHead,
                    height: OneDayMetrics.avatarPageHead
                )
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Palette.hairline, lineWidth: 0.5)
                }

            Menu {
                Button {
                    showAvatarEditor = true
                } label: {
                    Label("更换虚拟形象", systemImage: "person.crop.circle")
                }
                Button {
                    showNameEditor = true
                } label: {
                    Label("编辑名称", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: FrameworkIcon.composerGlyphSize, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(Palette.surface, in: Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }
                    // §247.3 档 F 浮件档（阴影两档之一）
                    .shadow(
                        color: Palette.shadowBase.opacity(
                            ElevationTokens.floatingOpacity
                        ),
                        radius: ElevationTokens.floatingRadius,
                        y: ElevationTokens.floatingY
                    )
                    // 0.23.0（命中域审计）：视觉盘 36 不变、
                    // 命中域外扩 44（盘居中）
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("编辑头像与名称")
        }
    }

    /// 页头状态行第一语义＝当前活动（结构归位包，
    /// benchmark §3.2）：台账进行中集派生与进展胶囊
    /// 同源（ProgressCapsule.derive，单件显标题、多
    /// 件显「正在进行 N 件 · 标题」）；枢纽是看全局
    /// 的面，不剔除任何会话（currentSessionID 传
    /// nil）。无进行中条目返回 nil，页头回落连接
    /// 状态词（兜底）
    private var hubActivityLine: String? {
        ProgressCapsule.derive(
            items: appState.sharedLedgerStore().items,
            currentSessionID: nil
        )?.headlineText
    }

    // MARK: - 四段分段控件（§222 胶囊条形态对齐）

    /// 分段条形态（§222，用户 2026-11-14 总评「枢纽页
    /// 和人家的 UI 设计差远了」后的全页对齐）：对 Muse
    /// 智能体页量测——整条胶囊高 ≈48、白面＋发丝描边，
    /// 选中段是浅灰填充胶囊（高 ≈36），图标 ≈22。系统
    /// segmented 与基准恰好反相（灰轨 32 高＋白选胶囊）
    /// 且高度/图标钉死不可调，形态对齐只能自绘；旧
    /// 「原生 segmented 先行」定案（0.36.22）由本节覆
    /// 盖。选中填充取 selectionFill——与 OpenMuse 底栏
    /// 激活项同一填充角色（Palette 本源）。段集/顺序/
    /// 图标仍走 HubSegment 单源（§217 四段口径不动）；
    /// 无障碍与旧 Picker 等价：按钮＋段名标签＋选中
    /// trait（UI 布局探针按标签回落查按钮、兼容）。
    /// 条下 Divider 撤除——基准是留白节奏不是线（宪
    /// 法③的分隔几何收口不在此面回潮）
    private var segmentPicker: some View {
        HStack(spacing: OneDayMetrics.spacingXS) {
            ForEach(availableSegments) { item in
                Button {
                    segment = item
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(
                            size: OneDayMetrics.hubSegGlyphSize,
                            weight: .regular
                        ))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: OneDayMetrics.hubSegCapsuleHeight)
                        .background(
                            segment == item
                                ? Palette.selectionFill : Color.clear,
                            in: Capsule()
                        )
                        // 第 83 条（命中域收口）：选中胶囊视
                        // 觉高 36 不变、段钮命中高外扩 44
                        // （条高 48 内居中、上下各剩 2pt）；
                        // 负内边距抵消外扩、条布局不动。命
                        // 中形由旧 36 胶囊改外层矩形（与全
                        // 仓外扩口径同款）
                        .frame(height: OneDayMetrics.minTapTarget)
                        .contentShape(Rectangle())
                        .padding(
                            .vertical,
                            -(OneDayMetrics.minTapTarget
                                - OneDayMetrics.hubSegCapsuleHeight) / 2
                        )
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(
                    segment == item ? .isSelected : []
                )
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingXS)
        .frame(height: OneDayMetrics.hubSegBarHeight)
        .background(Palette.surface, in: Capsule())
        .overlay {
            Capsule().stroke(Palette.hairline, lineWidth: 0.5)
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingSM)
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: segment
        )
    }

    // MARK: - 段内容

    @ViewBuilder
    private func segmentContent(_ store: AgentHubStore) -> some View {
        switch segment {
        case .activity:
            // 工作台账（§95）：段自持 LedgerStore，行
            // 下钻打开会话走既有 pendingChatSessionID
            // 通道，与旧活动行同路（下钻即关页）。
            // §217：三段并入后本段
            // 兼收任务/审批下钻补齐与监测合成条目——
            // 共享 hubStore 一并注入（锚点数据在 store
            // 里，与聊天就地卡同源；审批规则本体已按
            // §244 归设置页权限区，本段只留审批记录）
            HubLedgerSection(hubStore: store, onOpenSession: { sessionID in
                appState.router.pendingChatSessionID = sessionID
                dismiss()
            })
        case .cron:
            // 定时段数据自台账 198 收敛起走共享
            // CronStore，不再经枢纽 store 私拉一份
            HubCronSection(appState: appState)
        case .browser:
            HubBrowserSection()
        case .identity:
            HubIdentitySection(store: store)
        }
    }
}


/// 枢纽卡片式呈现口径（§217，用户 2026-11-13 拍板
/// 对齐 Muse 枢纽录屏形态）：系统 sheet 的大
/// detent——iOS 26 的卡片呈现语言（圆角卡浮起、后
/// 景缩退压暗、落定近全屏、关闭反向回缩淡出，全
/// 走系统弹簧），不自绘转场。呈现方（ChatView 的
/// .sheet 与测试装配台）共用本修饰符一处收口，防
/// 两处口径漂移；真机与录屏的帧级比对归真机验收
/// （HubSegmentsConsolidationTests 只钉系统行为的
/// 可测面：detent 在位、落定留边、圆角容器在场、
/// 呈现/关闭全程有帧位移非硬切）。
extension View {
    func hubSheetPresentation() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}
