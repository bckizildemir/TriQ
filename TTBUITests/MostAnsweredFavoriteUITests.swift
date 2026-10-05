import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class MostAnsweredFavoriteUITests: XCTestCase {
    private let harnessArgument = "-ui-test-most-answered-harness"
    private let firstQuestionCardID = "question-card-mostAnswered-preview-most-answered-1"
    private let firstQuestionFavoriteID = "question-card-favorite-mostAnswered-preview-most-answered-1"
    private let fullscreenFavoriteID = "question-card-fullscreen-favorite"
    private let fullscreenSaveID = "question-card-fullscreen-save"
    private let fullscreenCloseID = "question-card-fullscreen-close"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension MostAnsweredFavoriteUITests {
    func testFavoriteButtonTogglesWithoutOpeningCard() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let favoriteButton = app.buttons[firstQuestionFavoriteID]
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
