import Testing
@testable import TTB

/// `TTBTests` is hosted by the app (`TEST_HOST` in the project), so every unit-test run launches the
/// real app before these tests execute. That launch must not reach the live Firebase project (#112):
/// a live categories listener from the app's own `AppEnvironment` showed up as an App Check failure
/// in a test log, and one batch then sat in diagnostics collection for ten minutes.
@MainActor
struct UnitTestHostTests {
    /// The gates in `TTBApp` and `AppDelegate` go quiet when this is false, so pin the detection the
    /// rest of the suite relies on.
    @Test func thisProcessIsRecognisedAsAUnitTestHost() {
        #expect(UnitTestHost.isHostingUnitTests)
    }

    /// `live()` is the call that opens the Firestore listeners, and the app's root view is its only
    /// production caller, so zero means the host rendered no live environment at all.
    @Test func theHostAppBuiltNoLiveEnvironment() {
        #expect(AppEnvironment.liveBuildCount == 0)
    }
}
