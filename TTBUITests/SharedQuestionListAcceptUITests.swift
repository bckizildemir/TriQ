import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class SharedQuestionListAcceptUITests: XCTestCase {
    private let harnessArgument = "-ui-test-shared-question-list-harness"
    private let mainTabHarnessArgument = "-ui-test-shared-question-list-main-tab-harness"
    private let resetHarnessArgument = "-ui-test-reset-shared-question-list-harness"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension SharedQuestionListAcceptUITests {
    func testAcceptSharedQuestionListShowsAcceptedDetail() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            resetHarnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let acceptButton = app.buttons["shared-list-accept-button"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { acceptButton.isHittable && acceptButton.isEnabled })
        acceptButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["accepted-shared-list-detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Which conversation would you like to continue this week?"].waitForExistence(timeout: 2))
    }

    func testAcceptedSharedQuestionListActionsRequireConfirmation() {
        let app = XCUIApplication()
        launch(app, reset: true)

        let acceptButton = app.buttons["shared-list-accept-button"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { acceptButton.isHittable && acceptButton.isEnabled })
        acceptButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["accepted-shared-list-detail"].waitForExistence(timeout: 5))

        let sendButton = app.buttons["shared-list-send-answers-button"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()
        XCTAssertTrue(app.staticTexts["Send answers?"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()

        let removeButton = app.buttons["Remove Shared List"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5))
        removeButton.tap()
        XCTAssertTrue(app.staticTexts["Remove shared list?"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()
    }

    func testAcceptedSharedQuestionListHidesTabBarInMainTabFlow() {
        let app = XCUIApplication()
        launch(app, argument: mainTabHarnessArgument, reset: true)

        let acceptButton = app.buttons["shared-list-accept-button"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { acceptButton.isHittable && acceptButton.isEnabled })
        acceptButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["accepted-shared-list-detail"].waitForExistence(timeout: 5))

        let sendButton = app.buttons["shared-list-send-answers-button"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { sendButton.isHittable })
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    func testAcceptedSharedQuestionListPersistsAfterRelaunch() {
        let app = XCUIApplication()
        launch(app, reset: true)

        let acceptButton = app.buttons["shared-list-accept-button"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { acceptButton.isHittable && acceptButton.isEnabled })
        acceptButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["accepted-shared-list-detail"].waitForExistence(timeout: 5))

        app.terminate()
        launch(app, reset: false)

        XCTAssertTrue(app.descendants(matching: .any)["accepted-shared-list-detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Which conversation would you like to continue this week?"].waitForExistence(timeout: 2))
    }

    private func launch(_ app: XCUIApplication, reset: Bool) {
        launch(app, argument: harnessArgument, reset: reset)
    }

    private func launch(_ app: XCUIApplication, argument: String, reset: Bool) {
        app.launchArguments = [
            argument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        if reset {
            app.launchArguments.append(resetHarnessArgument)
        }
        app.launch()
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
