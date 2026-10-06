import XCTest

/// Covers the guest funnel from the favorite cap through to a migrated account.
///
/// Both halves lived only on the production app root, so no harness presented them and nothing
/// tested them — the divergence AD-3 exists to remove. The assertions are `CONTEXT.md`'s rules
/// rather than the wiring: reaching the guest favorite cap "prompts an upgrade", and guest
/// favorites "migrate onto the account when the user upgrades".
///
/// The harness launches one favorite below the cap. The cap is ten and the largest fixture holds
/// three questions, so tapping cannot get there and the seed is what makes the scenario expressible.
// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class GuestFavoriteUpgradeFunnelUITests: XCTestCase {
    private let harnessArgument = "-ui-test-guest-favorite-milestone-harness"
    private let seedArgument = "-ui-test-guest-favorites-one-below-cap"
    private let capPromptID = "favorite-limit-sheet"
    private let createAccountID = "favorite-limit-create-account"
    private let maybeLaterID = "favorite-limit-maybe-later"
    private let upgradeSheetID = "guest-upgrade-sheet"
    private let migrationToastID = "guest-favorite-migration-toast"
    private let firstFavoriteID = "question-card-favorite-category.Career-career-question-1"
    private let firstCardID = "question-card-category.Career-career-question-1"
    private let expandedRootID = "question-card-fullscreen-root"
    private let expandedFavoriteID = "question-card-fullscreen-favorite"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension GuestFavoriteUpgradeFunnelUITests {
    func testFavoriteThatReachesTheGuestCapPromptsAnUpgrade() {
        let app = launchApp()
        let capPrompt = app.descendants(matching: .any)[capPromptID]
        let favoriteButton = app.buttons[firstFavoriteID]

        XCTAssertTrue(scrollUntilHittable(favoriteButton, in: app))
        XCTAssertFalse(
            capPrompt.exists,
            "The upgrade prompt must not be presented before the cap is reached"
        )

        favoriteButton.tap()

        XCTAssertTrue(
            capPrompt.waitForExistence(timeout: 5),
            "The favorite that reaches the guest cap should present the upgrade prompt"
        )
    }

    func testUpgradingFromTheCapPromptMigratesTheGuestFavorites() {
        let app = launchApp()
        let favoriteButton = app.buttons[firstFavoriteID]

        XCTAssertTrue(scrollUntilHittable(favoriteButton, in: app))
        favoriteButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[capPromptID].waitForExistence(timeout: 5),
            "The upgrade prompt is the entry point to this funnel"
        )

        tap(app.buttons[createAccountID], in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)[upgradeSheetID].waitForExistence(timeout: 5),
            "Creating an account from the prompt should open the guest upgrade sheet"
        )

        completeUpgradeForm(in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)[migrationToastID].waitForExistence(timeout: 15),
            "Favorites saved as a guest should migrate onto the account the upgrade created"
        )
    }

    // MARK: - From inside the expanded card

    /// Issue #15. The expanded card is a `fullScreenCover`, and a sheet bound at the app root
    /// cannot present over it, so the prompt used to stay hidden here. See `docs/adr/0010`.
    func testFavoriteThatReachesTheGuestCapInsideTheExpandedCardPromptsAnUpgrade() {
        let app = launchApp()
        let capPrompt = app.descendants(matching: .any)[capPromptID]

        openExpandedCard(in: app)
        tap(app.buttons[expandedFavoriteID], in: app)

        XCTAssertTrue(
            capPrompt.waitForExistence(timeout: 5),
            "The favorite that reaches the guest cap should prompt an upgrade over the expanded card too"
        )
    }

    /// The upgrade sheet was root-bound as well, so fixing only the prompt would leave its
    /// "Create Free Account" button doing nothing over the expanded card.
    func testCreatingAnAccountFromThePromptInsideTheExpandedCardOpensTheUpgradeSheet() {
        let app = launchApp()

        openExpandedCard(in: app)
        tap(app.buttons[expandedFavoriteID], in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[capPromptID].waitForExistence(timeout: 5),
            "The upgrade prompt is the entry point to this funnel"
        )

        tap(app.buttons[createAccountID], in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)[upgradeSheetID].waitForExistence(timeout: 5),
            "Creating an account from the prompt should open the guest upgrade sheet over the expanded card"
        )
    }

    /// The prompt no longer dismisses itself — its owner does — so "Maybe Later" closing it is the
    /// owner's work and needs its own check.
    func testMaybeLaterInsideTheExpandedCardClosesThePrompt() {
        let app = launchApp()
        let capPrompt = app.descendants(matching: .any)[capPromptID]

        openExpandedCard(in: app)
        tap(app.buttons[expandedFavoriteID], in: app)
        XCTAssertTrue(capPrompt.waitForExistence(timeout: 5), "The cap should prompt an upgrade")

        tap(app.buttons[maybeLaterID], in: app)

        XCTAssertTrue(
            waitUntil(timeout: 5) { !capPrompt.exists },
            "Maybe Later should close the prompt"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[expandedRootID].exists,
            "Closing the prompt should leave the guest in the expanded card"
        )
    }

    /// A swipe closes the prompt without either button, so nothing but the presenter can lower the
    /// flag. If it stays raised, the next time the guest reaches the cap nothing appears.
    func testPromptSwipedAwayInsideTheExpandedCardAppearsAgainAtTheNextCap() {
        let app = launchApp()
        let capPrompt = app.descendants(matching: .any)[capPromptID]
        let favoriteButton = app.buttons[expandedFavoriteID]

        openExpandedCard(in: app)
        tap(favoriteButton, in: app)
        XCTAssertTrue(capPrompt.waitForExistence(timeout: 5), "The first cap should prompt an upgrade")

        capPrompt.swipeDown(velocity: .fast)
        XCTAssertTrue(
            waitUntil(timeout: 5) { !capPrompt.exists },
            "A swipe down should close the prompt"
        )

        // One tap takes the guest back below the cap, the next reaches it again.
        tap(favoriteButton, in: app)
        tap(favoriteButton, in: app)

        XCTAssertTrue(
            capPrompt.waitForExistence(timeout: 5),
            "Reaching the cap again should prompt an upgrade again after a swipe closed the first one"
        )
    }

    // MARK: - Helpers

    private func openExpandedCard(in app: XCUIApplication) {
        tap(app.buttons[firstCardID], in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[expandedRootID].waitForExistence(timeout: 5),
            "Tapping the card should open the expanded card"
        )
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            seedArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()
        return app
    }

    /// The four fields are addressed by their accessibility labels, which is how the rest of this
    /// suite reaches auth fields, and the English labels are pinned by the launch arguments above.
    private func completeUpgradeForm(in app: XCUIApplication) {
        type("guesttester", into: app.textFields["Username field"], in: app)
        type("guest@example.com", into: app.textFields["Email field"], in: app)
        type("SecurePass123", into: app.secureTextFields["Password field"], in: app)
        type("SecurePass123", into: app.secureTextFields["Confirm password field"], in: app)

        tap(app.buttons["Create Account"], in: app)
    }

    /// SwiftUI installs the text responder a frame after the tap lands, so a `typeText` that
    /// arrives first fails with "Neither element nor any descendant has keyboard focus" — the flake
    /// `CategoryQuestionsExpansionUITests` already hits. Wait on the field's own focus, not on the
    /// software keyboard: a simulator with a hardware keyboard attached never shows one.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(scrollUntilHittable(field, in: app), "Field should be reachable")
        field.tap()
        XCTAssertTrue(
            waitUntil(timeout: 3) { Self.hasKeyboardFocus(field) },
            "The field should take keyboard focus before any text is typed"
        )
        if field.elementType == .secureTextField {
            declineStrongPasswordSuggestion(in: app)
        }
        field.typeText(text)
    }

    /// The password fields are `.newPassword`, so iOS AutoFill can slide up its "Use Strong
    /// Password?" panel a moment after one takes focus. It arrives mid-`typeText`, swallows every
    /// keystroke after the first, and covers the Confirm field so it is never hittable. Whether it
    /// appears depends on the simulator's Passwords state, so wait for it briefly and close it if
    /// it shows; the field keeps keyboard focus.
    private func declineStrongPasswordSuggestion(in app: XCUIApplication) {
        let panel = app.windows.containing(.button, identifier: "GenerateStrongPasswordButton").firstMatch
        guard panel.waitForExistence(timeout: 2) else { return }

        panel.buttons["xmark"].tap()
        XCTAssertTrue(
            waitUntil(timeout: 3) { !app.buttons["GenerateStrongPasswordButton"].exists },
            "The strong password suggestion should close"
        )
    }

    /// `hasKeyboardFocus` is not in `XCUIElement`'s public surface, so this reads it through KVC.
    /// A missing key means a future Xcode renamed it: assume focus rather than fail, because the
    /// `typeText` that follows reports a genuine focus problem on its own.
    private static func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? true
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(scrollUntilHittable(element, in: app), "Element should be reachable")
        element.tap()
    }

    /// Question cards are tall enough that only about two fit on an iPhone-sized screen, and the
    /// upgrade form scrolls once the keyboard is up, so both need scrolling before they can be tapped.
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
