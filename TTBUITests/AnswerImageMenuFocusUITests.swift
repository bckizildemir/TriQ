import XCTest

/// Opening a slot's image menu while its answer field is focused used to leave the field holding
/// first responder under the menu. The menu then installed its type-select key input as the
/// keyboard's delegate on every keyboard-toolbar reload, a loop that pegged the CPU and flooded
/// the log until the menu closed. The loop needs the keyboard up, so the menu must dismiss it.
final class AnswerImageMenuFocusUITests: XCTestCase {
    private let harnessArgument = "-ui-test-home-harness"
    private let firstQuestionCardID = "question-card-home.today-home-question-1"
    private let secondSlotInputID = "question-card-input-1"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReopeningImageMenuFromFocusedFieldDismissesKeyboard() {
        let app = XCUIApplication()
        app.launchArguments += [
            harnessArgument,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()

        let card = app.buttons[firstQuestionCardID]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        // The reported path opens the menu once, puts an image in the slot, then reopens it.
        let addImageButtons = app.buttons.matching(NSPredicate(format: "label == 'Add image'"))
        XCTAssertTrue(addImageButtons.element(boundBy: 1).waitForExistence(timeout: 5))
        addImageButtons.element(boundBy: 1).tap()
        let chooseFromLibrary = app.buttons["Choose from Library"]
        XCTAssertTrue(chooseFromLibrary.waitForExistence(timeout: 5))
        chooseFromLibrary.tap()
        // The photo picker runs out of process, so its grid cells never report hittable.
        let photo = app.images["PXGGridLayout-Info"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let changeImage = app.buttons["Change image"]
        XCTAssertTrue(changeImage.waitForExistence(timeout: 10))

        let input = app.textViews[secondSlotInputID].exists
            ? app.textViews[secondSlotInputID]
            : app.textFields[secondSlotInputID]
        input.tap()
        input.typeText("Sleep")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        changeImage.tap()

        XCTAssertTrue(chooseFromLibrary.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 3) { !app.keyboards.firstMatch.exists })
        XCTAssertTrue(app.buttons["Find Image"].exists)
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
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
