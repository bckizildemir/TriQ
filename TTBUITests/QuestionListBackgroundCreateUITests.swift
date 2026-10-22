import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class QuestionListBackgroundCreateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension QuestionListBackgroundCreateUITests {
    /// The profile harness with a list service whose create always fails (#72). Animations stay on,
    /// because the sheet closing while the toast appears is the hand-off under test.
    func testFailedCreateLeavesNotSavedRowWithRetryAndDeleteAndShowsToast() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-test-profile-harness",
            "-ui-test-failing-list-create",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let questionListsRow = app.staticTexts["Question Lists"]
        XCTAssertTrue(questionListsRow.waitForExistence(timeout: 5))
        questionListsRow.tap()

        let createButton = app.toolbars.buttons["Create"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let nameField = app.textFields["List name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Weekend")
        app.navigationBars.buttons["Create"].tap()

        // The sheet closes at once and the failure shows as a toast, with no alert.
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 5))
        let toast = app.descendants(matching: .any)["question-list-create-error-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)

        let row = element(app, idPrefix: "pending-list-row-")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not saved"].exists)

        let retry = element(app, idPrefix: "pending-list-retry-")
        let delete = element(app, idPrefix: "pending-list-delete-")
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(delete.exists)
        XCTAssertTrue(retry.isHittable)
        XCTAssertTrue(delete.isHittable)

        // Retry runs the create again; the fake fails again, so the row comes back as "Not saved".
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))

        delete.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    private func element(_ app: XCUIApplication, idPrefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", idPrefix))
            .firstMatch
    }
}
