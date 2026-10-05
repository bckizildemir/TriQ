import XCTest
@testable import TTB

/// The provider choice is the one place a launch can end up unattested, and the failure is silent:
/// an unattested build reaches the AI callables and gets `unauthenticated`, which the client reports
/// as a network error. So every combination is asserted here rather than left to the configuration
/// the test run happens to compile.
final class AppCheckPolicyTests: XCTestCase {

    // MARK: - The choice

    func testAReleaseLaunchAttests() {
        let choice = AppCheckPolicy.provider(
            for: AppCheckLaunchContext(isDebugBuild: false, isUITestHarness: false)
        )

        XCTAssertEqual(choice, .appAttest)
    }

    func testAHarnessArgumentCannotWeakenAReleaseBuild() {
        let choice = AppCheckPolicy.provider(
            for: AppCheckLaunchContext(isDebugBuild: false, isUITestHarness: true)
        )

        XCTAssertEqual(choice, .appAttest)
    }

    func testADebugLaunchUsesTheDebugProvider() {
        let choice = AppCheckPolicy.provider(
            for: AppCheckLaunchContext(isDebugBuild: true, isUITestHarness: false)
        )

        XCTAssertEqual(choice, .debugProvider)
    }

    func testAHarnessInstallsNoProvider() {
        let choice = AppCheckPolicy.provider(
            for: AppCheckLaunchContext(isDebugBuild: true, isUITestHarness: true)
        )

        XCTAssertEqual(choice, .noProvider)
    }

    // MARK: - The launch context

    func testEveryHarnessArgumentIsRecognisedAsAHarness() {
        for argument in UITestLaunchOptions.allHarnessArguments {
            XCTAssertTrue(
                UITestLaunchOptions.isAnyHarness(in: ["-someOtherFlag", argument]),
                "\(argument) is a harness argument but does not read as one"
            )
        }
    }

    func testAnOrdinaryLaunchIsNotAHarness() {
        XCTAssertFalse(UITestLaunchOptions.isAnyHarness(in: []))
        XCTAssertFalse(UITestLaunchOptions.isAnyHarness(in: ["-AppleLanguages", "(tr)"]))
    }

    func testEveryHarnessThatSkipsFirebaseConfigurationIsAlsoInTheHarnessList() {
        // The two lists differ on purpose, but only in one direction: a harness may configure
        // Firebase and still be a harness. One that skips configuration and is missing here would
        // install the debug provider during a UI test. Both are now derived from `Harness`, so
        // this holds by construction — this test is the regression guard for that staying true.
        let skipping = UITestLaunchOptions.Harness.allCases
            .filter { !$0.needsFirebase }
            .map(\.rawValue)

        XCTAssertFalse(skipping.isEmpty, "expected at least one Firebase-skipping harness to check")

        for argument in skipping {
            XCTAssertTrue(
                UITestLaunchOptions.allHarnessArguments.contains(argument),
                "\(argument) skips Firebase configuration but is missing from allHarnessArguments"
            )
        }
    }

    func testTheCurrentContextReportsTheBuildTheTestsRunIn() {
        // The test bundle only ever runs against a debug build. This asserts the wiring reads the
        // configuration at all, so a release binary cannot silently take the debug branch.
        XCTAssertTrue(AppCheckLaunchContext.current.isDebugBuild)
    }
}
