import XCTest
@testable import OneDayCore

/// 设置目录钉测（DESIGN §164）：清单完整性（id/目的
/// 地唯一、对账锚点齐全）与搜索口径（清单序、空查询
/// 全量、中英关键词命中、无命中为空）
final class SettingsCatalogTests: XCTestCase {

    func testIDsAndDestinationsAreUnique() {
        let ids = SettingsCatalog.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "条目 id 必须唯一")
        let destinations = SettingsCatalog.entries.map(\.destination)
        XCTAssertEqual(
            Set(destinations).count, destinations.count,
            "每个目的地只许一个条目（点达不许双门）"
        )
    }

    func testEntriesCarrySearchMaterial() {
        for entry in SettingsCatalog.entries {
            XCTAssertFalse(entry.title.isEmpty, "\(entry.id) 缺标题")
            XCTAssertFalse(entry.summary.isEmpty, "\(entry.id) 缺副行")
            XCTAssertFalse(entry.keywords.isEmpty, "\(entry.id) 缺关键词")
        }
    }

    /// 搜索索引在清单里逐项有锚（prototype-2 索引经
    /// 结构归位 2026-11-20 修订：四个枢纽页条目退役、
    /// 子项与断开连接动作条目续存）
    func testPrototypeIndexIsCovered() {
        let ids = Set(SettingsCatalog.entries.map(\.id))
        for id in [
            "privacy", "terms",
            "identity", "profiles", "memory", "skills", "models", "cron",
            "mainSession", "serverSessions",
            "server", "gateway", "logs", "envVars", "usage",
            "connectors", "devicePermissions",
            "status", "computer", "serverFiles", "voice",
            "appearance", "help", "about",
            "disconnect",
        ] {
            XCTAssertTrue(ids.contains(id), "索引缺条目 \(id)")
        }
        // 枢纽页条目已退役、不许残留（点达不许有第二扇门）
        for id in ["agentConfig", "serverManagement", "sessionManagement", "workspace"] {
            XCTAssertFalse(ids.contains(id), "枢纽页条目 \(id) 应已退役")
        }
        // 重启网关独立页条目已退役（台账 198 收敛
        // S4：重启只走网关状态页控制组，根行不许再
        // 长第二扇门）
        XCTAssertFalse(ids.contains("restartGateway"), "重启网关条目应已退役")
    }

    /// 现行主页全部目的地在清单里有锚（零丢失对账的
    /// 机器面：目的地集合与 SettingsDestination 全集
    /// 逐一对应）
    func testEveryDestinationIsCovered() {
        let covered = Set(SettingsCatalog.entries.map(\.destination))
        let all: [SettingsDestination] = [
            .identity, .profiles, .memory, .skills, .toolsets, .cron,
            .serverSessions, .models, .envVars, .usage,
            .serverDetail, .connectors, .devicePermissions,
            .approvalRules,
            .gateway, .logs, .status, .computer, .serverFiles,
            .appearance, .help, .about, .privacy, .terms,
            // prototype-2 叶子（枢纽目的地已退役；重启
            // 网关目的地随台账 198 收敛 S4 一并退役）
            .mainSession,
            // H1-a 新增（台账 158）
            .healthCheck,
            // 结构归位新增（断开连接动作）
            .disconnect,
            // H2-a 新增（台账 159）
            .voice,
            // 配对一期新增（台账 153/160）
            .addDevice,
            // 聊天诊断新增（台账 189/190）
            .chatDiagnostics,
        ]
        XCTAssertEqual(covered, Set(all))
    }

    /// 结构归位：agent 组五行——原智能体配置页内三项
    /// （profiles/memory/skills）提回根组直达
    func testAgentGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .agent).map(\.id),
            ["models", "profiles", "memory", "skills", "toolsets", "cron"]
        )
    }

    /// 台账 198 收敛后：serverAndWorkspace 组十二行
    /// ——四段序（服务器→会话→工作区→维护）；重启网
    /// 关行退役（S4）、语音行迁偏好组（S13）、添加
    /// 设备入服务器段（S13）
    func testServerAndWorkspaceGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .serverAndWorkspace).map(\.id),
            [
                "server", "addDevice", "gateway", "logs", "usage",
                "mainSession", "serverSessions",
                "status", "computer", "serverFiles",
                "envVars", "healthCheck",
            ]
        )
    }

    /// 台账 198 收敛 S7：四段分组与段内序——段题与
    /// 段集是根页渲染的机器口径，不许渲染层另排
    func testServerAndWorkspaceSegments() {
        let segments = SettingsCatalog.browseSegments(in: .serverAndWorkspace)
        // 台账 199 合流对账：serverSessions 条目随 199 退役出段（仅留搜索路由、目的地归全部对话），段内只剩 mainSession
        XCTAssertEqual(
            segments.map(\.segment),
            [.server, .sessions, .workspace, .maintenance]
        )
        XCTAssertEqual(
            segments.map { $0.entries.map(\.id) },
            [
                ["server", "addDevice", "gateway", "logs", "usage"],
                ["mainSession"],
                ["status", "computer", "serverFiles"],
                ["envVars", "healthCheck"],
            ]
        )
        // 无段字段的组不分段（整组一个 Section）
        XCTAssertTrue(SettingsCatalog.browseSegments(in: .agent).isEmpty)
        XCTAssertTrue(SettingsCatalog.browseSegments(in: .preferences).isEmpty)
    }

    /// preferences 组五行（台账 198 收敛 S13：语音行
    /// 自服务器组迁入、紧随外观）
    func testPreferencesGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .preferences).map(\.id),
            ["appearance", "voice", "connectors", "devicePermissions", "approvalRules"]
        )
    }

    /// 全部对话在设置内无独立条目（归位合流 2026-
    /// 11-20，纲要 D2-1／原则 6 列表只住一级面）：
    /// 目录不许长 allConversations 本体条目。台账
    /// 199（2026-11-21 用户裁）改判后半：设置「服
    /// 务端会话」行改深链直达全部对话（旧设置内名
    /// 单页已删、名单实现只剩正主一份），搜索「全
    /// 部对话」自此恰命中该深链行一条——是深链、
    /// 不是第二扇门（无第二份名单实现）
    func testAllConversationsHasNoSettingsEntry() {
        XCTAssertFalse(
            SettingsCatalog.entries.contains {
                $0.id == "allConversations"
            }
        )
        XCTAssertEqual(
            SettingsCatalog.search("全部对话").map(\.id),
            ["serverSessions"]
        )
    }

    /// 侧边栏行已退役（归位合流 2026-11-20）：分区
    /// 管理面整套退役后目录不许残留 phantom 入口
    func testSidebarEntryIsRetired() {
        XCTAssertFalse(
            SettingsCatalog.entries.contains { $0.id == "sidebar" }
        )
    }

    /// 隐藏条目（不在根页显示）：身份（卡片形态单
    /// 列）、隐私/协议（关于页内二级）、断开连接（动
    /// 作条目，浏览态由根页手写行呈现）与聊天诊断
    /// （台账 198 收敛 S13：入口迁关于页内部实验节，
    /// 只进搜索索引）
    func testHiddenFromBrowseEntries() {
        let hidden = SettingsCatalog.entries
            .filter { !$0.showsInBrowse }.map(\.id)
        XCTAssertEqual(
            Set(hidden),
["identity","privacy","terms","disconnect", "chatDiagnostics"]
        )
    }

    /// 台账 198 收敛 S13：聊天诊断根行退役后搜索仍
    /// 须点达（入口迁关于页内部实验节、搜索是第二路）
    func testChatDiagnosticsEntryIsSearchOnly() {
        let hits = SettingsCatalog.search("聊天诊断")
        XCTAssertEqual(hits.first?.id, "chatDiagnostics")
        XCTAssertEqual(hits.first?.destination, .chatDiagnostics)
        XCTAssertFalse(hits.first?.showsInBrowse ?? true)
    }

    func testSearchByChineseTitle() {
        let hits = SettingsCatalog.search("记忆")
        XCTAssertEqual(hits.first?.id, "memory")
        // 标题命中优先、且是唯一命中（枢纽页退役后无
        // 副行搭载命中）
        XCTAssertEqual(hits.map(\.id), ["memory"])
    }

    func testSearchMatchesSummaryAndKeywords() {
        // 「服务器」命中当前服务器/服务器文件（标题）、
        // 配置档案（副行含「服务器」）等多条，按清单序返回
        let hits = SettingsCatalog.search("服务器")
        XCTAssertTrue(hits.contains { $0.id == "server" })
        XCTAssertTrue(hits.contains { $0.id == "serverFiles" })
        XCTAssertTrue(hits.contains { $0.id == "profiles" })
        // 英文关键词大小写不敏感
        XCTAssertEqual(
            SettingsCatalog.search("MEMORY").map(\.id), ["memory"]
        )
        XCTAssertEqual(
            SettingsCatalog.search("mcp").map(\.id), ["connectors"]
        )
        // 断开连接搜索命中专设动作条目（标题直达）
        let disconnectHits = SettingsCatalog.search("断开连接")
        XCTAssertEqual(disconnectHits.first?.id, "disconnect")
    }

    func testSearchTrimsAndEmptyReturnsAll() {
        XCTAssertEqual(
            SettingsCatalog.search("  外观 ").map(\.id), ["appearance"]
        )
        XCTAssertEqual(
            SettingsCatalog.search("").count,
            SettingsCatalog.entries.count
        )
        XCTAssertEqual(
            SettingsCatalog.search("   ").count,
            SettingsCatalog.entries.count
        )
    }

    func testSearchNoHitIsEmpty() {
        XCTAssertTrue(SettingsCatalog.search("不存在的词条xyz").isEmpty)
    }

    /// H1-a（台账 158）：体检面条目——标题直搜命中；
    /// 结构归位后已提回根页服务器组浏览态直达
    func testHealthCheckEntryIsSearchable() {
        let hits = SettingsCatalog.search("体检")
        XCTAssertEqual(hits.first?.id, "healthCheck")
        XCTAssertEqual(hits.first?.destination, .healthCheck)
        XCTAssertEqual(hits.first?.group, .serverAndWorkspace)
        XCTAssertTrue(hits.first?.showsInBrowse ?? false)
        // 英文关键词同达
        XCTAssertTrue(
            SettingsCatalog.search("doctor").contains {
                $0.id == "healthCheck"
            }
        )
    }

    /// H2-a（台账 159）：语音条目——标题直搜命中；
    /// 台账 198 收敛 S13 归组再裁：自服务器组维护尾
    /// 段迁偏好与权限组（回复呈现偏好、与外观同族），
    /// 浏览态直达不变
    func testVoiceEntryIsSearchable() {
        let hits = SettingsCatalog.search("语音")
        XCTAssertEqual(hits.first?.id, "voice")
        XCTAssertEqual(hits.first?.destination, .voice)
        XCTAssertEqual(hits.first?.group, .preferences)
        XCTAssertTrue(hits.first?.showsInBrowse ?? false)
        // 朗读关键词同达
        XCTAssertTrue(
            SettingsCatalog.search("朗读").contains {
                $0.id == "voice"
            }
        )
    }

    /// 配对一期（台账 153/160）：添加设备条目——标
    /// 题直搜命中；台账 198 收敛 S13：自维护尾段迁
    /// 服务器段（连接引导、与当前服务器同段）；扫码
    /// 关键词同达
    func testAddDeviceEntryIsSearchable() {
        let hits = SettingsCatalog.search("添加设备")
        XCTAssertEqual(hits.first?.id, "addDevice")
        XCTAssertEqual(hits.first?.destination, .addDevice)
        XCTAssertEqual(hits.first?.group, .serverAndWorkspace)
        XCTAssertEqual(hits.first?.segment, .server)
        XCTAssertTrue(hits.first?.showsInBrowse ?? false)
        XCTAssertTrue(
            SettingsCatalog.search("扫码").contains {
                $0.id == "addDevice"
            }
        )
    }
}
