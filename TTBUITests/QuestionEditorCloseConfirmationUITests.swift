import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class QuestionEditorCloseConfirmationUITests: XCTestCase {
    private let firstQuestionCardID = "question-card-home.today-home-question-1"
    private let fullscreenCloseID = "question-card-fullscreen-close"
    private let firstInputID = "question-card-input-0"
    private let savedAnswer = "Ship the onboarding fix"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension QuestionEditorCloseConfirmationUITests {
    func testCloseWithoutChangesClosesAtOnce() {
        let app = launchHomeWithSavedAnswer()
        let card = openFirstQuestion(in: app)

        app.buttons[fullscreenCloseID].tap()

        XCTAssertTrue(waitUntil(timeout: 3) { card.exists && card.isHittable })
        XCTAssertFalse(app.buttons["Close Without Saving"].exists)
    }

    func testCloseWithoutSavingDropsTheDraftAndKeepsTheSavedAnswer() {
        let app = launchHomeWithSavedAnswer()
        let card = openFirstQuestion(in: app)

        let input = firstInput(in: app)
        XCTAssertEqual(input.value as? String, savedAnswer)
        input.tap()
        input.typeText(" today")

        app.buttons[fullscreenCloseID].tap()

        let closeWithoutSaving = app.buttons["Close Without Saving"]
        XCTAssertTrue(closeWithoutSaving.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Save and Close"].exists)
        closeWithoutSaving.tap()

        XCTAssertTrue(waitUntil(timeout: 3) { card.exists && card.isHittable })

        openFirstQuestion(in: app, card: card)
        XCTAssertEqual(firstInput(in: app).value as? String, savedAnswer)
    }

    private func launchHomeWithSavedAnswer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-test-home-harness",
            "-ui-test-home-saved-answer",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()
        return app
    }

    @discardableResult
    private func openFirstQuestion(in app: XCUIApplication, card: XCUIElement? = nil) -> XCUIElement {
        let card = card ?? app.buttons[firstQuestionCardID]
        XCTAssertTrue(waitUntil(timeout: 3) { card.exists && card.isHittable })
        card.tap()
        XCTAssertTrue(app.buttons[fullscreenCloseID].waitForExistence(timeout: 3))
        XCTAssertTrue(firstInput(in: app).waitForExistence(timeout: 3))
        return card
    }

    /// A vertical-axis `TextField` can surface as a text view or a text field, so match either.
    private func firstInput(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[firstInputID].firstMatch
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping () -> Bool
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
