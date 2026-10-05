import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class SharedQuestionListHubUITests: XCTestCase {
    private let harnessArgument = "-ui-test-question-list-detail-share-harness"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension SharedQuestionListHubUITests {
    func testTappingAwaitingSentShareOpensSharedListDetailWithoutInlineManagement() {
        let app = launchHarness()
        openSharedSegment(in: app)

        let sentRow = app.descendants(matching: .any)["shared-list-sent-row-ui-test-share"]
        XCTAssertTrue(sentRow.waitForExistence(timeout: 5))
        sentRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["owned-shared-list-detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Which conversation would you like to continue this week?"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["sent-share-manage-link-button"].exists)
        XCTAssertFalse(app.staticTexts["Waiting for Recipients"].exists)
    }

    func testTappingAcceptedSentShareOpensComparisonDetail() {
        let app = launchHarness()
        openSharedSegment(in: app)

        let sentRow = app.descendants(matching: .any)["shared-list-sent-row-ui-test-compare-share"]
        XCTAssertTrue(sentRow.waitForExistence(timeout: 5))
        sentRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["owned-shared-list-detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Which conversation would you like to continue this week?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["@Compare Friend"].waitForExistence(timeout: 2))
    }

    private func launchHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()
        return app
    }

    private func openSharedSegment(in app: XCUIApplication) {
        let sharedSegment = app.buttons["Shared"]
        XCTAssertTrue(sharedSegment.waitForExistence(timeout: 5))
        sharedSegment.tap()
        XCTAssertTrue(app.descendants(matching: .any)["question-list-shares-hub"].waitForExistence(timeout: 5))
    }
}
