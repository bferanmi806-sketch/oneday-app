import XCTest

final class ChatQuotePreviewLayoutTests: XCTestCase {
    func testReplyPreviewStaysAboveComposerInput() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let composer = app.textViews["composerField"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("quote preview layout check")

        let sendButton = app.buttons["发送"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()

        let message = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "quote preview layout check"
                )
            )
            .firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 15))
        message.press(forDuration: 1)

        let replyAction = app.buttons["回复"]
        XCTAssertTrue(replyAction.waitForExistence(timeout: 5))
        replyAction.tap()

        let quotePreview = app.descendants(matching: .any)
            .matching(identifier: "chat.quotePreview")
            .firstMatch
        XCTAssertTrue(quotePreview.waitForExistence(timeout: 5))

        XCTAssertGreaterThan(quotePreview.frame.width, 300)
        XCTAssertLessThanOrEqual(
            quotePreview.frame.maxY,
            composer.frame.minY + 1,
            "The reply preview must stay above the composer text field."
        )
    }
}
