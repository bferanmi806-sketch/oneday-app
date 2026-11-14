import XCTest

/// 出厂冒烟门（2026-11-14 立门，release-smoke-gate-20261114.md）：
/// 把「默认路径之外真用一遍」落成 UI 真执行——开关真拨、
/// 数据真非空、首帧真渲染。本套件红＝不许组版交付
/// （DESIGN §190 前置子集）。
///
/// 覆盖正源＝同类横扫 same-class-sweep-20261114.md A 类：
/// A-1 连接页首连／A-4 文件网格／A-6 英文首帧／A-8 抽屉
/// 分区关态在本文件；A-2 存量迁移在 OneDayAppTests 的
/// SmokeGateMigrationTests；A-3/A-5/A-7 自动化够不到，
/// 逐条转发版门文档真机手验清单（报告有对照表）。
/// A-0（gen3 实验开关）两例在本文件：设置内真拨＋启动
/// 参数预置首帧。基线 rel-05045 未含热修
/// （fix/gen3-scroll-reentrancy），两例在基线上预期红
/// ——冒烟门当场抓住 A-0 即立门证据；热修并入后转绿。
final class SmokeGateUITests: XCTestCase {

    /// 演示种子线程首帧可见文（run 43612107391 自查
    /// 纠正：旧表 5 条没有一条落在首个种子线程里——
    /// 「三个节点都在线」是第二线程；「帮我看看服务
    /// 器现在的状态。」是标点近似，种子原文此处是
    /// 「，」；「演示旁聊起手」「这单演示数据是假的」
    /// 全仓不存在；「演示旁聊中段」是第三线程。现表
    /// 只取首线程（「帮我看看服务器状态」）消息的精
    /// 确子串：尾三条（开线程默认落底、必在树里）＋
    /// 头两条（列表若落顶时兜底），任一命中即算开出。
    private let seedMarkers = [
        "好，就按你说的顺序来。",
        "我盯五项，按重要性排",
        "巡检类的定时任务，一般都盯哪些指标？",
        "帮我看看服务器现在的状态，顺便确认",
        "刚查过，一切正常",
    ]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// pinChineseLocale：CI 模拟器是英文区域（DrawerRow
    /// 注释实证），演示文案经词条库本地化——不钉语言，
    /// 「开始连接」等按钮以英文渲染、按中文查必然超时
    /// （run 43612107391 的 A1 即此）。标准做法：
    /// -AppleLanguages (zh-Hans)。A6 测英文路径，显式
    /// 传 false（其断言只认硬编码中文件＋本地化行）。
    private func launchDemo(
        _ extra: [String], pinChineseLocale: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-odDemoMode"]
        if pinChineseLocale {
            args += ["-AppleLanguages", "(zh-Hans)"]
        }
        args += extra
        app.launchArguments = args
        app.launch()
        return app
    }

    /// 等任一文案出现在无障碍树（轮询多元素类型）
    private func waitForAnyText(
        _ app: XCUIApplication, _ needles: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for needle in needles {
                let hit = app.descendants(matching: .any)
                    .matching(NSPredicate(
                        format: "label CONTAINS %@", needle
                    )).firstMatch
                if hit.exists { return true }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }

    /// 开抽屉并点进第一条本地种子线程（非空首帧落点）
    private func openFirstSeededThread(
        _ app: XCUIApplication, line: UInt = #line
    ) {
        let rows = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "drawer.row.side.local."
        ))
        if !rows.firstMatch.waitForExistence(timeout: 6) {
            // 抽屉未开（设置关闭后可能已收回）：先开抽屉
            let opener = app.buttons["drawer.open"]
            XCTAssertTrue(
                opener.waitForExistence(timeout: 15),
                "抽屉开启钮应在场", line: line
            )
            opener.tap()
        }
        XCTAssertTrue(
            rows.firstMatch.waitForExistence(timeout: 15),
            "抽屉本地种子行应在场", line: line
        )
        if !rows.firstMatch.isHittable {
            app.swipeUp()
        }
        rows.firstMatch.tap()
    }

    /// 经抽屉底条齿轮进设置（演示态既有路径）。
    /// run 43612107391 自查：三例同卡于「关闭钮未现」
    /// ——齿轮在抽屉宿主常驻、未开时也可能已在树里，
    /// 只查存在就点，可能点到未落定的抽屉动画或离屏
    /// 钮。本版三道加固：①等频道行可命中、确认抽屉
    /// 真开；②齿轮可命中才点；③关钮 20 秒未现则重
    /// 拨一次（置位只在呈现时消费，重拨幂等），仍未
    /// 现把当场按钮清单写进断言、供下一轮日志定位。
    /// 生产路径真机可证（用户当晚在设置里拨过开关），
    /// 若加固后重跑仍卡于此步，即升产品问题处理。
    private func openSettings(
        _ app: XCUIApplication,
        gearLabels: [String] = ["设置"],
        closeLabel: String = "关闭设置",
        line: UInt = #line
    ) {
        let opener = app.buttons["drawer.open"]
        XCTAssertTrue(
            opener.waitForExistence(timeout: 25),
            "抽屉开启钮应在场", line: line
        )
        opener.tap()
        let channelRow = app.buttons["drawer.row.channel.hermes"]
        XCTAssertTrue(
            channelRow.waitForExistence(timeout: 15),
            "抽屉应打开（频道行在场）", line: line
        )
        var gear: XCUIElement?
        for label in gearLabels {
            let candidate = app.buttons[label]
            if candidate.waitForExistence(timeout: 8) {
                gear = candidate
                break
            }
        }
        guard let gear else {
            XCTFail("抽屉底条设置钮应在场", line: line)
            return
        }
        let gearDeadline = Date().addingTimeInterval(10)
        while !gear.isHittable && Date() < gearDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(gear.isHittable, "抽屉齿轮应可命中", line: line)
        gear.tap()
        if !app.buttons[closeLabel].waitForExistence(timeout: 20) {
            if gear.exists && gear.isHittable {
                gear.tap()
            }
            if !app.buttons[closeLabel].waitForExistence(timeout: 15) {
                let visible = app.buttons.allElementsBoundByIndex
                    .prefix(20).map { $0.label }
                    .joined(separator: " | ")
                XCTFail(
                    "设置页应打开（关闭钮在场）；当场按钮：\(visible)",
                    line: line
                )
                return
            }
        }
    }

    /// 在设置列表里滚动直到元素可点
    @discardableResult
    private func scrollSettings(
        _ app: XCUIApplication, until element: XCUIElement,
        maxSwipes: Int = 18
    ) -> Bool {
        let list = app.tables.firstMatch.exists
            ? app.tables.firstMatch
            : app.scrollViews.firstMatch
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return true
            }
            list.swipeUp()
        }
        return element.exists && element.isHittable
    }

    // MARK: - A-0 实验开关·gen3 新承载（两路）

    /// 设置内真拨：默认关→拨开→进非空线程首帧不崩。
    /// 通过后拨回关，免污染同轮其他套件的沙盒默认值。
    func testSmokeGen3FlipFromSettings() {
        let app = launchDemo([])
        openSettings(app)
        let toggle = app.switches["会话页新承载"]
        XCTAssertTrue(
            scrollSettings(app, until: toggle),
            "实验组 gen3 开关应可达"
        )
        XCTAssertEqual(
            toggle.value as? String, "0", "基线默认应为关"
        )
        toggle.tap()
        XCTAssertEqual(
            app.state, .runningForeground,
            "拨开新承载后 App 必须存活（基线未含热修时在此崩，门即为拦此）"
        )
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["关闭设置"].tap()
        openFirstSeededThread(app)
        XCTAssertTrue(
            waitForAnyText(app, seedMarkers, timeout: 25),
            "新承载首帧应渲染出种子消息（非空）"
        )
        XCTAssertEqual(app.state, .runningForeground)
        // 恢复默认关
        openSettings(app)
        let toggleBack = app.switches["会话页新承载"]
        XCTAssertTrue(scrollSettings(app, until: toggleBack))
        if (toggleBack.value as? String) == "1" {
            toggleBack.tap()
        }
        XCTAssertEqual(toggleBack.value as? String, "0")
        app.buttons["关闭设置"].tap()
    }

    /// 预置开启首帧：启动参数域预置 gen3=YES 直达会话，
    /// 复刻用户「开着开关冷启动」路径（.ips 实况）。
    func testSmokeGen3PresetFirstFrame() {
        let app = launchDemo(["-chat.carrier.gen3", "YES"])
        XCTAssertTrue(
            app.buttons["drawer.open"]
                .waitForExistence(timeout: 25),
            "开着新承载冷启动必须活着进主界面（基线未含热修时启动即崩）"
        )
        openFirstSeededThread(app)
        XCTAssertTrue(
            waitForAnyText(app, seedMarkers, timeout: 25),
            "新承载首帧应渲染出种子消息（非空）"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - A-1 连接页装配与首连全流程

    /// -odDemoConnect 全新安装路径：欢迎面→登录面预填
    /// →点连接→四步探活（演示假回执）→进主界面。横扫
    /// 实查此启动参数此前在 Tests/ 内零引用。
    func testSmokeA1ConnectFirstRun() {
        let app = XCUIApplication()
        // 语言钉中文：连接页按钮走词条库本地化，CI 英文
        // 模拟器上不钉则以英文渲染、「开始连接」永查不到
        // （run 43612107391 实证）。
        app.launchArguments = [
            "-odDemoConnect", "-AppleLanguages", "(zh-Hans)",
        ]
        app.launch()
        let start = app.buttons["开始连接"]
        XCTAssertTrue(
            start.waitForExistence(timeout: 25),
            "连接页欢迎面首帧应渲染"
        )
        start.tap()
        let connect = app.buttons.matching(NSPredicate(
            format: "label IN %@",
            ["测试并连接", "验证并连接"]
        )).firstMatch
        XCTAssertTrue(
            connect.waitForExistence(timeout: 12),
            "登录面应渲染出连接钮（表单真装配）"
        )
        XCTAssertTrue(
            app.textFields.count + app.secureTextFields.count >= 2,
            "登录面表单字段应在场"
        )
        connect.tap()
        // 成功页须手动点「开始聊天」才进主界面
        // （ConnectView successPage：无自动跳转；
        // run 43634025826 实证：点连接后 35 秒轮询
        // drawer.open 永不到，因停在成功页）。
        // 「开始聊天」永不出现＝探活失败，先在此分清。
        let begin = app.buttons["开始聊天"]
        XCTAssertTrue(
            begin.waitForExistence(timeout: 35),
            "探活成功后应出现「开始聊天」（未出现＝探活失败）"
        )
        begin.tap()
        XCTAssertTrue(
            app.buttons["drawer.open"]
                .waitForExistence(timeout: 25),
            "首连全流程走完应进主界面"
        )
    }

    // MARK: - A-4 文件网格模式首帧

    /// files.displayMode 非默认档（grid）持久化后进资源
    /// 库首帧：网格真渲染出种子文件。
    /// run 43612107391 自查：旧断言按文件名查影音格，
    /// 但网格态 MediaCell 刻意不渲染文件名（0.36.4：
    /// 生成图名多为哈希串、属原始名漏出，已撤除），
    /// 按名查在网格态永远查不到。本版改断两件网格态
    /// 真渲染的东西：①文件段网格卡带标题（displayTitle
    /// 去扩展名），任一 seeded 文档卡名命中即算数据到
    /// 位；②全页按钮数下限（底栏 5＋影音格 4＋文件卡
    /// 4，取 10 作松下限），证影音格真有格子而非空态。
    /// 另断空态文案不在场（collect 空集才会出空态）。
    func testSmokeA4FilesGridFirstFrame() {
        let app = launchDemo(["-files.displayMode", "grid"])
        let tab = app.tabBars.buttons["资源库"]
        XCTAssertTrue(tab.waitForExistence(timeout: 25))
        tab.tap()
        XCTAssertTrue(
            waitForAnyText(
                app,
                ["网络巡检周报", "每日简报-1108", "交付说明"],
                timeout: 30
            ),
            "网格首帧应渲染出种子文件卡（文件段卡名）"
        )
        XCTAssertFalse(
            app.staticTexts["暂无影音交付"].exists
                || app.staticTexts["暂无交付物"].exists,
            "网格首帧不应落空态（聚合已到数据）"
        )
        XCTAssertGreaterThanOrEqual(
            app.buttons.count, 10,
            "网格首帧按钮数应含底栏＋影音格＋文件卡（≥10）"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - A-6 英文语言路径首帧

    /// appLanguage=en：设置面以英文真渲染（词条库 3225
    /// 条 en 全译；实验组标题与 gen3 开关名未入词条库、
    /// 英文态回落中文——登记项，不在本例断言）。
    /// run 43612107391 自查：旧断言两处查无此物——底栏
    /// 标题是 TabBarSymbols 硬编码中文（.labelStyle
    /// (.iconOnly)＋.accessibilityLabel(pair.title)），
    /// 「Chat」在任何语言下都不存在；设置关闭钮的
    /// accessibilityLabel 也是硬编码「关闭设置」，
    /// 「Close Settings」同样查不到。英文证明只剩本地
    /// 化行（Appearance 行），底栏只断在场。另登记产品
    /// 观察：底栏标题未本地化（A-6 原前提「底栏英文」
    /// 不成立），修不修归主线，本线只改测试预期。
    func testSmokeA6EnglishFirstFrame() {
        let app = launchDemo(
            ["-appLanguage", "en"], pinChineseLocale: false
        )
        XCTAssertTrue(
            app.tabBars.buttons["聊天"]
                .waitForExistence(timeout: 25),
            "英文态底栏应在场（标题硬编码中文，不本地化）"
        )
        openSettings(
            app, gearLabels: ["Settings", "设置"],
            closeLabel: "关闭设置"
        )
        let appearance = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "label == %@", "Appearance"
            )).firstMatch
        XCTAssertTrue(
            scrollSettings(app, until: appearance),
            "英文态设置面应渲染出 Appearance 行"
        )
        app.buttons["关闭设置"].tap()
    }

    // MARK: - 开关盘点·全部对话「显示系统运行」

    /// 开关真拨：点 knob 坐标＋轮询读值。
    /// run 43634025826 实证：整行中点点按事件已合成、
    /// 值仍为 "0"，点按后 0.3 秒立即读值不可靠——
    /// 落点改点开关 trailing 侧 knob，读值改带超时轮询。
    private func tapSwitchKnobAndWait(
        _ app: XCUIApplication, label: String,
        to expected: String, timeout: TimeInterval = 8,
        line: UInt = #line
    ) {
        let toggle = app.switches[label]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 20),
            "开关应在场", line: line
        )
        toggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (app.switches[label].value as? String) == expected {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(
            app.switches[label].value as? String, expected,
            "开关拨后值应为 \(expected)", line: line
        )
    }

    /// 视图内开关真拨：开后分段多出「系统」段（系统运
    /// 行会话的唯一用户面入口），拨回关恢复。
    func testSmokeAllConversationsSystemRunsToggle() {
        let app = launchDemo([])
        openSettings(app)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "label == %@", "全部对话"
            )).firstMatch
        XCTAssertTrue(
            scrollSettings(app, until: row),
            "设置内全部对话行应可达"
        )
        row.tap()
        let toggle = app.switches["显示系统运行"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 20),
            "全部对话页应打开且开关在场"
        )
        XCTAssertEqual(toggle.value as? String, "0")
        tapSwitchKnobAndWait(app, label: "显示系统运行", to: "1")
        XCTAssertTrue(
            app.buttons["系统"].waitForExistence(timeout: 10),
            "开启后分段应多出「系统」段"
        )
        tapSwitchKnobAndWait(app, label: "显示系统运行", to: "0")
        app.buttons["完成"].tap()
    }

    // MARK: - 偏好路径合并冒烟（深色＋主题＋头像尺寸）

    /// 三个值域型偏好一次预置非默认值：深色外观＋
    /// obsidian 聊天主题＋大头像——会话首帧照常渲染。
    func testSmokePreferencesDarkThemeAvatar() {
        let app = launchDemo([
            "-appearanceMode", "dark",
            "-chatTheme", "obsidian",
            "-avatarSize", "large",
        ])
        XCTAssertTrue(
            app.buttons["drawer.open"]
                .waitForExistence(timeout: 25)
        )
        openFirstSeededThread(app)
        XCTAssertTrue(
            waitForAnyText(app, seedMarkers, timeout: 25),
            "深色＋非默认主题＋大头像下首帧应渲染种子消息"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - A-8 抽屉分区可见性关态（排末位，内含恢复）

    /// 设置页「旁聊」选择器：按值域与抽屉分区头区分——
    /// Picker（.menu）值为当前显隐「显示/隐藏」，抽屉
    /// 同标签分区头值为折叠态「已展开/已收起」；
    /// app.buttons["旁聊"] 取首匹配会命中常驻抽屉头
    /// （run 43634025826 实证：帧宽 277.7、不可命中）。
    private func settingsSideChatPicker(
        _ app: XCUIApplication
    ) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label == %@ AND (value == %@ OR value == %@)",
            "旁聊", "显示", "隐藏"
        )).firstMatch
    }

    /// 设置→侧边栏把「旁聊」设为隐藏：抽屉旁聊行消失、
    /// 频道行仍在；再设回显示，行恢复。关态装配此前
    /// CI 零执行。命名 Z 前缀保证类内末位执行。
    func testSmokeZA8DrawerSectionVisibility() {
        let app = launchDemo([])
        openSettings(app)
        let sidebarRow = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "label == %@", "侧边栏"
            )).firstMatch
        XCTAssertTrue(
            scrollSettings(app, until: sidebarRow),
            "设置内侧边栏行应可达"
        )
        sidebarRow.tap()
        let picker = settingsSideChatPicker(app)
        XCTAssertTrue(
            picker.waitForExistence(timeout: 12),
            "侧边栏管理面应打开（旁聊选择器在场）"
        )
        picker.tap()
        let hide = app.buttons["隐藏"]
        XCTAssertTrue(hide.waitForExistence(timeout: 8))
        hide.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["关闭设置"].tap()
        // 抽屉验关态
        let opener = app.buttons["drawer.open"]
        XCTAssertTrue(opener.waitForExistence(timeout: 15))
        opener.tap()
        XCTAssertTrue(
            app.buttons["drawer.row.channel.hermes"]
                .waitForExistence(timeout: 12),
            "关态下频道行仍应在场"
        )
        let sideRows = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "drawer.row.side.local."
        ))
        XCTAssertEqual(
            sideRows.count, 0, "旁聊分区隐藏后抽屉不应有旁聊行"
        )
        // 恢复显示（同轮后续套件依赖默认态）
        openSettings(app)
        let sidebarRow2 = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "label == %@", "侧边栏"
            )).firstMatch
        XCTAssertTrue(scrollSettings(app, until: sidebarRow2))
        sidebarRow2.tap()
        let picker2 = settingsSideChatPicker(app)
        XCTAssertTrue(picker2.waitForExistence(timeout: 12))
        picker2.tap()
        let show = app.buttons["显示"]
        XCTAssertTrue(show.waitForExistence(timeout: 8))
        show.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["关闭设置"].tap()
        let opener2 = app.buttons["drawer.open"]
        XCTAssertTrue(opener2.waitForExistence(timeout: 15))
        opener2.tap()
        XCTAssertTrue(
            sideRows.firstMatch.waitForExistence(timeout: 12),
            "恢复显示后旁聊行应回来"
        )
    }
}
