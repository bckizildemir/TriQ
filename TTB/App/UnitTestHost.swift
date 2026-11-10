import Foundation

/// Whether this process is the host of a unit-test run.
///
/// The app target is the `TEST_HOST` of `TTBTests` (`BUNDLE_LOADER = $(TEST_HOST)` in the project),
/// so a unit-test run launches the real app first and injects the test bundle into it. That makes
/// the launch a container for the tests rather than a launch a person asked for, and it must not
/// reach the live Firebase project (#112): no live `AppEnvironment` and its listeners, no App Check
/// attestation, no device registration.
///
/// "Is XCTest loaded here" is the difference between the two launches: a unit test injects its
/// bundle into the app, so XCTest is loaded in the app's process; a UI test drives a separate launch
/// of the app, so it is not. `UITestLaunchOptions` and `AppCheckLaunchContext` answer the
/// neighbouring question, "was this launch asked to run a harness".
enum UnitTestHost {
    static var isHostingUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
