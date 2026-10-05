import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class HomeProfileQuestionListSheetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension HomeProfileQuestionListSheetUITests {
    func testShareListSheetStaysPresentedWhenProfileIsOpenedFromHome() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-test-home-profile-question-list-harness",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let profileButton = app.buttons["Profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { profileButton.isHittable })
        profileButton.tap()

        let questionListsRow = app.staticTexts["Question Lists"]
        XCTAssertTrue(questionListsRow.waitForExistence(timeout: 5))
        questionListsRow.tap()

        let ownedList = app.descendants(matching: .any)["question-list-row-ui-test-home-profile-list"]
        XCTAssertTrue(ownedList.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { ownedList.isHittable })
        ownedList.tap()

        let shareButton = app.buttons["question-list-detail-share-button"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { shareButton.isHittable && shareButton.isEnabled })
        shareButton.tap()

        let shareSheet = app.descendants(matching: .any)["question-list-share-sheet"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Include my text answers"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["question-list-share-dismiss-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["question-list-share-toolbar-share-button"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Create Share Link"].exists)

        RunLoop.current.run(until: Date().addingTimeInterval(1.75))

        XCTAssertTrue(shareSheet.exists)
        XCTAssertTrue(app.switches["Include my text answers"].exists)
        XCTAssertTrue(app.buttons["question-list-share-dismiss-button"].exists)
        XCTAssertTrue(app.buttons["question-list-share-toolbar-share-button"].exists)
        XCTAssertFalse(app.buttons["Create Share Link"].exists)

        let dismissButton = app.buttons["question-list-share-dismiss-button"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 2))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        dismissButton.tap()

        let addButton = app.buttons["question-list-detail-add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { addButton.isHittable && addButton.isEnabled })
        addButton.tap()

        let pickerSheet = app.descendants(matching: .any)["question-list-picker-sheet"]
        XCTAssertTrue(pickerSheet.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(1.75))

        XCTAssertTrue(pickerSheet.exists)
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
