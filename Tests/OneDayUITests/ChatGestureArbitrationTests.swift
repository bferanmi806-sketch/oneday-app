import XCTest

/// §265（换代包 5）手势仲裁系统级验收：打
/// -odDemoMode 真 App 生产装配，XCUITest 投递
/// 真手势，验 C4 两路与 T4 两条件：
/// 1. 长按正文文本→系统编辑菜单（选字），整行
///    菜单不出现（S3：菜单已下移非文本层）；
/// 2. 长按气泡内边距带（非文本层）→整行菜单出
///    现（按 SF Symbol 标识查、与语言无关——
///    DrawerRowContextMenuTests 先例）；
/// 3. 双击正文→选词＋编辑菜单，整行菜单不出现
///    （右滑 pan 的失败依赖＝点按先行的可见证）；
/// 4. 右滑一行→引用横幅出现（「取消引用」钮，
///    字面量 accessibilityLabel、与语言无关）；
/// 5. 长按电话命中段→系统链接菜单（Call 项，
///    T4 条件①），整行菜单不出现——与 S3 仲裁
///    同面共存（探针报告 §5.2 的生产复验）。
final class ChatGestureArbitrationTests: XCTestCase {

    /// 整行菜单首项（回复）的 SF Symbol 标识
    private let rowMenuReplySymbol =
        "arrowshape.turn.up.left"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 用例

    func testLongPressOnTextShowsEditMenuNotRowMenu() throws {
        let app = launchDemoApp()
        let text = try lastUserTextView(in: app)
        text.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).press(forDuration: 1.2)
        assertEditMenuShown(in: app)
        assertRowMenuAbsent(in: app)
    }

    func testLongPressOnBubblePaddingShowsRowMenu() throws {
        let app = launchDemoApp()
        let text = try lastUserTextView(in: app)
        // 气泡左内边距带中点：文本视图左缘外 8pt
        // （bubblePaddingH=16 的带宽一半处）
        let frame = text.frame
        let point = windowPoint(
            in: app, x: frame.minX - 8, y: frame.midY
        )
        point.press(forDuration: 1.5)
        let item = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                rowMenuReplySymbol
            )
        ).firstMatch
        if !item.waitForExistence(timeout: 10) {
            XCTFail(
                "长按气泡边距带未出整行菜单；当时按钮树："
                    + treeSnapshot(in: app)
            )
        }
        XCTAssertTrue(item.isHittable)
    }

    func testDoubleTapOnTextSelectsWordNotRowMenu() throws {
        let app = launchDemoApp()
        let text = try lastUserTextView(in: app)
        text.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).doubleTap()
        assertEditMenuShown(in: app)
        assertRowMenuAbsent(in: app)
    }

    func testSwipeRightOnRowTriggersReplyQuote() throws {
        let app = launchDemoApp()
        let text = try lastUserTextView(in: app)
        let frame = text.frame
        let start = windowPoint(
            in: app, x: frame.minX + 12, y: frame.midY
        )
        let end = windowPoint(
            in: app, x: frame.minX + 172, y: frame.midY
        )
        start.press(forDuration: 0.05, thenDragTo: end)
        let cancel = app.buttons["取消引用"]
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 8),
            "右滑过线后引用横幅未出现；当时按钮树："
                + treeSnapshot(in: app)
        )
    }

    func testLongPressOnPhoneShowsLinkMenuNotRowMenu() throws {
        let app = launchDemoApp()
        let text = try contactTextView(in: app)
        // 号码在文本首行前段（「值班电话 」之后）：
        // 取文本视图帧内 (0.32, 0.30) 处
        text.coordinate(
            withNormalizedOffset: CGVector(dx: 0.32, dy: 0.30)
        ).press(forDuration: 1.2)
        // 系统链接菜单的判别项＝Call（编辑菜单无此
        // 项；中英两档标签都认）
        let callItem = app.menuItems.matching(
            NSPredicate(
                format: "label IN %@", ["Call", "呼叫"]
            )
        ).firstMatch
        let callButton = app.buttons.matching(
            NSPredicate(
                format: "label IN %@", ["Call", "呼叫"]
            )
        ).firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              !callItem.exists, !callButton.exists {
            Thread.sleep(forTimeInterval: 0.3)
        }
        if !callItem.exists, !callButton.exists {
            XCTFail(
                "长按电话命中段未出系统链接菜单；"
                    + "当时按钮树：" + treeSnapshot(in: app)
            )
        }
        assertRowMenuAbsent(in: app)
    }

    // MARK: - 装配与查找

    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        return app
    }

    /// 末条用户消息的正文文本视图（演示种子末条
    /// 用户消息「好，就按你说的顺序来。」）
    private func lastUserTextView(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        let text = app.textViews.matching(
            NSPredicate(
                format: "value CONTAINS %@", "按你说的顺序来"
            )
        ).firstMatch
        XCTAssertTrue(
            text.waitForExistence(timeout: 15),
            "演示末条用户消息文本未出现"
        )
        reveal(text, in: app)
        return text
    }

    /// §265 演示种子 T4 样本消息的文本视图（值班
    /// 电话/状态页/邮箱一条）
    private func contactTextView(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        let text = app.textViews.matching(
            NSPredicate(
                format: "value CONTAINS %@", "值班电话"
            )
        ).firstMatch
        XCTAssertTrue(
            text.waitForExistence(timeout: 15),
            "演示 T4 样本消息文本未出现"
        )
        reveal(text, in: app)
        return text
    }

    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication
    ) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 where !element.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(
            element.isHittable,
            "目标文本滚动后仍不可命中"
        )
    }

    /// 屏幕绝对坐标点（窗口坐标系原点＋点偏移）
    private func windowPoint(
        in app: XCUIApplication, x: CGFloat, y: CGFloat
    ) -> XCUICoordinate {
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(CGVector(dx: x, dy: y))
    }

    // MARK: - 断言助手

    /// 编辑菜单出现的判据：menuItems 或按钮里出
    /// 现 Copy/拷贝（两档语言都认）
    private func assertEditMenuShown(in app: XCUIApplication) {
        let copyItem = app.menuItems.matching(
            NSPredicate(
                format: "label IN %@", ["Copy", "拷贝"]
            )
        ).firstMatch
        let copyButton = app.buttons.matching(
            NSPredicate(
                format: "label IN %@", ["Copy", "拷贝"]
            )
        ).firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              !copyItem.exists, !copyButton.exists {
            Thread.sleep(forTimeInterval: 0.3)
        }
        if !copyItem.exists, !copyButton.exists {
            XCTFail(
                "文本手势后系统编辑菜单未出现；当时按钮树："
                    + treeSnapshot(in: app)
            )
        }
    }

    /// 整行菜单不出现的判据：回复项（SF Symbol
    /// 标识）不存在
    private func assertRowMenuAbsent(in app: XCUIApplication) {
        let item = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                rowMenuReplySymbol
            )
        ).firstMatch
        XCTAssertFalse(
            item.exists,
            "文本区手势不许出整行菜单（S3 仲裁）"
        )
    }

    /// 失败取证：全树按钮的标识/标签紧凑清单
    private func treeSnapshot(in app: XCUIApplication) -> String {
        let buttons = app.buttons.allElementsBoundByIndex.map {
            "\($0.identifier)|\($0.label)"
        }
        return buttons.joined(separator: ", ")
    }
}
