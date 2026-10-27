import XCTest

/// Issue #2. Every screen that offers the guest upgrade asks the app root to present it, so each
/// entry point must end on the one `guest-upgrade-sheet`, including the two that sit under a
/// `fullScreenCover` or a push: the expanded card and the Favorites screen.
// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class GuestUpgradeEntryPointsUITests: XCTestCase {
    private let upgradeSheetID = "guest-upgrade-sheet"
    private let firstCardID = "question-card-category.Career-career-question-1"
    private let expandedRootID = "question-card-fullscreen-root"
    private let stripCTAID = "guest-favorite-strip-cta"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension GuestUpgradeEntryPointsUITests {
    /// The Favorites screen is pushed inside Profile, so its strip button used to present locally.
    func testFavoritesStripButtonOpensTheGuestUpgradeSheet() {
        let app = launch(arguments: [
            "-ui-test-profile-anonymous-harness",
            "-ui-test-guest-favorite-profile-question"
        ])

        let favoritesRow = app.buttons["Favorites"]
        XCTAssertTrue(scrollUntilHittable(favoritesRow, in: app), "Profile should offer Favorites")
        favoritesRow.tap()

        let stripButton = app.buttons[stripCTAID]
        XCTAssertTrue(
            scrollUntilHittable(stripButton, in: app),
            "A guest with a saved favorite should see the upgrade strip"
        )
        stripButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[upgradeSheetID].waitForExistence(timeout: 5),
            "The strip button should open the guest upgrade sheet"
        )
    }

    /// The expanded card is a `fullScreenCover`; its guest banner button used to own a local sheet.
    func testExpandedCardGuestBannerButtonOpensTheGuestUpgradeSheet() {
        let app = launch(arguments: ["-ui-test-guest-favorite-milestone-harness"])

        let card = app.buttons[firstCardID]
        XCTAssertTrue(scrollUntilHittable(card, in: app), "The first card should be reachable")
        card.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[expandedRootID].waitForExistence(timeout: 5),
            "Tapping the card should open the expanded card"
        )

        let createAccount = app.buttons["Create Free Account"]
        XCTAssertTrue(
            scrollUntilHittable(createAccount, in: app),
            "A guest should see the upgrade button in the expanded card"
        )
        createAccount.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[upgradeSheetID].waitForExistence(timeout: 5),
            "The expanded card's button should open the guest upgrade sheet over the card"
        )
    }

    // MARK: - Helpers

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments + [
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()
        return app
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) -> Bool {
        if waitUntil(timeout: 5, condition: { element.exists && element.isHittable }) {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if waitUntil(timeout: 1, condition: { element.exists && element.isHittable }) {
                return true
            }
        }

        return false
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
