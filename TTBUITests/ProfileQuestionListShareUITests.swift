import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class ProfileQuestionListShareUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension ProfileQuestionListShareUITests {
    func testShareListSheetStaysPresentedFromProfileQuestionListDetail() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-test-profile-harness",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let questionListsRow = app.staticTexts["Question Lists"]
        XCTAssertTrue(questionListsRow.waitForExistence(timeout: 5))
        questionListsRow.tap()

        let ownedList = app.descendants(matching: .any)["question-list-row-ui-test-profile-list"]
        XCTAssertTrue(ownedList.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { ownedList.isHittable })
        ownedList.tap()

        let shareButton = app.buttons["question-list-detail-share-button"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { shareButton.isHittable })
        shareButton.tap()

        let shareSheet = app.descendants(matching: .any)["question-list-share-sheet"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Include my text answers"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["question-list-share-dismiss-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["question-list-share-toolbar-share-button"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Create Share Link"].exists)

        RunLoop.current.run(until: Date().addingTimeInterval(1.25))

        XCTAssertTrue(shareSheet.exists)
        XCTAssertTrue(app.switches["Include my text answers"].exists)
        XCTAssertTrue(app.buttons["question-list-share-dismiss-button"].exists)
        XCTAssertTrue(app.buttons["question-list-share-toolbar-share-button"].exists)
        XCTAssertFalse(app.buttons["Create Share Link"].exists)
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
