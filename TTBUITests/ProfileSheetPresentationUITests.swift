import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class ProfileSheetPresentationUITests: XCTestCase {
    private let profileHarnessArgument = "-ui-test-profile-harness"
    private let profileAnonymousHarnessArgument = "-ui-test-profile-anonymous-harness"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension ProfileSheetPresentationUITests {
    func testProfileSheetsStayPresented() {
        let app = XCUIApplication()
        app.launchArguments += [
            profileHarnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let photoButton = app.buttons["profile-photo-button"]
        XCTAssertTrue(photoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { photoButton.isHittable })
        photoButton.tap()

        let photoSheet = app.descendants(matching: .any)["profile-photo-sheet"]
        XCTAssertTrue(photoSheet.waitForExistence(timeout: 5))
        waitForSheetStability()
        XCTAssertTrue(photoSheet.exists)

        app.buttons["profile-photo-close-button"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !photoSheet.exists })

        let statisticsSection = app.descendants(matching: .any)["profile-statistics-section"]
        XCTAssertTrue(scrollUntilHittable(statisticsSection, in: app))
        statisticsSection.tap()

        let statisticsSheet = app.descendants(matching: .any)["profile-statistics-sheet"]
        XCTAssertTrue(statisticsSheet.waitForExistence(timeout: 5))
        waitForSheetStability()
        XCTAssertTrue(statisticsSheet.exists)

        app.buttons["profile-statistics-close-button"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !statisticsSheet.exists })

        let editButton = app.buttons["profile-edit-button"]
        XCTAssertTrue(scrollUntilHittable(editButton, in: app))
        editButton.tap()

        let editSheet = app.descendants(matching: .any)["profile-edit-sheet"]
        XCTAssertTrue(editSheet.waitForExistence(timeout: 5))
        waitForSheetStability()
        XCTAssertTrue(editSheet.exists)

        app.buttons["Cancel editing profile"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !editSheet.exists })

        // The badge detail sheet is deliberately not covered here. `BadgeModel.loadBadges()`
        // reads `Auth.auth().currentUser` directly rather than the injected auth model, and the
        // harness signs in with a mock, so `badgeModel.badges` is always empty and
        // `BadgesSectionView` renders its empty state — no `profile-badge-*` element can ever
        // exist under this harness. Restoring this coverage needs an injectable badge source
        // (see the harness-seam candidate in Documentation/ARCHITECTURE_DEEPENING_AUDIT.md),
        // not a change to this test.
    }

    func testGuestUpgradeSheetStaysPresented() {
        let app = XCUIApplication()
        app.launchArguments += [
            profileAnonymousHarnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let upgradeButton = app.buttons["profile-guest-upgrade-button"]
        XCTAssertTrue(upgradeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { upgradeButton.isHittable })
        upgradeButton.tap()

        let upgradeSheet = app.descendants(matching: .any)["profile-guest-upgrade-sheet"]
        XCTAssertTrue(upgradeSheet.waitForExistence(timeout: 5))
        waitForSheetStability()
        XCTAssertTrue(upgradeSheet.exists)
    }

    private func waitForSheetStability() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.25))
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        for _ in 0..<8 {
            if element.isHittable { return true }
            app.swipeUp()
        }
        return element.isHittable
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
