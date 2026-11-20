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
            "server", "gateway", "restartGateway", "logs", "envVars", "usage",
            "connectors", "devicePermissions",
            "status", "computer", "serverFiles", "voice",
            "appearance", "sidebar", "help", "about",
            "disconnect",
        ] {
            XCTAssertTrue(ids.contains(id), "索引缺条目 \(id)")
        }
        // 枢纽页条目已退役、不许残留（点达不许有第二扇门）
        for id in ["agentConfig", "serverManagement", "sessionManagement", "workspace"] {
            XCTAssertFalse(ids.contains(id), "枢纽页条目 \(id) 应已退役")
        }
    }

    /// 现行主页全部目的地在清单里有锚（零丢失对账的
    /// 机器面：目的地集合与 SettingsDestination 全集
    /// 逐一对应）
    func testEveryDestinationIsCovered() {
        let covered = Set(SettingsCatalog.entries.map(\.destination))
        let all: [SettingsDestination] = [
            .identity, .profiles, .memory, .skills, .cron,
            .serverSessions, .models, .envVars, .usage,
            .serverDetail, .connectors, .devicePermissions,
            .approvalRules,
            .gateway, .logs, .status, .computer, .serverFiles,
            .appearance, .sidebar, .allConversations, .help, .about, .privacy, .terms,
            // prototype-2 叶子（枢纽目的地已退役）
            .mainSession, .restartGateway,
            // H1-a 新增（台账 158）
            .healthCheck,
            // 结构归位新增（断开连接动作）
            .disconnect,
            // H2-a 新增（台账 159）
            .voice,
        ]
        XCTAssertEqual(covered, Set(all))
    }

    /// 结构归位：agent 组五行——原智能体配置页内三项
    /// （profiles/memory/skills）提回根组直达
    func testAgentGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .agent).map(\.id),
            ["models", "profiles", "memory", "skills", "cron"]
        )
    }

    /// 结构归位：serverAndWorkspace 组十三行——三张枢
    /// 纽页子项全数提回根组（服务器本体→会话→工作区
    /// 资源→维护尾段）
    func testServerAndWorkspaceGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .serverAndWorkspace).map(\.id),
            [
                "server", "gateway", "logs", "usage",
                "mainSession", "serverSessions",
                "status", "computer", "serverFiles",
                "envVars", "restartGateway", "healthCheck", "voice",
            ]
        )
    }

    /// prototype-2：preferences 组四行（§198 侧边栏行
    /// 插在 appearance 与 connectors 之间）；管理收
    /// 口包补件起五行——全部对话行紧随侧边栏之后
    /// （用户 2026-11-13 18:57 拍板挪进设置页）
    func testPreferencesGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .preferences).map(\.id),
            ["appearance", "sidebar", "allConversations", "connectors", "devicePermissions", "approvalRules"]
        )
    }

    /// 全部对话行（管理收口包补件，用户 2026-11-13
    /// 18:57 拍板）：行在偏好组内、与侧边栏行同组相
    /// 邻（侧边栏在其上、连接器在其下），行名用页面
    /// 自身标题「全部对话」不带「管理」二字，目的地
    /// 是专设的 .allConversations（设置页据此渲动作
    /// 行、走原抽屉入口同一根级呈现路）
    func testAllConversationsEntrySitsNextToSidebar() {
        let browse = SettingsCatalog.browseEntries(in: .preferences)
        guard let idx = browse.firstIndex(where: { $0.id == "allConversations" })
        else {
            XCTFail("偏好组缺全部对话行")
            return
        }
        XCTAssertEqual(browse[idx].title, "全部对话")
        XCTAssertEqual(browse[idx].destination, .allConversations)
        XCTAssertEqual(browse[idx - 1].id, "sidebar")
        XCTAssertEqual(browse[idx + 1].id, "connectors")
        // 搜索点达同源：标题直搜命中本行
        XCTAssertTrue(
            SettingsCatalog.search("全部对话").contains {
                $0.id == "allConversations"
            }
        )
    }

    /// 隐藏条目（不在根页显示）：只剩身份（卡片形态
    /// 单列）、隐私/协议（关于页内二级）与断开连接
    /// （动作条目，浏览态由根页手写行呈现）——枢纽页
    /// 子项已全部提回根组、无一再藏
    func testHiddenFromBrowseEntries() {
        let hidden = SettingsCatalog.entries
            .filter { !$0.showsInBrowse }.map(\.id)
        XCTAssertEqual(
            Set(hidden),
["identity","privacy","terms","disconnect"]
        )
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

    /// H2-a（台账 159）：语音面条目——标题直搜命中、
    /// 归服务器管理枢纽页内子项（不在根页浏览态出现）
    func testVoiceEntryIsSearchable() {
        let hits = SettingsCatalog.search("语音")
        XCTAssertEqual(hits.first?.id, "voice")
        XCTAssertEqual(hits.first?.destination, .voice)
        XCTAssertEqual(hits.first?.group, .serverAndWorkspace)
        XCTAssertFalse(hits.first?.showsInBrowse ?? true)
        // 朗读关键词同达
        XCTAssertTrue(
            SettingsCatalog.search("朗读").contains {
                $0.id == "voice"
            }
        )
    }
}
