import XCTest

/// A tap outside the answer fields on the question detail screen must close the keyboard. The
/// screen only closed it on a scroll drag, so a tap on the question title left it open.
final class QuestionDetailKeyboardDismissUITests: XCTestCase {
    private let harnessArgument = "-ui-test-home-harness"
    private let firstQuestionCardID = "question-card-home.today-home-question-1"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTapOutsideAnswerFieldDismissesKeyboard() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let card = app.buttons[firstQuestionCardID]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        let input = answerInput(at: 0, in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        // A tap on another answer field moves focus there and keeps the keyboard up.
        let secondInput = answerInput(at: 1, in: app)
        secondInput.tap()
        secondInput.typeText("Sleep")
        XCTAssertEqual(secondInput.value as? String, "Sleep")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        // The question title sits above the first answer slot and is plain text, not a control.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -50))
            .tap()

        XCTAssertTrue(waitUntil(timeout: 3) { !app.keyboards.firstMatch.exists })
    }

    /// A vertical-axis `TextField` reports as a text view; fall back to a text field.
    private func answerInput(at index: Int, in app: XCUIApplication) -> XCUIElement {
        let identifier = "question-card-input-\(index)"
        return app.textViews[identifier].waitForExistence(timeout: 5)
            ? app.textViews[identifier]
            : app.textFields[identifier]
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
