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

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
