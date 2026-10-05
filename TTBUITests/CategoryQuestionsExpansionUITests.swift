import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class CategoryQuestionsExpansionUITests: XCTestCase {
    private let harnessArgument = "-ui-test-category-questions-harness"
    private let firstQuestionCardID = "question-card-category.Career-career-question-1"
    private let secondQuestionCardID = "question-card-category.Career-career-question-2"
    private let fullscreenCloseID = "question-card-fullscreen-close"
    private let fullscreenSaveID = "question-card-fullscreen-save"
    private let fullscreenShareID = "question-card-fullscreen-share"
    private let fullscreenFavoriteID = "question-card-fullscreen-favorite"
    private let managerSuggestionID = "question-card-quick-suggestion-my manager"
    private let dadSuggestionID = "question-card-quick-suggestion-my dad"
    private let closeFriendSuggestionID = "question-card-quick-suggestion-a close friend"
    private let teacherSuggestionID = "question-card-quick-suggestion-my teacher"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

@MainActor
extension CategoryQuestionsExpansionUITests {
    func testFirstQuestionPresentsAndDismissesFullscreenEditor() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let firstCard = app.buttons[firstQuestionCardID]
        let secondCard = app.buttons[secondQuestionCardID]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
        XCTAssertTrue(secondCard.waitForExistence(timeout: 2))

        openAndCloseFirstQuestion(
            app: app,
            firstCard: firstCard,
        )

        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
        XCTAssertTrue(secondCard.waitForExistence(timeout: 2))

        openAndCloseFirstQuestion(
            app: app,
            firstCard: firstCard,
        )

        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
        XCTAssertTrue(secondCard.waitForExistence(timeout: 2))
    }

    func testCardFavoriteButtonTogglesWithoutOpeningFullscreen() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let favoriteButton = app.buttons["question-card-favorite-category.Career-career-question-1"]
        XCTAssertTrue(waitForElementToBecomeHittable(favoriteButton, timeout: 3))
        XCTAssertEqual(favoriteButton.label, "Add to favorites")

        favoriteButton.tap()

        XCTAssertTrue(waitUntil(timeout: 2) {
            favoriteButton.exists && favoriteButton.label == "Remove from favorites"
        })
        XCTAssertFalse(app.buttons[fullscreenSaveID].exists)

        let firstCard = app.buttons[firstQuestionCardID]
        XCTAssertTrue(waitForElementToBecomeHittable(firstCard, timeout: 2))
        firstCard.tap()
        XCTAssertTrue(app.buttons[fullscreenFavoriteID].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons[fullscreenFavoriteID].label, "Remove from favorites")
        closeFullscreen(in: app)
        XCTAssertTrue(waitForElementToBecomeHittable(favoriteButton, timeout: 2))

        favoriteButton.tap()

        XCTAssertTrue(waitUntil(timeout: 2) {
            favoriteButton.exists && favoriteButton.label == "Add to favorites"
        })
        XCTAssertFalse(app.buttons[fullscreenSaveID].exists)
    }

    func testExpandedChromeAndSequentialQuickAnswerFlow() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let secondCard = app.buttons[secondQuestionCardID]
        XCTAssertTrue(waitForElementToBecomeHittable(secondCard, timeout: 3))
        secondCard.tap()

        XCTAssertTrue(app.buttons[fullscreenShareID].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[fullscreenFavoriteID].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[fullscreenSaveID].waitForExistence(timeout: 2))

        XCTAssertTrue(waitForInputToAppear(in: app, index: 0))

        let firstInput = inputElement(in: app, index: 0)
        firstInput.tap()

        let managerSuggestion = app.buttons[managerSuggestionID]
        let dadSuggestion = app.buttons[dadSuggestionID]
        let closeFriendSuggestion = app.buttons[closeFriendSuggestionID]
        let teacherSuggestion = app.buttons[teacherSuggestionID]

        XCTAssertTrue(managerSuggestion.waitForExistence(timeout: 2))
        XCTAssertTrue(dadSuggestion.waitForExistence(timeout: 2))
        XCTAssertTrue(closeFriendSuggestion.waitForExistence(timeout: 2))
        XCTAssertTrue(teacherSuggestion.waitForExistence(timeout: 2))

        managerSuggestion.tap()
        XCTAssertTrue(waitForInputValue("My manager", in: app, index: 0))

        dadSuggestion.tap()
        XCTAssertTrue(waitForInputValue("My dad", in: app, index: 1))

        closeFriendSuggestion.tap()
        XCTAssertTrue(waitForInputValue("A close friend", in: app, index: 2))
        XCTAssertFalse(teacherSuggestion.exists)
    }

    func testQuickSuggestionPrefersFirstEmptySlotOverFocusedSlot() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let secondCard = app.buttons[secondQuestionCardID]
        XCTAssertTrue(waitForElementToBecomeHittable(secondCard, timeout: 3))
        secondCard.tap()

        XCTAssertTrue(waitForInputToAppear(in: app, index: 0))

        let firstInput = inputElement(in: app, index: 0)
        firstInput.tap()
        firstInput.typeText("Custom mentor")
        firstInput.tap()

        let managerSuggestion = app.buttons[managerSuggestionID]
        XCTAssertTrue(managerSuggestion.waitForExistence(timeout: 2))
        managerSuggestion.tap()

        XCTAssertTrue(waitUntil(timeout: 2) {
            self.inputValue(in: app, index: 0) == "Custom mentor"
                && self.inputValue(in: app, index: 1) == "My manager"
        })
    }

    func testFullscreenFavoriteButtonTogglesLabel() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let secondCard = app.buttons[secondQuestionCardID]
        XCTAssertTrue(waitForElementToBecomeHittable(secondCard, timeout: 3))
        secondCard.tap()

        let favoriteButton = app.buttons[fullscreenFavoriteID]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 2))
        XCTAssertEqual(favoriteButton.label, "Add to favorites")

        favoriteButton.tap()

        XCTAssertTrue(waitUntil(timeout: 2) {
            favoriteButton.exists && favoriteButton.label == "Remove from favorites"
        })

        favoriteButton.tap()

        XCTAssertTrue(waitUntil(timeout: 2) {
            favoriteButton.exists && favoriteButton.label == "Add to favorites"
        })
    }

    private func openAndCloseFirstQuestion(
        app: XCUIApplication,
        firstCard: XCUIElement,
    ) {
        XCTAssertTrue(waitForElementToBecomeHittable(firstCard, timeout: 3))
        firstCard.tap()
        XCTAssertTrue(waitForElementToBecomeNotHittable(firstCard, timeout: 2))
        closeFullscreen(in: app)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
    }

    private func waitForElementToBecomeHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && element.isHittable
        }
    }

    private func waitForElementToBecomeNotHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && !element.isHittable
        }
    }
    private func closeFullscreen(in app: XCUIApplication) {
        let closeButtonByID = app.buttons[fullscreenCloseID]
        if closeButtonByID.waitForExistence(timeout: 1) {
            closeButtonByID.tap()
        }
    }

    private func waitForInputToAppear(in app: XCUIApplication, index: Int) -> Bool {
        waitUntil(timeout: 2) {
            app.textViews["question-card-input-\(index)"].exists
                || app.textFields["question-card-input-\(index)"].exists
        }
    }

    private func waitForInputValue(_ value: String, in app: XCUIApplication, index: Int) -> Bool {
        waitUntil(timeout: 2) {
            self.inputValue(in: app, index: index) == value
        }
    }

    private func inputElement(in app: XCUIApplication, index: Int) -> XCUIElement {
        let identifier = "question-card-input-\(index)"
        let textView = app.textViews[identifier]
        if textView.exists {
            return textView
        }

        return app.textFields[identifier]
    }

    private func inputValue(in app: XCUIApplication, index: Int) -> String? {
        inputElement(in: app, index: index).value as? String
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
