import XCTest
@testable import OneDayCore

/// 设置注册表钉测（DESIGN §437）：一期硬验收＝行为
/// 不变——回落态（能力位不亮/断服）与现行内置目录
/// 逐面全等（条目、顺序、默认值）；注册表态以假注
/// 册表验合并规则（逐面生效、永不删行、目的地锚
/// 回）与五型渲染模型各一例
final class SettingsRegistryTests: XCTestCase {

    // MARK: - 回落全等（registry = nil）

    func testFallbackBrowseRowsMatchBuiltinForEveryGroup() {
        for group in SettingsGroupID.allCases {
            let rows = SettingsCatalog.effectiveBrowseRows(
                in: group, registry: nil
            )
            let builtin = SettingsCatalog.browseEntries(in: group)
            XCTAssertEqual(
                rows.count, builtin.count,
                "\(group) 回落行数须与内置一致"
            )
            XCTAssertEqual(
                rows.compactMap { $0.destinationEntry }, builtin,
                "\(group) 回落行须与内置逐字一致（条目＋顺序）"
            )
        }
    }

    func testFallbackSegmentsMatchBuiltin() {
        let effective = SettingsCatalog.effectiveBrowseSegments(
            in: .serverAndWorkspace, registry: nil
        )
        let builtin = SettingsCatalog.browseSegments(
            in: .serverAndWorkspace
        )
        XCTAssertEqual(
            effective.map { $0.segment }, builtin.map { $0.segment }
        )
        for (effectiveSegment, builtinSegment) in zip(effective, builtin) {
            XCTAssertEqual(
                effectiveSegment.rows.compactMap { $0.destinationEntry },
                builtinSegment.entries,
                "\(effectiveSegment.segment) 段回落须全等"
            )
            XCTAssertEqual(
                effectiveSegment.rows.count, builtinSegment.entries.count
            )
        }
    }

    func testFallbackSearchMatchesBuiltin() {
        for query in ["", "记忆", "服务器", "voice", "不存在的词xyz"] {
            let rows = SettingsCatalog.effectiveSearch(
                query, registry: nil
            )
            let builtin = SettingsCatalog.search(query)
            XCTAssertEqual(
                rows.count, builtin.count,
                "查询「\(query)」回落命中数须一致"
            )
            XCTAssertEqual(
                rows.compactMap { $0.destinationEntry }, builtin,
                "查询「\(query)」回落命中须全等"
            )
        }
    }

    // MARK: - 逐面生效与逐面回落

    func testRegistryAppliesPerSurfaceAndOthersFallBack() {
        let record = SettingsRegistryRecord(
            key: "test.agent.flag", type: .bool, title: "测试开关",
            surface: SettingsGroupID.agent.rawValue, sort: 0,
            defaultValue: .bool(true)
        )
        let registry = SettingsRegistryResponse(
            version: 1, records: [record]
        )

        // agent 面：值行按记录序在前、内置条目原序附后
        let agentRows = SettingsCatalog.effectiveBrowseRows(
            in: .agent, registry: registry
        )
        XCTAssertEqual(agentRows.first, .value(record))
        XCTAssertEqual(
            agentRows.dropFirst().compactMap { $0.destinationEntry },
            SettingsCatalog.browseEntries(in: .agent),
            "未被引用的内置条目不许丢、按原序附后"
        )

        // 其余面：无有效记录→逐面回落全等
        for group in [
            SettingsGroupID.preferences, .support, .serverAndWorkspace,
        ] {
            let rows = SettingsCatalog.effectiveBrowseRows(
                in: group, registry: registry
            )
            XCTAssertEqual(
                rows.compactMap { $0.destinationEntry },
                SettingsCatalog.browseEntries(in: group),
                "\(group) 无注册表记录时须回落全等"
            )
            XCTAssertEqual(
                rows.count,
                SettingsCatalog.browseEntries(in: group).count
            )
        }

        // 分段面在「注册表在场但本组回落」时同样全等
        let segments = SettingsCatalog.effectiveBrowseSegments(
            in: .serverAndWorkspace, registry: registry
        )
        let builtinSegments = SettingsCatalog.browseSegments(
            in: .serverAndWorkspace
        )
        XCTAssertEqual(
            segments.map { $0.segment }, builtinSegments.map { $0.segment }
        )
        for (seg, builtin) in zip(segments, builtinSegments) {
            XCTAssertEqual(
                seg.rows.compactMap { $0.destinationEntry },
                builtin.entries
            )
        }
    }

    // MARK: - 五型渲染模型

    func testFiveTypeRowModels() {
        // bool：回读值优先于默认值
        let boolModel = SettingsRegistryRowModel(record:
            SettingsRegistryRecord(
                key: "t.bool", type: .bool, title: "开关",
                surface: "preferences",
                defaultValue: .bool(true), value: .bool(false)
            ))
        XCTAssertEqual(boolModel.kind, .toggle)
        XCTAssertFalse(boolModel.boolValue)

        // bool：无回读值回落默认值
        let boolDefaultModel = SettingsRegistryRowModel(record:
            SettingsRegistryRecord(
                key: "t.bool2", type: .bool, title: "开关二",
                surface: "preferences", defaultValue: .bool(true)
            ))
        XCTAssertTrue(boolDefaultModel.boolValue)

        // enum：选中回读值；候选集透传
        let enumModel = SettingsRegistryRowModel(record:
            SettingsRegistryRecord(
                key: "t.enum", type: .enumeration, title: "选择",
                surface: "preferences",
                options: ["甲", "乙"], value: .string("乙")
            ))
        XCTAssertEqual(enumModel.kind, .picker)
        XCTAssertEqual(enumModel.stringValue, "乙")
        XCTAssertEqual(enumModel.options, ["甲", "乙"])

        // enum：无值回落首候选
        let enumDefaultModel = SettingsRegistryRowModel(record:
            SettingsRegistryRecord(
                key: "t.enum2", type: .enumeration, title: "选择二",
                surface: "preferences", options: ["甲", "乙"]
            ))
        XCTAssertEqual(enumDefaultModel.stringValue, "甲")

        // string
        let stringModel = SettingsRegistryRowModel(record:
            SettingsRegistryRecord(
                key: "t.string", type: .string, title: "文本",
                surface: "preferences", value: .string("abc")
            ))
        XCTAssertEqual(stringModel.kind, .textField)
        XCTAssertEqual(stringModel.stringValue, "abc")

        // number
        let numberModel = SettingsRegistryRowModel(record:
            SettingsRegistryRecord(
                key: "t.number", type: .number, title: "数值",
                surface: "preferences", value: .number(42)
            ))
        XCTAssertEqual(numberModel.kind, .numberField)
        XCTAssertEqual(numberModel.numberValue, 42)

        // text：长文走文本块、默认值生效
        let textModel = SettingsRegistryRowModel(record:
            SettingsRegistryRecord(
                key: "t.text", type: .text, title: "长文",
                surface: "preferences", defaultValue: .string("长文内容")
            ))
        XCTAssertEqual(textModel.kind, .textBlock)
        XCTAssertEqual(textModel.stringValue, "长文内容")
    }

    func testFiveTypesAppearAsValueRowsInSortOrder() {
        let records = [
            SettingsRegistryRecord(
                key: "t.text", type: .text, title: "长文",
                surface: "preferences", sort: 5
            ),
            SettingsRegistryRecord(
                key: "t.bool", type: .bool, title: "开关",
                surface: "preferences", sort: 1
            ),
            SettingsRegistryRecord(
                key: "t.number", type: .number, title: "数值",
                surface: "preferences", sort: 4
            ),
            SettingsRegistryRecord(
                key: "t.enum", type: .enumeration, title: "选择",
                surface: "preferences", sort: 2, options: ["甲"]
            ),
            SettingsRegistryRecord(
                key: "t.string", type: .string, title: "文本",
                surface: "preferences", sort: 3
            ),
        ]
        let registry = SettingsRegistryResponse(
            version: 1, records: records
        )
        let rows = SettingsCatalog.effectiveBrowseRows(
            in: .preferences, registry: registry
        )
        let valueKinds = rows.prefix(5).map { row -> SettingsRegistryRowModel.ControlKind? in
            if case .value(let record) = row {
                return SettingsRegistryRowModel(record: record).kind
            }
            return nil
        }
        XCTAssertEqual(
            valueKinds,
            [.toggle, .picker, .textField, .numberField, .textBlock],
            "五型须按 sort 序成行、控件型逐一对位"
        )
        // 内置偏好条目随后附上（永不删行）
        XCTAssertEqual(
            rows.dropFirst(5).compactMap { $0.destinationEntry },
            SettingsCatalog.browseEntries(in: .preferences)
        )
    }

    // MARK: - 目的地记录（锚回、重排、丢弃）

    func testDestinationRecordsAnchorReorderAndDropInvalid() {
        let registry = SettingsRegistryResponse(version: 1, records: [
            SettingsRegistryRecord(
                key: "reg.about", title: "关于",
                surface: "support", sort: 0, destination: "about"
            ),
            SettingsRegistryRecord(
                key: "reg.ghost", title: "不存在",
                surface: "support", sort: 1, destination: "nope"
            ),
            SettingsRegistryRecord(
                key: "reg.cross", title: "跨组",
                surface: "support", sort: 2, destination: "models"
            ),
            SettingsRegistryRecord(
                key: "reg.help", title: "帮助",
                surface: "support", sort: 3, destination: "help"
            ),
        ])
        let rows = SettingsCatalog.effectiveBrowseRows(
            in: .support, registry: registry
        )
        XCTAssertEqual(
            rows.compactMap { $0.destinationEntry?.id },
            ["about", "help"],
            "目的地记录按 sort 重排；不存在/跨组记录丢弃"
        )
        XCTAssertEqual(rows.count, 2)
    }

    func testPartialDestinationRecordsKeepUnreferencedEntries() {
        let registry = SettingsRegistryResponse(version: 1, records: [
            SettingsRegistryRecord(
                key: "reg.about", title: "关于",
                surface: "support", sort: 0, destination: "about"
            ),
        ])
        let rows = SettingsCatalog.effectiveBrowseRows(
            in: .support, registry: registry
        )
        XCTAssertEqual(
            rows.compactMap { $0.destinationEntry?.id },
            ["about", "help"],
            "被引用的提前、未引用的按原序附后（永不删行）"
        )
    }

    func testSearchOnlyDestinationRecordDoesNotEnterBrowse() {
        let registry = SettingsRegistryResponse(version: 1, records: [
            SettingsRegistryRecord(
                key: "reg.privacy", title: "隐私",
                surface: "support", sort: 0, destination: "privacy"
            ),
        ])
        let rows = SettingsCatalog.effectiveBrowseRows(
            in: .support, registry: registry
        )
        XCTAssertEqual(
            rows.compactMap { $0.destinationEntry },
            SettingsCatalog.browseEntries(in: .support),
            "搜索专行不因注册表登记被提进浏览，结果与回落全等"
        )
    }

    // MARK: - 注册表态搜索

    func testRegistrySearchIncludesValueRows() {
        let record = SettingsRegistryRecord(
            key: "test.agent.flag", type: .bool, title: "测试开关",
            surface: "agent", defaultValue: .bool(true)
        )
        let registry = SettingsRegistryResponse(
            version: 1, records: [record]
        )
        let hits = SettingsCatalog.effectiveSearch(
            "测试开关", registry: registry
        )
        XCTAssertTrue(
            hits.contains(.value(record)),
            "值行须可按题搜达"
        )
        let memoryHits = SettingsCatalog.effectiveSearch(
            "记忆", registry: registry
        )
        XCTAssertEqual(
            memoryHits.first?.destinationEntry?.id, "memory",
            "条目题命中仍居首（现行搜索分层不变）"
        )
    }

    // MARK: - 解码容错与能力位

    func testRegistryResponseDecodingIsTolerant() throws {
        let json = """
        {"version": 3, "records": [
          {"key": "a.b", "type": "bool", "title": "开关",
           "surface": "agent", "default": true, "value": false},
          {"key": "a.c", "type": "enum", "title": "选择",
           "surface": "agent", "options": ["x", "y"], "default": "y"},
          {"key": "a.d", "type": "link", "title": "入口",
           "surface": "agent", "destination": "models"},
          {"key": "a.e", "title": "缺类型", "surface": "agent"}
        ]}
        """
        let response = try JSONDecoder().decode(
            SettingsRegistryResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.version, 3)
        XCTAssertEqual(response.records.count, 4)
        XCTAssertEqual(response.records[0].type, .bool)
        XCTAssertEqual(
            response.records[0].effectiveValue, .bool(false),
            "回读值优先于默认值"
        )
        XCTAssertEqual(
            response.records[1].effectiveValue, .string("y"),
            "无回读值回落默认值"
        )
        XCTAssertNil(
            response.records[2].type,
            "未知型不猜测、落 nil（目的地记录不依赖类型）"
        )
        XCTAssertEqual(response.records[2].destination, "models")
        XCTAssertNil(response.records[3].type)
    }

    /// §450（R4）：按 key 直查——审批规则页据此取
    /// 两条 config-backed 写入审批记录呈现；缺失返
    /// 回 nil（消费方整行不出、不造假行）
    func testRecordForKeyFindsConfigBackedApprovals() {
        let registry = SettingsRegistryResponse(version: 1, records: [
            SettingsRegistryRecord(
                key: "memory.write_approval", type: .bool,
                title: "记忆写入审批",
                surface: "settings.agent", sort: 0,
                defaultValue: .bool(true), value: .bool(true)
            ),
            SettingsRegistryRecord(
                key: "skills.write_approval", type: .bool,
                title: "技能写入审批",
                surface: "settings.agent", sort: 1,
                defaultValue: .bool(true), value: .bool(true)
            ),
        ])
        XCTAssertEqual(
            registry.record(forKey: "memory.write_approval")?.title,
            "记忆写入审批"
        )
        XCTAssertEqual(
            registry.record(forKey: "skills.write_approval")?.title,
            "技能写入审批"
        )
        XCTAssertNil(registry.record(forKey: "no.such.key"))
    }

    func testSettingsRegistryAvailabilityReadsFeatureFlag() throws {
        let decoder = JSONDecoder()
        let on = try decoder.decode(
            CapabilitiesResponse.self,
            from: Data(#"{"features": {"settings_registry": true}}"#.utf8)
        )
        XCTAssertEqual(
            CapabilityNegotiation.settingsRegistryAvailability(on),
            .available
        )
        let off = try decoder.decode(
            CapabilitiesResponse.self,
            from: Data(#"{"features": {"settings_registry": false}}"#.utf8)
        )
        XCTAssertEqual(
            CapabilityNegotiation.settingsRegistryAvailability(off),
            .unavailable
        )
        let missing = try decoder.decode(
            CapabilitiesResponse.self, from: Data(#"{}"#.utf8)
        )
        XCTAssertEqual(
            CapabilityNegotiation.settingsRegistryAvailability(missing),
            .unknown
        )
        XCTAssertEqual(
            CapabilityNegotiation.settingsRegistryAvailability(nil),
            .unknown
        )
    }
}
