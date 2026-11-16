import Foundation
import OneDayCore
import SwiftUI

/// 跨页深链路由（IA v3）：总览的指标行/最近会话/快捷动作要把
/// 用户直接送进智能体格或设置格的某个二级页，路由经 AppRouter
/// 的 pending 字段传递，目标页消费后清空。
/// （§301 前本文件名为 AppRoutes.swift、只有两个枚举——信箱
/// 本体从未并入；A-03 收口后枚举与信箱同归 AppRouter 一处。）
enum AgentRoute: Hashable {
    case memory
    case skills
    case cron
    case serverSessions
    case serverSessionDetail(String)
    case mcp
    /// 设备与权限总览（0.34.0，本机连接器批一）：五件
    /// 数据源的授权状态＋调用开关汇总（设计档 §6.3）
    case devicePermissions
    /// 审批规则（§244 归位）：设置页权限区内的规则面
    case approvalRules
}

/// （应用格内页面枚举 AppsPage 已于 0.20.0 随应用格
/// 一并退役：总览/电脑/服务器文件迁设置「管理」组
/// sheet 呈现、设置改根级 sheet、文件升底栏第四格，
/// 「格内页面切换」的状态机不再存在。）

enum SettingsRoute: Hashable {
    case serverDetail
    case profiles
    case models
    case envVars
    case usage
    case gateway
    case logs
    /// （0.33.1 退役：原 .writeGateKey 桥钥匙粘贴页路由随
    /// 设置页「桥钥匙」整节删除，用户只持 Hermes 登录密钥）
    /// 0.2.1：运维四模块并入设置「智能体」组，路由复用 AgentRoute
    case agent(AgentRoute)
    /// 0.2.1：外观（主题）
    case appearance
    /// 侧边栏分区管理面（§198，抽屉包题二）：抽屉四
    /// 区显隐账的唯一治理面（设置→偏好与权限→侧边栏）
    case sidebar
    /// 设置页重塑（DESIGN §164）：身份卡详情页与支持
    /// 组三页（帮助/关于/协议草稿）——目的地与 Core
    /// SettingsCatalog 一一对应
    case identity
    case help
    case about
    case privacy
    case terms
    /// prototype-2（DESIGN §164 升级）：四个二级枢纽页
    case agentConfig        // 智能体配置枢纽页
    case serverManagement   // 服务器管理枢纽页
    case sessionManagement  // 会话管理枢纽页
    case workspaceHub       // 工作区枢纽页
    case mainSession        // 主线会话详情页
    case restartGateway     // 重启网关页
}

/// 「工作区」组三页的 sheet 呈现槽枚举（原定义在
/// SettingsView 内部、WorkspaceHubView 反向借用——
/// §301 横扫 A-28 随 A-03 上移：呈现槽枚举归呈现
/// 协调方，本枚举自此与 AppRouter 同文件公共层）
enum ManageSheet: String, Identifiable {
    case overview, computer, serverFiles
    var id: String { rawValue }
}

/// 全 App 唯一导航真值（§301，横扫 A-03 router-unify）：
/// 0.4.0–§219 六代「置位—消费—清零」信箱原散在 AppState
/// （约 20 个字段各自为政、消费方各写 onChange 猜时序），
/// 本类整组收口为唯一持有者——跨页路由意图、底栏格、
/// sheet 呈现槽、抽屉呈现与当前对象、频道观看出处全
/// 在此一处；视图只经本类读写导航状态，不再有第二
/// 个导航状态源。字段名与置位—消费—清零协议逐项沿
/// 旧制（行为不变是本包硬口径），变的只是持有者。
/// 面内导航栈仍归各面自有（设置页 NavigationStack
/// path 即官方形态），本类只管跨面一层。
@MainActor
@Observable
final class AppRouter {
    /// 跨页深链（总览 → 智能体格/设置格二级页）：目标页消费后置 nil
    var pendingAgentRoute: AgentRoute?
    var pendingSettingsRoute: SettingsRoute?
    /// 设置 sheet 打开请求（0.20.0）：抽屉齿轮置位，
    /// ContentView 消费呈现根级设置 sheet 后置 false。
    /// 0.6.0 的 pendingAppsPage 通道随应用格退役一并
    /// 删除——应用格页面已各有新家（总览/电脑/服务器
    /// 文件进设置「管理」组、文件格升底栏），不再有
    /// 「切格落位」这回事
    var settingsSheetRequested = false
    /// 底栏切格请求（0.29.0）：设置内页面（如连接器目
    /// 录的本机服务详情）要把用户送到目标/点子底栏格
    /// 时置位，ContentView 消费后关设置 sheet 并切格
    /// 并清零——置位—消费—清零与 settingsSheet-
    /// Requested 同式；目标格枚举与底栏本体同源
    /// （ContentView.MainTab），不另立第二套格名
    var mainTabSwitchRequest: ContentView.MainTab?
    /// 文件页定位请求（§131，D8「在文件页中打开」）：
    /// 打开页动作置位目标路径并同行置 mainTabSwitch-
    /// Request=.files 切格，DeliverablesView 消费后
    /// 滚动定位＋高亮该行并清零——置位—消费—清零与
    /// pendingChatSessionID 同式
    var fileRevealPath: String?
    /// 待续聊的服务端会话 id（0.4.0，审计 §3.4）：四处
    /// 入口（抽屉／服务端会话页／状态页／定时运行记录）
    /// 置位，ContentView 据此切聊天格、ChatView 消费后
    /// 导入历史并置 nil。不再走设置格的只读详情页
    var pendingChatSessionID: String?
    /// 待续聊会话的频道来源标记（0.36.29，频道规格
    /// §10.3）：频道页点行时与 pendingChatSessionID
    /// 同行置位（先标记、后置 id），ChatView 消费时
    /// 据此把抽屉当前对象置为 .channel 并落频道观
    /// 看出处；其他入口打开会话不置此标记，消费口
    /// 径据「无标记」清旧出处。消费后清零
    var pendingChatChannelID: String?
    /// 频道观看出处（0.36.29，§10.2）：当前线程是
    /// 从哪个频道的哪条会话打开的——ChatView 当前
    /// 线程同步据此维持 .channel 对象引用（导入线
    /// 程渲染期间不派生成 .side）；线程切离该会话
    /// 或从旁聊区/主线行重进同一条时由各置位点清
    /// 除。只存呈现出处、不参与分类（分类归属与选
    /// 择归属是两件事）
    var channelViewingOrigin: ChannelViewingOrigin?
    /// 总览快捷动作「新建定时任务」：定时页消费后自动拉起新建表单
    var cronCreateRequested = false

    /// 通知落点请求（§123 H2）：通知中心点条目时置位
    /// （落点解析在 Core NotificationDestination），
    /// AgentHubView 开枢纽时消费段位、对应段消费各自
    /// 的聚焦字段，消费后清零——置位—消费—清零与
    /// hubOpenRequested 同式
    var hubDestinationRequest: NotificationDestination?
    /// 审批段聚焦的已决记录 id（approvalDecision 携带来）
    var hubApprovalFocusID: String?
    /// 监测段深链：直达的监测 id 与变化 id（变化 id 为
    /// nil 时只达监测详情）
    var monitorDeepLink: (monitorID: String, changeID: String?)?
    /// 锚点点达请求（§165）：枢纽记录行/通知回执命中本
    /// 机锚时置位——目标线程＋锚定键（键为 nil＝只切线
    /// 程不定位）；ChatView 消费（切线程→滚动定位→点
    /// 亮→清零），与 hubDestinationRequest 分家：锚点
    /// 落点不在枢纽里、不经枢纽开启接力
    var approvalAnchorRequest: (
        threadID: UUID, approvalKey: String?
    )?

    /// 通知条目落点分发：把落点拆成各消费方能消费的
    /// 字段；返回 false 表示无落点（调用方不导航）。
    /// §165：锚点落点（approvalAnchor/approvalThread）
    /// 不进 hubDestinationRequest——它由通知页直接切聊
    /// 天格＋置 approvalAnchorRequest，ChatView 消费；
    /// 返回 true 表示落点成立（调用方关通知页即可，不
    /// 走枢纽接力）
    @discardableResult
    func requestHubDestination(
        _ destination: NotificationDestination
    ) -> Bool {
        switch destination {
        case .approvalDecision(let id):
            hubApprovalFocusID = id
        case .monitorChange(let monitorID, let changeID):
            monitorDeepLink = (monitorID, changeID)
        case .approvalAnchor(let threadID, let key):
            approvalAnchorRequest = (threadID, key)
            return destination.hasDestination
        case .approvalThread(let threadID):
            approvalAnchorRequest = (threadID, nil)
            return destination.hasDestination
        case .approvalHome, .monitorsHome, .none:
            break
        }
        guard destination.hasDestination else { return false }
        hubDestinationRequest = destination
        return true
    }
    /// 抽屉「枢纽」导航行的开枢纽请求（0.19.0）：抽屉置
    /// 位（先切聊天格再置位），ChatView 消费后开枢纽
    /// sheet 并清零——置位—消费—清零与 cronCreate-
    /// Requested 同式。枢纽 sheet 本体长在聊天页（胶囊
    /// 入口同处），不在抽屉另立第二份承载
    var hubOpenRequested = false
    /// 聊天抽屉开合的语义状态（0.2.2 立；0.4.5 改口径，
    /// §30）：壳层 ContentView 是执行者（覆盖式动画与跟手
    /// 状态在壳层），任何视图想开/关抽屉只写这里、壳层
    /// onChange 执行；DrawerView 据此在打开时补拉服
    /// 务端会话 source 映射（0.19.0 返工瘦身：只喂旁
    /// 聊行显的来源过滤判定，不再拉名单成行——名单
    /// 本体是本地线程）。（0.2.2–0.4.4 的旧注「Con-
    /// tentView 据此隐藏自绘底栏」随自绘底栏与覆盖式
    /// 抽屉一并作废）
    var drawerPresented = false
    /// 抽屉与 ChatView 之间的通道（0.4.5，抽屉提到
    /// 壳层后立；模式与 pendingChatSessionID 一致：置位
    /// 方写、消费方读后清零）
    /// 抽屉当前对象引用（0.36.7，频道规格 §10.2/§10.3）：
    /// 全抽屉唯一选择源——写入点只有导航动作（抽屉主
    /// 线行→.main、旁聊行→.side）与 ChatView 的当前线
    /// 程同步（落点/切换/新建/导入都经它派生）；抽屉
    /// 胶囊只许问 Core DrawerSelectionPolicy，不许再
    /// 私读页签或线程 id 自画。页签切走不清、回切恢
    /// 复。0.4.5 的 activeThreadID 随本引用落地退役
    /// （其消费面——胶囊判定与删当前线程判定——已全
    /// 部改读本引用经政策解析）
    var currentDrawerObject: DrawerCurrentObject?
    /// 动态原帖回跳请求（§208）：聊天里点消息的动态
    /// 引用块时置位帖 id 并同行置 mainTabSwitch-
    /// Request=.feed 切格，FeedView 消费后定位原帖
    /// （查无此帖给诚实提示）并清零——置位—消费—
    /// 清零与 fileRevealPath 同式
    var feedOpenPostRequest: String?
    /// 点子回跳请求（§219）：聊天里点消息的点子引
    /// 用块时置位点子 id 并同行置 mainTabSwitch-
    /// Request=.ideas 切格，IdeasView 消费后开该点
    /// 子详情（查无此点子给诚实提示）并清零——与
    /// feedOpenPostRequest 同式
    var ideaOpenRequest: String?
    /// 抽屉点选/新建的线程 id（DrawerView 写，ChatView
    /// 消费后切 currentThreadID 并清零）
    var drawerThreadSelection: UUID?
    /// 抽屉刚删掉的线程 id（DrawerView 写，ChatView 若
    /// 正显示该线程则置空 currentThreadID 并清零）
    var drawerDeletedThreadID: UUID?
}
