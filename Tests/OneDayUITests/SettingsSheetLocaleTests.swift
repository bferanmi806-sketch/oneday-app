import XCTest

/// A6 回归：英文语言下抽屉齿轮点按后设置 sheet 应呈现。
///
/// 事由：冒烟门第四轮 run 43634025826，A6（testSmokeA6EnglishFirstFrame）红——
/// 英文语言档（`-appLanguage en`）下齿轮点按成功、无报错，但设置 sheet 20 秒＋15 秒
/// 轮询均未呈现，齿轮随后不可命中；同 helper 中文态同轮 3 例均 1 秒内打开。
/// 本组把 A6 的最小复现收成常驻回归：英文例＋中文对照例各一。
/// 修复前英文例应红、中文例应绿；修复后两例皆绿。
///
/// 判定只认关闭钮「关闭设置」在场（SettingsView 恒传 onClose、关闭钮硬编码此标签，
/// sheet 若呈现必在场；反之 sheet 未呈现）。
final class SettingsSheetLocaleTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 英文例：复现 A6——英文档下点齿轮，设置 sheet 应升起。
    func testSettingsSheetPresentsInEnglishLocale() {
        let app = launchDemo(["-appLanguage", "en"])
        defer { app.terminate() }
        openSettingsViaDrawerGear(app)
    }

    /// 中文对照例：同一路径中文态应打开（A6 对照组同轮实证：约 1 秒即见关闭钮）。
    func testSettingsSheetPresentsInChineseLocale() {
        let app = launchDemo(["-AppleLanguages", "(zh-Hans)"])
        defer { app.terminate() }
        openSettingsViaDrawerGear(app)
    }

    // MARK: - helper（与冒烟门 openSettings 同形：先证抽屉真开再点齿轮）

    private func launchDemo(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"] + extra
        app.launch()
        XCTAssertTrue(
            app.tabBars.buttons["聊天"].waitForExistence(timeout: 25),
            "底栏应在场（标题硬编码中文，不本地化）"
        )
        return app
    }

    /// 经抽屉底条齿轮进设置；关闭钮 20 秒内应在场，验后点关闭钮收尾。
    private func openSettingsViaDrawerGear(
        _ app: XCUIApplication, line: UInt = #line
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
        let gear = app.buttons["设置"]
        XCTAssertTrue(
            gear.waitForExistence(timeout: 10),
            "抽屉底条设置钮应在场", line: line
        )
        let gearDeadline = Date().addingTimeInterval(10)
        while !gear.isHittable && Date() < gearDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(gear.isHittable, "抽屉齿轮应可命中", line: line)
        gear.tap()
        XCTAssertTrue(
            app.buttons["关闭设置"].waitForExistence(timeout: 20),
            "设置页应打开（关闭钮在场）", line: line
        )
        app.buttons["关闭设置"].tap()
    }
}
