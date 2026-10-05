import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class AITrioComposerUITests: XCTestCase {
    private let harnessArgument = "-ui-test-ai-harness"
    private let anonymousArgument = "-ui-test-ai-anonymous"
    private let dailyLimitArgument = "-ui-test-ai-at-daily-limit"
    private let seedDraftArgument = "-ui-test-ai-seed-draft"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension AITrioComposerUITests {
    func testTrioComposer_generateVariationAndPublish() {
        let app = launchHarness(extraArguments: [seedDraftArgument])

        openCreateSheet(in: app)

        let publishButton = app.buttons["trio-publish-button"]
        XCTAssertTrue(waitForPublishReady(publishButton, in: app, timeout: 12))
        publishButton.tap()

        let success = app.descendants(matching: .any)["trio-publish-success-toast"].firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                success.exists
                    && app.descendants(matching: .any)["trio-create-question-sheet"].firstMatch.exists
            }
                || success.waitForExistence(timeout: 2)
                || app.staticTexts["Submitted for review"].waitForExistence(timeout: 2)
        )
    }

    func testTrioComposer_generateButtonShowsQuestionSuggestions() {
        let app = launchHarness()

        openCreateSheet(in: app)
        fillQuestion(in: app, text: "Travel memories")

        let generateButton = app.buttons["trio-generate-ideas-button"]
        XCTAssertTrue(waitForElementToBecomeHittable(generateButton, timeout: 5))
        generateButton.tap()

        let firstSuggestion = app.buttons["trio-suggestion-0"]
        XCTAssertTrue(firstSuggestion.waitForExistence(timeout: 8))
        XCTAssertTrue(firstSuggestion.label.contains("top 3 travel memories"))
    }

    func testTrioComposer_anonymousPublishOpensUpgrade() {
        let app = launchHarness(extraArguments: [anonymousArgument, seedDraftArgument])

        let createButton = app.buttons["trio-create-question-button"]
        XCTAssertTrue(waitForElementToBecomeHittable(createButton, timeout: 5))
        createButton.tap()

        let upgradeSheet = app.descendants(matching: .any)["guest-upgrade-sheet"].firstMatch
        XCTAssertTrue(
            upgradeSheet.waitForExistence(timeout: 5)
                || app.staticTexts["Save Your Progress"].waitForExistence(timeout: 3)
        )
    }

    func testTrioComposer_dailyLimitDisablesVariationsWand() {
        let app = launchHarness(extraArguments: [dailyLimitArgument])

        openCreateSheet(in: app)
        fillQuestion(in: app, text: "Travel memories")

        let generateButton = app.buttons["trio-generate-ideas-button"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                generateButton.exists && !generateButton.isEnabled
            }
        )
    }

    private func launchHarness(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ] + extraArguments
        app.launch()
        return app
    }

    private func openCreateSheet(in app: XCUIApplication) {
        let createButton = app.buttons["trio-create-question-button"]
        XCTAssertTrue(waitForElementToBecomeHittable(createButton, timeout: 5))
        createButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trio-create-question-sheet"].firstMatch.waitForExistence(timeout: 5))
    }

    private func fillQuestion(in app: XCUIApplication, text: String) {
        let questionField = app.descendants(matching: .any)["trio-draft-field"].firstMatch
        XCTAssertTrue(questionField.waitForExistence(timeout: 3))
        questionField.tap()
        questionField.typeText(text)
    }

    private func waitForPublishReady(
        _ publishButton: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            let publishValue = publishButton.value as? String ?? ""
            let isReady = publishValue == "ready" || publishButton.isEnabled
            return publishButton.exists && isReady && publishButton.isHittable
        }
    }

    private func waitForElementToBecomeHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && element.isHittable
        }
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
