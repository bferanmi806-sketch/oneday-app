import Foundation

/// 设置目录（设置页重塑，DESIGN §164）：设置首页分组
/// 与顶部搜索共用同一份条目清单——浏览态按组排、搜
/// 索态按本清单过滤，「搜得到的＝平时点得到的」只有
/// 一份真源，对账表（§164.2）逐项以本清单 id 为锚。
/// 条目只记标题／搜索副行／关键词／目的地；图标与呈
/// 现留 App 层。标题与副行是中文源串（App 侧经
/// SwiftUI 本地化键取词，三语词条与源串同字面）。

/// 设置分组（IA 顺序即声明序）：身份卡不在任何组内
/// （.top，浏览态以卡片形态居首、搜索态可命中）
/// prototype-2（DESIGN §164 升级）：连接组改服务与工作区
/// serverAndWorkspace、app 组改偏好与权限 preferences、
/// workspace 旧组退役（改为二级枢纽页）；结构归位
/// （2026-11-20）后枢纽页撤销、工作区子项并回本组尾段，
/// 组名与组集不变
public enum SettingsGroupID: String, CaseIterable, Sendable {
    case top
    case agent
    case serverAndWorkspace  // 原 connection 改组（服务与工作区）
    case preferences         // 原 app 改组（偏好与权限）
    case support
}

/// 条目目的地：与 App 层 SettingsRoute／管理 sheet
/// 一一对应（映射在 SettingsView.activate），Core 只
/// 记语义、不依赖 App 层类型
/// prototype-2（DESIGN §164 升级）：曾新增四个二级枢纽页
/// （agentConfig/serverManagement/sessionManagement/
/// workspaceHub）、主线会话（mainSession）、重启网关页
/// （restartGateway）
/// 结构归位（2026-11-20，结构纲要 D7-1／原则 8）：四个
/// 转接枢纽页撤销——叶子条目全部提回根组直达（层位降
/// 级、入口零丢失），枢纽目的地随之退役；断开连接是
/// 动作非页面，设专目的地（.disconnect，搜索可达、
/// 浏览态由根页服务器组末行手写呈现）
public enum SettingsDestination: Equatable, Sendable {
    case identity
    case profiles
    case memory
    case skills
    case cron
    case serverSessions
    case models
    case envVars
    case usage
    case serverDetail
    case connectors
    case devicePermissions
    /// 审批规则（§244 归位，大厂九项⑦）：规则是长期
    /// 设置、归设置页权限区；台账只留审批记录
    case approvalRules
    case gateway
    case logs
    // 总览目的地已撤（结构归位包，纲要 D5-1：总览撤
    // 独立页、入口摘除，待处理归聊天/枢纽记录、最近
    // 会话归抽屉）；状态详情页（StatusView）的家经
    // 合流对接点落位：原拟归服务器管理页、该页已随
    // 设置根归位撤销，改由本目录 status 条目在服务
    // 与工作区组直达
    case status
    case computer
    case serverFiles
    case appearance
    // 侧边栏目的地已撤（归位合流 2026-11-20 对接
    // 点）：分区管理面整套退役——抽屉已断显隐账消
    // 费，管理面留着只是 phantom 开关（纲要原则 8）
    // 全部对话目的地已撤（同上）：入口升一级归抽屉
    // 名单收尾行独占（纲要 D2-1、原则 6 列表只住一
    // 级面），设置页不再设第二扇门、搜索亦不点达
    case help
    case about
    case privacy
    case terms
    // prototype-2 新增（结构归位后仅存叶子与动作）
    case mainSession        // 主线会话详情页
    case restartGateway     // 重启网关页
    /// 体检面（H1-a，台账 158）：原服务器管理枢纽页
    /// 「维护」段子项，结构归位后提回根页服务器组——
    /// 自检＋安全审计＋结论留痕
    case healthCheck
    /// 断开连接（动作目的地）：原服务器管理页页底动
    /// 作，归位后落根页服务器组末行＋搜索点达，两路
    /// 都经 SettingsView 的确认框执行（口径不变）
    case disconnect
    /// 语音面（H2-a，台账 159）：原服务器管理枢纽页
    /// 「维护」段内子项——回复朗读可用性/自动朗读/
    /// 音色展示（服务端语音能力）；合流对接点随页
    /// 归位：与体检面同落根页服务器组维护尾段直达
    case voice
    /// 添加设备（配对一期，台账 153/160）：已登录侧
    /// 出码面——向网关领一次性认领码、组二维码给新
    /// 设备扫码入驻；与体检/语音同落根页服务器组维
    /// 护尾段直达
    case addDevice
    /// 聊天诊断（台账 189/190）：本机聊天面探针的
    /// 可读面——卡顿探针汇总／量测台积压／诊断留
    /// 痕（ChatDiagTrace）／气泡浓淡键值原文与解
    /// 析值（台账 188 证据出口）。探针此前只写不
    /// 读、真机回读无门，本面是其唯一消费方；落
    /// 支持组（与帮助/关于同组，内部取证性质）
    case chatDiagnostics
}

public struct SettingsCatalogEntry: Equatable, Sendable, Identifiable {
    /// 稳定 id（对账表与测试锚点，改名不改 id）
    public let id: String
    public let group: SettingsGroupID
    /// 行题（中文源串）
    public let title: String
    /// 搜索副行兼关键词主串（中文源串）
    public let summary: String
    /// 补充关键词（中英混排，搜索命中面）
    public let keywords: [String]
    public let destination: SettingsDestination
    /// 浏览态是否以行形态出现在所属组内：身份（卡片
    /// 形态单列）与隐私/协议（关于页内二级）为 false，
    /// 只进搜索索引
    public let showsInBrowse: Bool

    public init(
        id: String,
        group: SettingsGroupID,
        title: String,
        summary: String,
        keywords: [String],
        destination: SettingsDestination,
        showsInBrowse: Bool = true
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.summary = summary
        self.keywords = keywords
        self.destination = destination
        self.showsInBrowse = showsInBrowse
    }
}

public enum SettingsCatalog {
    public static let entries: [SettingsCatalogEntry] = [
        // 身份（卡片单列，只进搜索）
        SettingsCatalogEntry(
            id: "identity", group: .top,
            title: "形象与名称",
            summary: "头像、显示名",
            keywords: ["头像", "名称", "显示名", "avatar", "name"],
            destination: .identity, showsInBrowse: false
        ),
        // 智能体（结构归位：智能体配置枢纽页撤销，原
        // 页内三项 profiles/memory/skills 提回根组直达，
        // 与 models/cron 同组并列——上下文同属智能体）
        SettingsCatalogEntry(
            id: "models", group: .agent,
            title: "模型与服务商",
            summary: "默认模型、服务商与辅助模型",
            keywords: ["默认模型", "服务商", "辅助模型", "model", "models"],
            destination: .models
        ),
        SettingsCatalogEntry(
            id: "profiles", group: .agent,
            title: "配置档案",
            summary: "决定人设与系统提示，保存在服务器",
            keywords: ["配置", "档案", "人设", "系统提示", "profile", "soul"],
            destination: .profiles
        ),
        SettingsCatalogEntry(
            id: "memory", group: .agent,
            title: "记忆",
            summary: "长期偏好与记忆条目",
            keywords: ["长期记忆", "用户档案", "偏好", "memory"],
            destination: .memory
        ),
        SettingsCatalogEntry(
            id: "skills", group: .agent,
            title: "技能",
            summary: "智能体可用的能力，可启停",
            keywords: ["技能商店", "能力", "skill", "skills"],
            destination: .skills
        ),
        SettingsCatalogEntry(
            id: "cron", group: .agent,
            title: "定时任务",
            summary: "按计划自动执行的任务",
            keywords: ["计划", "定时", "自动", "cron"],
            destination: .cron
        ),
        // 服务与工作区（结构归位：服务器管理／会话管
        // 理／工作区三张枢纽页撤销，全部子项提回根组
        // 直达。组内序＝服务器本体（地址/网关/日志/用
        // 量）→会话（主线/服务端）→工作区资源（状态/
        // 电脑/文件）→维护尾段（密钥/重启/体检/语音/
        // 添加设备））
        SettingsCatalogEntry(
            id: "server", group: .serverAndWorkspace,
            title: "当前服务器",
            summary: "地址、密钥与连接状态",
            keywords: ["服务器地址", "密钥", "连接", "server"],
            destination: .serverDetail
        ),
        SettingsCatalogEntry(
            id: "gateway", group: .serverAndWorkspace,
            title: "网关状态",
            summary: "网关运行状态与重启",
            keywords: ["网关", "重启", "gateway"],
            destination: .gateway
        ),
        SettingsCatalogEntry(
            id: "logs", group: .serverAndWorkspace,
            title: "日志",
            summary: "服务端运行日志",
            keywords: ["运行日志", "log", "logs"],
            destination: .logs
        ),
        SettingsCatalogEntry(
            id: "usage", group: .serverAndWorkspace,
            title: "用量",
            summary: "模型用量统计",
            keywords: ["统计", "消耗", "token", "usage"],
            destination: .usage
        ),
        SettingsCatalogEntry(
            id: "mainSession", group: .serverAndWorkspace,
            title: "主线会话",
            summary: "主要对话、会话 ID",
            keywords: ["主线", "当前会话", "main session"],
            destination: .mainSession
        ),
        SettingsCatalogEntry(
            id: "serverSessions", group: .serverAndWorkspace,
            title: "服务端会话",
            summary: "在网页端等其他入口产生的会话",
            keywords: ["会话", "网页端", "session", "sessions"],
            destination: .serverSessions
        ),
        // 状态详情（StatusView）：原「总览」条目已随
        // 枢纽/总览归位摘除（纲要 D5-1 总览撤页、D5-2
        // 入口提浅归正主）；总览的状态下钻页不随页丢
        // ——合流对接点落位为本条目，接替总览原位在工
        // 作区资源段首位直达（活动/定时/系统三段）
        SettingsCatalogEntry(
            id: "status", group: .serverAndWorkspace,
            title: "状态",
            summary: "活动、定时与系统状态",
            keywords: ["状态", "活动", "定时", "系统", "status", "overview", "工作区"],
            destination: .status
        ),
        SettingsCatalogEntry(
            id: "computer", group: .serverAndWorkspace,
            title: "电脑",
            summary: "智能体使用的电脑",
            keywords: ["云电脑", "桌面", "computer", "工作区"],
            destination: .computer
        ),
        SettingsCatalogEntry(
            id: "serverFiles", group: .serverAndWorkspace,
            title: "服务器文件",
            summary: "服务器上的文件",
            keywords: ["文件", "files", "工作区", "资源库"],
            destination: .serverFiles
        ),
        SettingsCatalogEntry(
            id: "envVars", group: .serverAndWorkspace,
            title: "密钥",
            summary: "保存在服务器上的密钥",
            keywords: ["环境变量", "key", "env", "维护"],
            destination: .envVars
        ),
        SettingsCatalogEntry(
            id: "restartGateway", group: .serverAndWorkspace,
            title: "重启网关",
            summary: "重启服务端网关",
            keywords: ["重启", "维护", "restart gateway"],
            destination: .restartGateway
        ),
        SettingsCatalogEntry(
            id: "healthCheck", group: .serverAndWorkspace,
            title: "体检与存档",
            summary: "自检、安全审计与备份存档",
            keywords: ["体检", "自检", "安全审计", "健康", "维护", "health", "doctor", "audit"],
            destination: .healthCheck
        ),
        // 语音（H2-a，台账 159）：原服务器管理枢纽页
        // 「维护」段内子项，合流对接点随页归位——维护
        // 尾段末位、浏览直达（与体检面同组同例）
        SettingsCatalogEntry(
            id: "voice", group: .serverAndWorkspace,
            title: "语音",
            summary: "回复朗读、自动朗读与音色",
            keywords: ["语音", "朗读", "音色", "回复朗读", "voice", "speak", "tts"],
            destination: .voice
        ),
        // 添加设备（配对一期，台账 153/160）：已登录
        // 侧出码面，维护尾段末位、浏览直达（与体检/
        // 语音同组同例）
        SettingsCatalogEntry(
            id: "addDevice", group: .serverAndWorkspace,
            title: "添加设备",
            summary: "生成认领二维码，让新设备扫码连上这台服务器",
            keywords: ["添加设备", "扫码", "二维码", "配对", "新设备", "enroll", "pairing", "qr"],
            destination: .addDevice
        ),
        // 断开连接（动作条目，只进搜索：浏览态由根页
        // 服务器组末行手写呈现，点达经 activate 起确认框）
        SettingsCatalogEntry(
            id: "disconnect", group: .serverAndWorkspace,
            title: "断开连接",
            summary: "清除本机保存的服务器凭据与登录会话",
            keywords: ["断开", "退出登录", "disconnect"],
            destination: .disconnect, showsInBrowse: false
        ),
        // 偏好与权限（prototype-2 新组）
        SettingsCatalogEntry(
            id: "appearance", group: .preferences,
            title: "外观",
            summary: "聊天配色、形象大小、模式与语言",
            keywords: ["主题", "配色", "形象大小", "语言", "深色", "浅色", "theme", "language"],
            destination: .appearance
        ),
        SettingsCatalogEntry(
            id: "connectors", group: .preferences,
            title: "连接器",
            summary: "外部服务与设备能力",
            keywords: ["外部服务", "设备", "mcp", "connector"],
            destination: .connectors
        ),
        SettingsCatalogEntry(
            id: "devicePermissions", group: .preferences,
            title: "设备与权限",
            summary: "本机数据授权与同步",
            keywords: ["权限", "授权", "同步", "设备", "隐私"],
            destination: .devicePermissions
        ),
        SettingsCatalogEntry(
            id: "approvalRules", group: .preferences,
            title: "审批规则",
            summary: "「总是允许」的规则与撤销",
            keywords: ["审批", "规则", "总是允许", "撤销", "approval", "rules"],
            destination: .approvalRules
        ),
        // 支持
        SettingsCatalogEntry(
            id: "help", group: .support,
            title: "帮助与反馈",
            summary: "连接帮助与问题反馈",
            keywords: ["反馈", "问题", "帮助", "help"],
            destination: .help
        ),
        SettingsCatalogEntry(
            id: "about", group: .support,
            title: "关于 OneDay",
            summary: "版本、隐私与开源",
            keywords: ["版本", "隐私", "协议", "开源", "about"],
            destination: .about
        ),
        SettingsCatalogEntry(
            id: "privacy", group: .support,
            title: "隐私政策",
            summary: "我们如何处理你的数据",
            keywords: ["隐私", "政策", "privacy"],
            destination: .privacy, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "terms", group: .support,
            title: "用户协议",
            summary: "使用 OneDay 的条款",
            keywords: ["协议", "条款", "terms"],
            destination: .terms, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "chatDiagnostics", group: .support,
            title: "聊天诊断",
            summary: "卡顿探针、量测积压与诊断留痕",
            keywords: ["诊断", "卡顿", "探针", "量测", "diagnostics", "lag"],
            destination: .chatDiagnostics
        ),
    ]

    /// 某组在浏览态出现的行（清单序）
    public static func browseEntries(
        in group: SettingsGroupID
    ) -> [SettingsCatalogEntry] {
        entries.filter { $0.group == group && $0.showsInBrowse }
    }

    /// 搜索：查询去空白并折叠大小写后，对标题／副行／
    /// 关键词做包含匹配；标题命中排在副行／关键词命中
    /// 之前（按标题搜先达标题页，如搜「记忆」先达记忆
    /// 页、枢纽页「智能体配置」以副行含「记忆」随后），
    /// 同层内按清单序（清单序即 IA 序）；空查询返回
    /// 全部条目
    public static func search(_ query: String) -> [SettingsCatalogEntry] {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return entries }
        let titleHits = entries.filter {
            $0.title.lowercased().contains(needle)
        }
        let otherHits = entries.filter { entry in
            !entry.title.lowercased().contains(needle)
                && (entry.summary.lowercased().contains(needle)
                    || entry.keywords.contains {
                        $0.lowercased().contains(needle)
                    })
        }
        return titleHits + otherHits
    }
}
