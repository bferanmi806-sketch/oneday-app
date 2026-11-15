import UIKit
import XCTest

/// §293（原生重建 R3）包 5 手势五件在新承载
/// （UICollectionView 原生面）的对位复验：第
/// 95 条收口指定——旧承载（gen3）上 UI 绿证未
/// 达成的五件在本面以真实装配＋UI 证明复验。
/// 与 ChatGestureArbitrationTests（gen3 面基
/// 线）同题同判据、另立一册：启动参数加
/// `-chat.list.native YES`（@AppStorage 读
/// standard defaults、参数域在席即开原生面，
/// 产品码零改动）；列表元素改集合视图口径。
/// finder 沿基线的值匹配＋reveal 路（第 95 条
/// 的帧落定机器按收口口径不迁移、不重建）。
/// 五件：
/// 1. 长按正文→系统编辑菜单、整行菜单不出现；
/// 2. 长按气泡边距带→整行菜单（原生 cell 的
///    UIContextMenuInteraction＋点位否决）；
/// 3. 双击正文→选词＋编辑菜单；
/// 4. 右滑一行→引用横幅（桥辖区帧＝cell 帧）；
/// 5. 电话（T4）：长按号码由文本选择接管（平
///    台定性）或点按出系统链接动作——任一达即
///    主动作已证；本面联系方式消息是助手原生
///    散文 cell，finder 须命中真实 UITextView。
final class ChatGestureNativeSurfaceTests: XCTestCase {

    private let rowMenuReplySymbol =
        "arrowshape.turn.up.left"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 用例

    func testLongPressOnTextShowsEditMenuNotRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        let text = try lastUserTextView(in: app)
        text.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).press(forDuration: 1.2)
        assertEditMenuShown(in: app)
        assertRowMenuAbsent(in: app)
    }

    func testLongPressOnBubblePaddingShowsRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 与基线同梯：四点逐个试、逐个记结果，任
        // 一出整行菜单即收（点位全走元素坐标系）
        let attempts: [(
            name: String, base: CGVector,
            offset: CGVector, duration: TimeInterval
        )] = [
            ("左带", CGVector(dx: 0, dy: 0.5),
             CGVector(dx: -8, dy: 0), 1.5),
            ("上带", CGVector(dx: 0.5, dy: 0),
             CGVector(dx: 0, dy: -6), 1.5),
            ("左带长压", CGVector(dx: 0, dy: 0.5),
             CGVector(dx: -8, dy: 0), 2.5),
            ("右带", CGVector(dx: 1, dy: 0.5),
             CGVector(dx: 8, dy: 0), 1.5),
        ]
        var evidence: [String] = []
        for attempt in attempts {
            let text = try lastUserTextView(in: app)
            let point = text.coordinate(
                withNormalizedOffset: attempt.base
            ).withOffset(attempt.offset)
            point.press(forDuration: attempt.duration)
            if pollRowMenu(in: app, timeout: 5) {
                print(
                    "TEST-PADDING point=\(attempt.name)"
                        + " result=rowMenu"
                )
                let item = app.buttons.matching(
                    NSPredicate(
                        format: "identifier == %@",
                        rowMenuReplySymbol
                    )
                ).firstMatch
                XCTAssertTrue(item.isHittable)
                return
            }
            let result = editMenuVisible(in: app)
                ? "editMenu" : "none"
            print(
                "TEST-PADDING point=\(attempt.name)"
                    + " result=\(result)"
            )
            evidence.append("\(attempt.name)=\(result)")
            dismissMenus(in: app)
        }
        XCTFail(
            "气泡边距带四点均未出整行菜单；逐点结果："
                + evidence.joined(separator: ", ")
                + "；当时按钮树：" + treeSnapshot(in: app)
        )
    }

    func testDoubleTapOnTextSelectsWordNotRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        let text = try lastUserTextView(in: app)
        text.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).doubleTap()
        assertEditMenuShown(in: app)
        assertRowMenuAbsent(in: app)
    }

    func testSwipeRightOnRowTriggersReplyQuote() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 与基线同法：慢速拖＋终点保持；先边距带
        // 起拖、不成再文本左缘内起拖
        let starts: [(name: String, offsetX: CGFloat)] = [
            ("边距带起拖", -8),
            ("文本区起拖", 12),
        ]
        for start in starts {
            let text = try lastUserTextView(in: app)
            let begin = text.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0.5)
            ).withOffset(CGVector(dx: start.offsetX, dy: 0))
            let end = begin.withOffset(
                CGVector(dx: 170, dy: 0)
            )
            begin.press(
                forDuration: 0.1, thenDragTo: end,
                withVelocity: .slow,
                thenHoldForDuration: 1.0
            )
            let cancel = app.buttons["取消引用"]
            let found = cancel.waitForExistence(timeout: 6)
            print(
                "TEST-SWIPE attempt=\(start.name)"
                    + " banner=\(found)"
            )
            if found { return }
        }
        XCTFail(
            "两轮慢速右滑均未触发引用横幅；当时按钮树："
                + treeSnapshot(in: app)
        )
    }

    func testLongPressOnPhoneShowsLinkMenuNotRowMenu() throws {
        let app = launchDemoApp()
        openSeededThread(in: app)
        // 阶段一：长按号码正中（点位由实帧＋字宽
        // 测算钉死）——出 Call 项链接菜单即收
        let point = try phoneNumberCoordinate(in: app)
        point.press(forDuration: 1.5)
        if waitForCallItem(in: app, timeout: 6) {
            print("TEST-PHONE proof=longpress-linkmenu")
            assertRowMenuAbsent(in: app)
            return
        }
        print(
            "TEST-PHONE 长按号码正中未出链接菜单；"
                + "当时菜单项="
                + menuLabels(in: app).joined(separator: "/")
                + "；按钮树：" + treeSnapshot(in: app)
        )
        // 平台定性（基线第十轮·主线裁示）：可选
        // 文本视图里长按由文本选择接管、检测链接
        // 主动作是点按——改走点按证明：清选区后
        // 点按号码正中，系统链接动作任一形态出现
        // 即算主动作已达
        dismissMenus(in: app)
        clearSelectionByTappingPlainText(in: app)
        for tapIndex in 0..<2 {
            let tapPoint = try phoneNumberCoordinate(
                in: app
            )
            tapPoint.tap()
            if waitForLinkAction(in: app, timeout: 5) {
                print(
                    "TEST-PHONE proof=tap-linkaction"
                        + " tapIndex=\(tapIndex)"
                )
                return
            }
        }
        XCTFail(
            "长按（只出编辑菜单）与点按均未见链接动作；"
                + "点按后按钮树：" + treeSnapshot(in: app)
        )
    }

    // MARK: - 装配与查找

    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-odDemoMode", "-chat.list.native", "YES",
        ]
        app.launch()
        return app
    }

    /// 原生面在场的硬证据：聊天列表是集合视图
    /// （gen3/旧面为滚动视图口径）——五件全在本
    /// 断言之后跑，面不对整册无意义
    private func assertNativeSurface(in app: XCUIApplication) {
        XCTAssertTrue(
            app.collectionViews.firstMatch
                .waitForExistence(timeout: 15),
            "原生面未在场：集合视图不存在（旗未生效？）"
        )
    }

    /// 打开演示种子会话（与基线同路：抽屉本地
    /// 行点开种子会话；列表滚动口径换集合视图）
    private func openSeededThread(in app: XCUIApplication) {
        assertNativeSurface(in: app)
        let openButton = app.buttons["drawer.open"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 15),
            "抽屉入口未出现"
        )
        if openButton.isHittable {
            openButton.tap()
        }
        let rows = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "drawer.row.side.local."
            )
        )
        var target: XCUIElement?
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, target == nil {
            for row in rows.allElementsBoundByIndex
            where row.label.contains("服务器状态") {
                target = row
                break
            }
            if target == nil {
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        guard let target else {
            XCTFail("抽屉里找不到演示种子会话行")
            return
        }
        if !target.isHittable {
            // 抽屉开态内容层退出无障碍树（容器既定
            // 行为）——集合视图此时不在树内，滑动走
            // app 级（命中的是抽屉自己的滚动面）；
            // 第一轮 CI 五件全卡于此、先修此一处
            app.swipeUp()
        }
        target.tap()
        _ = app.buttons["topbar.modelCapsule"]
            .waitForExistence(timeout: 10)
        // 跳到底部：走生产「回到底部」钮，无钮时
        // 以列表上滑兜底；落底后末条消息物化在屏内
        let toBottom = app.buttons["chevron.down"]
        if toBottom.waitForExistence(timeout: 3),
           toBottom.isHittable {
            toBottom.tap()
        } else {
            // 抽屉刚关、内容层回树有动画时差——走
            // app 级滑动不赌集合视图在树时刻
            for _ in 0..<6 {
                app.swipeUp()
            }
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func lastUserTextView(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        try textView(matching: "按你说的顺序来", in: app)
    }

    private func contactTextView(
        in app: XCUIApplication
    ) throws -> XCUIElement {
        try textView(matching: "值班电话", in: app)
    }

    /// 按正文找承载文本视图（基线同法：a11y
    /// value 经整形插有 U+2060、谓词 CONTAINS
    /// 必落空——逐元素读 value 剥整形字符后比
    /// 对；找不到时上滑促物化后重找）
    private func textView(
        matching needle: String, in app: XCUIApplication
    ) throws -> XCUIElement {
        _ = app.buttons["topbar.modelCapsule"]
            .waitForExistence(timeout: 30)
        for round in 0..<2 {
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                for element in candidateElements(in: app) {
                    let raw = (element.value as? String)
                        ?? element.label
                    guard !raw.isEmpty else { continue }
                    let stripped = raw
                        .replacingOccurrences(
                            of: "\u{2060}", with: ""
                        )
                        .replacingOccurrences(
                            of: "\u{200B}", with: ""
                        )
                        .replacingOccurrences(
                            of: "\u{FEFF}", with: ""
                        )
                    if stripped.contains(needle) {
                        print(
                            "TEST-FINDER matched needle="
                                + needle
                                + " type=\(element.elementType.rawValue)"
                                + " frame=\(element.frame)"
                        )
                        reveal(element, in: app)
                        return element
                    }
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
            if round == 0 { app.swipeUp() }
        }
        XCTFail(
            "按正文找不到承载文本视图「\(needle)」；"
                + "当时文本视图 value 摘要："
                + valueDigest(in: app)
        )
        throw NSError(
            domain: "ChatGestureNativeSurface", code: 1
        )
    }

    private func candidateElements(
        in app: XCUIApplication
    ) -> [XCUIElement] {
        app.textViews.allElementsBoundByIndex
            + app.staticTexts.allElementsBoundByIndex
    }

    private func valueDigest(in app: XCUIApplication) -> String {
        candidateElements(in: app).map {
            let raw = ($0.value as? String) ?? $0.label
            let stripped = raw.replacingOccurrences(
                of: "\u{2060}", with: ""
            )
            return "t\($0.elementType.rawValue):"
                + String(stripped.prefix(30))
        }.joined(separator: " | ")
    }

    /// 双向 reveal（基线同法：帧退化/在上方下滑
    /// 找、在下方上滑找；列表口径换集合视图）
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication
    ) {
        let list = app.collectionViews.firstMatch
        var attempts = 0
        while !element.isHittable, attempts < 14 {
            let frame = element.frame
            if frame.isEmpty || !frame.minY.isFinite
                || frame.minY < 130 {
                list.swipeDown()
            } else {
                list.swipeUp()
            }
            attempts += 1
        }
        XCTAssertTrue(
            element.isHittable,
            "目标文本滚动后仍不可命中"
        )
    }

    // MARK: - 断言助手（与基线同判据）

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

    private func pollRowMenu(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        // 原生 UIMenu 的菜单项以标题为标签在树；
        // SF Symbol 标识与标题两口径任一命中即认
        // （基线 SwiftUI 菜单以 symbol 标识在树）
        let bySymbol = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                rowMenuReplySymbol
            )
        ).firstMatch
        let byLabel = app.buttons.matching(
            NSPredicate(format: "label == %@", "回复")
        ).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if bySymbol.exists || byLabel.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return bySymbol.exists || byLabel.exists
    }

    private func editMenuVisible(
        in app: XCUIApplication
    ) -> Bool {
        app.menuItems.matching(
            NSPredicate(
                format: "label IN %@", ["Copy", "拷贝"]
            )
        ).firstMatch.exists
            || app.buttons.matching(
                NSPredicate(
                    format: "label IN %@", ["Copy", "拷贝"]
                )
            ).firstMatch.exists
    }

    private func menuLabels(
        in app: XCUIApplication
    ) -> [String] {
        app.menuItems.allElementsBoundByIndex
            .map { $0.label }.filter { !$0.isEmpty }
    }

    private func dismissMenus(in app: XCUIApplication) {
        let rowItem = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                rowMenuReplySymbol
            )
        ).firstMatch
        if rowItem.exists || editMenuVisible(in: app) {
            app.collectionViews.firstMatch.swipeDown()
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    private func waitForCallItem(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        let item = app.menuItems.matching(
            NSPredicate(
                format: "label IN %@", ["Call", "呼叫"]
            )
        ).firstMatch
        let button = app.buttons.matching(
            NSPredicate(
                format: "label IN %@", ["Call", "呼叫"]
            )
        ).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if item.exists || button.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return item.exists || button.exists
    }

    private func waitForLinkAction(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if app.sheets.firstMatch.exists {
                print("TEST-PHONE linkAction=sheet")
                return true
            }
            if app.alerts.firstMatch.exists {
                print("TEST-PHONE linkAction=alert")
                return true
            }
            if app.buttons.matching(
                NSPredicate(
                    format: "label IN %@",
                    ["Call", "呼叫"]
                )
            ).firstMatch.exists
                || app.menuItems.matching(
                    NSPredicate(
                        format: "label IN %@",
                        ["Call", "呼叫"]
                    )
                ).firstMatch.exists {
                print("TEST-PHONE linkAction=callItem")
                return true
            }
            if app.buttons.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "13800138000"
                )
            ).firstMatch.exists {
                print("TEST-PHONE linkAction=numberButton")
                return true
            }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// 联系方式消息的点位几何：帧在 reveal 后重
    /// 读；呈现字体走现行正文单源 .body（§263
    /// 后用户/助手同档——基线文件里的 .callout
    /// 是升档前口径、本册按现行口径测算）；号码
    /// 中心＝前缀宽＋号码宽一半、纵取首行行心
    private func contactGeometry(
        in app: XCUIApplication
    ) throws -> (
        element: XCUIElement, frame: CGRect,
        prefixWidth: CGFloat, numberWidth: CGFloat,
        lineHeight: CGFloat
    ) {
        let text = try contactTextView(in: app)
        let frame = text.frame
        let font = UIFont.preferredFont(
            forTextStyle: .body
        )
        let prefixWidth = ("值班电话 " as NSString)
            .size(withAttributes: [.font: font]).width
        let numberWidth = ("13800138000" as NSString)
            .size(withAttributes: [.font: font]).width
        print(
            "TEST-PHONE frame=\(frame)"
                + " prefixW=\(prefixWidth)"
                + " numberW=\(numberWidth)"
                + " lineH=\(font.lineHeight)"
        )
        return (
            text, frame, prefixWidth, numberWidth,
            font.lineHeight
        )
    }

    private func phoneNumberCoordinate(
        in app: XCUIApplication
    ) throws -> XCUICoordinate {
        let g = try contactGeometry(in: app)
        guard g.frame.width > 10, g.frame.height > 5
        else {
            print("TEST-PHONE 帧退化、回落经验点位")
            return g.element.coordinate(
                withNormalizedOffset:
                    CGVector(dx: 0.32, dy: 0.30)
            )
        }
        let dx = (g.prefixWidth + g.numberWidth / 2)
            / g.frame.width
        let dy = (g.lineHeight / 2) / g.frame.height
        print(
            "TEST-PHONE numberCenter dx=\(dx) dy=\(dy)"
        )
        return g.element.coordinate(
            withNormalizedOffset: CGVector(dx: dx, dy: dy)
        )
    }

    private func clearSelectionByTappingPlainText(
        in app: XCUIApplication
    ) {
        guard let g = try? contactGeometry(in: app),
              g.frame.width > 10, g.frame.height > 5
        else { return }
        let dx = (g.prefixWidth / 2) / g.frame.width
        let dy = (g.lineHeight / 2) / g.frame.height
        g.element.coordinate(
            withNormalizedOffset: CGVector(dx: dx, dy: dy)
        ).tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func treeSnapshot(in app: XCUIApplication) -> String {
        let buttons = app.buttons.allElementsBoundByIndex.map {
            "\($0.identifier)|\($0.label)"
        }
        return buttons.joined(separator: ", ")
    }
}
