import XCTest

/// Covers the guest favorite milestone toast that replaced the inline reminder card.
///
/// The milestone is encouragement, not the upgrade prompt — `CONTEXT.md` is explicit that it
/// "asks nothing of the user" — so the toast has no tap target. That is asserted directly rather
/// than assumed, because the toast used to open the upgrade sheet and a regression here would be
/// silent otherwise.
// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class GuestFavoriteMilestoneUITests: XCTestCase {
    private let harnessArgument = "-ui-test-guest-favorite-milestone-harness"
    private let firstFavoriteID = "question-card-favorite-category.Career-career-question-1"
    private let secondFavoriteID = "question-card-favorite-category.Career-career-question-2"
    private let thirdFavoriteID = "question-card-favorite-category.Career-career-question-3"
    private let milestoneToastID = "guest-favorite-milestone-toast"
    private let upgradeSheetID = "guest-upgrade-sheet"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension GuestFavoriteMilestoneUITests {
    func testMilestoneToastAppearsOnThirdFavoriteAndAsksNothingOfTheUser() {
        let app = launchApp()

        let toast = app.descendants(matching: .any)[milestoneToastID]

        favorite(firstFavoriteID, in: app)
        XCTAssertFalse(toast.exists, "Toast must not appear on the first favorite")

        favorite(secondFavoriteID, in: app)
        XCTAssertFalse(toast.exists, "Toast must not appear on the second favorite")

        favorite(thirdFavoriteID, in: app)
        XCTAssertTrue(
            toast.waitForExistence(timeout: 3),
            "Milestone toast should appear on the third favorite"
        )

        toast.tap()

        XCTAssertFalse(
            app.descendants(matching: .any)[upgradeSheetID].waitForExistence(timeout: 1),
            "The milestone is not the upgrade prompt: tapping it must not open anything"
        )
    }

    func testMilestoneToastAutoDismissesWithoutBeingTapped() {
        let app = launchApp()

        favorite(firstFavoriteID, in: app)
        favorite(secondFavoriteID, in: app)
        favorite(thirdFavoriteID, in: app)

        let toast = app.descendants(matching: .any)[milestoneToastID]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))

        XCTAssertTrue(
            waitUntil(timeout: 12) { !toast.exists },
            "Toast should auto-dismiss on its own so ignoring it costs nothing"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[upgradeSheetID].exists,
            "Letting the toast expire must never present the upgrade sheet"
        )
    }

    // MARK: - Helpers

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()
        return app
    }

    private func favorite(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(
            scrollUntilHittable(button, in: app),
            "Favorite button \(identifier) should be reachable"
        )
        button.tap()
        XCTAssertTrue(
            waitUntil(timeout: 2) { button.label == "Remove from favorites" },
            "Favorite button \(identifier) should confirm the guest favorite before continuing"
        )
    }

    /// Question cards are tall enough that only about two fit on an iPhone-sized screen,
    /// so the third one has to be scrolled into view before it can be tapped.
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) -> Bool {
        if waitForElementToBecomeHittable(element, timeout: 2) {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if waitForElementToBecomeHittable(element, timeout: 1) {
                return true
            }
        }

        return false
    }

    private func waitForElementToBecomeHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) { element.exists && element.isHittable }
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
