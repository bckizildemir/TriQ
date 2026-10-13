import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class HomeCategoryChipsUITests: XCTestCase {
    private let harnessArgument = "-ui-test-home-harness"
    private let careerChipID = "home-category-chip-Career"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension HomeCategoryChipsUITests {
    func testCategoryChipOpensCategoryQuestions() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let careerChip = app.buttons[careerChipID]
        XCTAssertTrue(careerChip.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { careerChip.isHittable })

        careerChip.tap()

        let categoryTitle = app.navigationBars["Career"]
        XCTAssertTrue(categoryTitle.waitForExistence(timeout: 5))

        let questionCard = app.buttons["question-card-category.Career-home-question-1"]
        XCTAssertTrue(questionCard.waitForExistence(timeout: 5))
    }

    /// The chip row is pinned above the feed, so a feed scroll must not move it away (#59).
    func testChipStaysHittableAfterFeedScroll() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-ui-test-home-long-feed",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let personalChip = app.buttons["home-category-chip-Personal"]
        XCTAssertTrue(personalChip.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { personalChip.isHittable })
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "question-card-home.")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // Pin the card by its identifier so the check after the swipe reads the same card.
        let probe = app.buttons[card.identifier]
        let probeTop = probe.frame.minY

        app.swipeUp()
        // The long feed is taller than the screen, so the swipe must move it.
        XCTAssertTrue(waitUntil(timeout: 5) { !probe.exists || probe.frame.minY < probeTop - 50 })
        XCTAssertTrue(waitUntil(timeout: 5) { personalChip.isHittable })
        personalChip.tap()

        XCTAssertTrue(app.navigationBars["Personal"].waitForExistence(timeout: 5))
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
