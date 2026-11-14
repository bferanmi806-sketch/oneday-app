import XCTest

/// 【探针分支 probe/gen5-t4-detectors 专用，禁止合入任何线】
/// 包 5 T4 数据检测探针·UI 层（筹备稿 §2.2-2 出口分流实测）：
/// 以 -odProbeDetectors 启动真 App 探针场景（真 MarkdownText＋
/// 真 Coordinator，dataDetectorTypes=候选开集，环境 openURL 已
/// 覆写为录音动作），逐行点按命中段并转储三路证据：
///  ① probe.openURLLog 文本——出口是否经 Coordinator→openURL、
///     URL 形态为何；
///  ② 当前元素树按钮/菜单/导航栏标签——系统默认动作（建日程
///     sheet／地图／链接菜单）是否绕过 Coordinator 自行呈现；
///  ③ 长按命中段 vs 长按普通段的菜单差异（与选字/长按菜单的
///     相互影响）。
/// 本文件不断言产品行为（探针采集），结果以 T4PROBE 前缀 print。
final class Gen5T4DetectorInteractionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launchProbe() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-odProbeDetectors", "-odProbeDetectorsSet=candidate",
        ]
        app.launch()
        return app
    }

    private func textView(
        containing needle: String, in app: XCUIApplication
    ) -> XCUIElement {
        let predicate = NSPredicate(
            format: "value CONTAINS %@ OR label CONTAINS %@",
            needle, needle
        )
        return app.textViews.matching(predicate).firstMatch
    }

    private func openURLLog(in app: XCUIApplication) -> String {
        let log = app.staticTexts["probe.openURLLog"]
        return log.exists ? log.label : "<log element missing>"
    }

    private func dumpState(_ tag: String, in app: XCUIApplication) {
        let buttons = app.buttons.allElementsBoundByIndex
            .map { $0.label }.filter { !$0.isEmpty }
        let menuItems = app.menuItems.allElementsBoundByIndex
            .map { $0.label }.filter { !$0.isEmpty }
        let navBars = app.navigationBars.allElementsBoundByIndex
            .map { $0.identifier }.filter { !$0.isEmpty }
        print("T4PROBE UI|\(tag)|appState=\(app.state.rawValue)|buttons=\(buttons)|menuItems=\(menuItems)|navBars=\(navBars)|sheets=\(app.sheets.count)|alerts=\(app.alerts.count)")
        print("T4PROBE UI|\(tag)|openURLLog=\"\(openURLLog(in: app))\"")
    }

    private func tapRow(
        _ tag: String, needle: String, in app: XCUIApplication
    ) {
        let row = textView(containing: needle, in: app)
        guard row.waitForExistence(timeout: 10) else {
            print("T4PROBE UI|\(tag)|row NOT FOUND needle=\(needle)")
            return
        }
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 2.0)
        dumpState("tap-\(tag)", in: app)
        // 收尾：点空白处关掉可能呈现的系统面，回到场景
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    func testTapExits() {
        let app = launchProbe()
        XCTAssertTrue(
            app.staticTexts["probe.openURLLog"].waitForExistence(timeout: 10),
            "探针场景未出现"
        )
        dumpState("initial", in: app)
        tapRow("phone", needle: "13800138000", in: app)
        tapRow("date", needle: "2026年11月16日", in: app)
        tapRow("address", needle: "西故现村", in: app)
        tapRow("url", needle: "example.com/docs", in: app)
        tapRow("email", needle: "inkroot001", in: app)
    }

    func testLongPressDetectedVsPlain() {
        let app = launchProbe()
        XCTAssertTrue(
            app.staticTexts["probe.openURLLog"].waitForExistence(timeout: 10),
            "探针场景未出现"
        )
        let phone = textView(containing: "13800138000", in: app)
        if phone.waitForExistence(timeout: 10) {
            phone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 2.0)
            Thread.sleep(forTimeInterval: 1.2)
            dumpState("longpress-phone", in: app)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            print("T4PROBE UI|longpress-phone|row NOT FOUND")
        }
        let plain = textView(containing: "普通文字", in: app)
        if plain.waitForExistence(timeout: 10) {
            plain.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 2.0)
            Thread.sleep(forTimeInterval: 1.2)
            dumpState("longpress-plain", in: app)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            print("T4PROBE UI|longpress-plain|row NOT FOUND")
        }
        // 普通段点按（非长按）对照：不应有任何出口
        tapRow("plain", needle: "普通文字", in: app)
    }
}
