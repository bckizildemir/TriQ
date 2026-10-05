import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class QuestionListDetailShareUITests: XCTestCase {
    private let harnessArgument = "-ui-test-question-list-detail-share-harness"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension QuestionListDetailShareUITests {
    func testShareListSheetStaysPresentedFromDetailToolbar() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let listRow = app.staticTexts["Owned Fixture"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        listRow.tap()

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

        RunLoop.current.run(until: Date().addingTimeInterval(1))

        XCTAssertTrue(shareSheet.exists)
        XCTAssertTrue(app.switches["Include my text answers"].exists)
        XCTAssertTrue(app.buttons["question-list-share-dismiss-button"].exists)
        XCTAssertTrue(app.buttons["question-list-share-toolbar-share-button"].exists)
        XCTAssertFalse(app.buttons["Create Share Link"].exists)
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
