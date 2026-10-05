import SwiftUI
import XCTest
@testable import TTB

/// The one launch-argument read that guarded no service.
///
/// `SimulatorSafeSheetDismissButton` delays its dismiss by 700 ms so a UI test cannot tap the button
/// before the sheet finishes its presentation animation. The button used to ask
/// `UITestLaunchOptions` for that itself, which made a production view aware of one harness. The
/// delay is now a value the harness supplies, and the app supplies nothing.
@MainActor
final class SheetDismissDelayTests: XCTestCase {

    /// Zero is the production answer, and it is what a screen gets when nothing wired it.
    func testAScreenWithNoEnvironmentDismissesASheetImmediately() {
        XCTAssertEqual(EnvironmentValues().sheetDismissDelay, .zero)
    }

    func testAHarnessCanDelayASheetDismiss() {
        let environment = AppEnvironment.uiTest(
            storage: UserDefaults(suiteName: #function) ?? .standard,
            authModel: UITestAuthModelFactory.permanentUser(uid: "sheet-dismiss-test-user"),
            questionModel: QuestionModel(localQuestions: []),
            sheetDismissDelay: .milliseconds(700)
        )

        XCTAssertEqual(environment.sheetDismissDelay, .milliseconds(700))
    }

    func testAHarnessThatAsksForNoDelayGetsNone() {
        let environment = AppEnvironment.uiTest(
            storage: UserDefaults(suiteName: #function) ?? .standard,
            authModel: UITestAuthModelFactory.permanentUser(uid: "sheet-dismiss-test-user"),
            questionModel: QuestionModel(localQuestions: [])
        )

        XCTAssertEqual(environment.sheetDismissDelay, .zero)
    }
}
