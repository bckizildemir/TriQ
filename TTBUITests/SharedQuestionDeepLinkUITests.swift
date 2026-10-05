import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class SharedQuestionDeepLinkUITests: XCTestCase {
    private let harnessArgument = "-ui-test-shared-question-harness"
    private let fullscreenRootID = "question-card-fullscreen-root"
    private let fullscreenSaveID = "question-card-fullscreen-save"
    private let fullscreenShareID = "question-card-fullscreen-share"
    private let fullscreenFavoriteID = "question-card-fullscreen-favorite"
    private let fullscreenListID = "question-card-fullscreen-list"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension SharedQuestionDeepLinkUITests {
    func testSharedQuestionSheetPresentsExpandedQuestionWithoutMissingEnvironmentObjects() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)[fullscreenRootID].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[fullscreenSaveID].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[fullscreenShareID].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[fullscreenFavoriteID].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[fullscreenListID].waitForExistence(timeout: 2))
    }
}
