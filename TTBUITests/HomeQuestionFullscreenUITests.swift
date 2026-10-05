import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class HomeQuestionFullscreenUITests: XCTestCase {
    private let harnessArgument = "-ui-test-home-harness"
    private let firstQuestionCardID = "question-card-home.today-home-question-1"
    private let fullscreenCloseID = "question-card-fullscreen-close"
    private let fullscreenSaveID = "question-card-fullscreen-save"
    private let fullscreenShareID = "question-card-fullscreen-share"
    private let fullscreenFavoriteID = "question-card-fullscreen-favorite"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension HomeQuestionFullscreenUITests {
    func testTodayQuestionPresentsAndDismissesFullscreenEditor() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let firstCard = app.buttons[firstQuestionCardID]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForElementToBecomeHittable(firstCard, timeout: 3))

        firstCard.tap()

        XCTAssertTrue(waitForElementToBecomeNotHittable(firstCard, timeout: 2))
        XCTAssertTrue(app.buttons[fullscreenSaveID].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[fullscreenShareID].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[fullscreenFavoriteID].waitForExistence(timeout: 2))
        closeFullscreen(in: app)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
    }

    func testFavoriteButtonTogglesAndFullscreenMatches() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let favoriteButton = app.buttons["question-card-favorite-home.today-home-question-1"]
        XCTAssertTrue(waitForElementToBecomeHittable(favoriteButton, timeout: 3))
        XCTAssertEqual(favoriteButton.label, "Add to favorites")

        favoriteButton.tap()

        XCTAssertTrue(waitUntil(timeout: 2) {
            favoriteButton.exists && favoriteButton.label == "Remove from favorites"
        })
        XCTAssertFalse(app.buttons[fullscreenSaveID].exists)

        let firstCard = app.buttons[firstQuestionCardID]
        XCTAssertTrue(waitForElementToBecomeHittable(firstCard, timeout: 2))
        firstCard.tap()

        let fullscreenFavorite = app.buttons[fullscreenFavoriteID]
        XCTAssertTrue(fullscreenFavorite.waitForExistence(timeout: 2))
        XCTAssertEqual(fullscreenFavorite.label, "Remove from favorites")
        closeFullscreen(in: app)
    }

    private func waitForElementToBecomeHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && element.isHittable
        }
    }

    private func waitForElementToBecomeNotHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && !element.isHittable
        }
    }

    private func closeFullscreen(in app: XCUIApplication) {
        let closeButtonByID = app.buttons[fullscreenCloseID]
        if closeButtonByID.waitForExistence(timeout: 1) {
            closeButtonByID.tap()
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
