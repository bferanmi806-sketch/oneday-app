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
/// 二轮修订（首轮教训）：正文左对齐、短行中心点落在文本外——
/// 电话改点左侧文本起点；日期只认时间碎片（「13:00」在行尾），
/// 按 0.70/0.82/0.93 三档横移逐个试、每点查记录变化；URL 行
/// 先转储全部 textView 值再定位。
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

    private func dismissAnySurface(in app: XCUIApplication) {
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
        // 诊断：转储全部文本视图的值，定位 URL 行为何没被找到
        for tv in app.textViews.allElementsBoundByIndex {
            print("T4PROBE UI|textViewDump|value=\"\(tv.value as? String ?? "?")\"|label=\"\(tv.label)\"")
        }

        // 电话：左对齐短文本，点文本起点附近（dx 0.12）
        let phone = textView(containing: "13800138000", in: app)
        if phone.waitForExistence(timeout: 10) {
            phone.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 2.0)
            dumpState("tap-phone-left", in: app)
            dismissAnySurface(in: app)
        } else {
            print("T4PROBE UI|tap-phone-left|row NOT FOUND")
        }

        // 日期：整行只有尾部「13:00」是命中段，三档横移逐个试
        let date = textView(containing: "2026年11月16日", in: app)
        if date.waitForExistence(timeout: 10) {
            for dx in [0.70, 0.82, 0.93] {
                let before = openURLLog(in: app)
                date.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
                Thread.sleep(forTimeInterval: 1.6)
                dumpState("tap-date-dx\(dx)", in: app)
                if openURLLog(in: app) != before {
                    print("T4PROBE UI|tap-date|log changed at dx=\(dx), stop")
                    break
                }
                dismissAnySurface(in: app)
            }
        } else {
            print("T4PROBE UI|tap-date|row NOT FOUND")
        }

        // 地址：预期无命中（中文地址引擎零命中），点按应无出口——对照
        let addr = textView(containing: "西故现村", in: app)
        if addr.waitForExistence(timeout: 10) {
            addr.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.6)
            dumpState("tap-address-left", in: app)
            dismissAnySurface(in: app)
        } else {
            print("T4PROBE UI|tap-address-left|row NOT FOUND")
        }

        // URL：用值转储里确认过的形态定位（needle 取域名片段）
        let url = textView(containing: "example.com", in: app)
        if url.waitForExistence(timeout: 10) {
            url.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 2.0)
            dumpState("tap-url-left", in: app)
            dismissAnySurface(in: app)
        } else {
            print("T4PROBE UI|tap-url-left|row NOT FOUND")
        }

        // 邮箱：复验首轮结论（mailto 经 Coordinator 录音）
        let email = textView(containing: "inkroot001", in: app)
        if email.waitForExistence(timeout: 10) {
            email.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 2.0)
            dumpState("tap-email-left", in: app)
            dismissAnySurface(in: app)
        } else {
            print("T4PROBE UI|tap-email-left|row NOT FOUND")
        }
    }

    func testLongPressDetectedVsPlain() {
        let app = launchProbe()
        XCTAssertTrue(
            app.staticTexts["probe.openURLLog"].waitForExistence(timeout: 10),
            "探针场景未出现"
        )
        let phone = textView(containing: "13800138000", in: app)
        if phone.waitForExistence(timeout: 10) {
            phone.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
                .press(forDuration: 2.0)
            Thread.sleep(forTimeInterval: 1.2)
            dumpState("longpress-phone", in: app)
            dismissAnySurface(in: app)
        } else {
            print("T4PROBE UI|longpress-phone|row NOT FOUND")
        }
        // 长按日期行的时间碎片（行尾「13:00」）：看日期段的长按菜单形态
        let date = textView(containing: "2026年11月16日", in: app)
        if date.waitForExistence(timeout: 10) {
            for dx in [0.93, 0.82] {
                date.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
                    .press(forDuration: 2.0)
                Thread.sleep(forTimeInterval: 1.2)
                dumpState("longpress-date-dx\(dx)", in: app)
                let items = app.menuItems.allElementsBoundByIndex.map { $0.label }
                dismissAnySurface(in: app)
                if items.count > 1 {
                    print("T4PROBE UI|longpress-date|menu captured at dx=\(dx), stop")
                    break
                }
            }
        } else {
            print("T4PROBE UI|longpress-date|row NOT FOUND")
        }
        let plain = textView(containing: "普通文字", in: app)
        if plain.waitForExistence(timeout: 10) {
            plain.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 2.0)
            Thread.sleep(forTimeInterval: 1.2)
            dumpState("longpress-plain", in: app)
            dismissAnySurface(in: app)
        } else {
            print("T4PROBE UI|longpress-plain|row NOT FOUND")
        }
        // 普通段点按对照：不应有任何出口
        let plainTap = textView(containing: "普通文字", in: app)
        if plainTap.waitForExistence(timeout: 10) {
            plainTap.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.2)
            dumpState("tap-plain", in: app)
        }
    }
}
