import Foundation

/// Which App Check provider a launch installs.
///
/// App Check answers one question for the backend: did this request come from our app? The six paid
/// AI callables enforce it (`AI_FUNCTION_OPTIONS` in `functions/index.js`), so a launch that
/// installs the wrong provider cannot reach the AI features at all.
///
/// The choice is a value rather than an `#if DEBUG` at the install site, so a test can assert every
/// combination instead of only the one the current configuration compiles.
enum AppCheckProviderChoice: Equatable {
    /// App Attest. Keyed to the device and to the copy of the app Apple distributed, so it is the
    /// only choice that satisfies enforcement for a real user.
    case appAttest

    /// Firebase's debug provider. It attests nothing. It presents a token that somebody registered
    /// by hand in the Firebase console, which is the only way a simulator can pass enforcement.
    case debugProvider

    /// No provider. Requests carry no App Check token, so every enforced callable rejects them.
    case noProvider
}

/// The facts about this launch that decide the provider.
struct AppCheckLaunchContext: Equatable {
    var isDebugBuild: Bool
    var isUITestHarness: Bool
}

enum AppCheckPolicy {
    /// A release build always attests, whatever arguments the launch carries. A debug build uses
    /// the debug provider, except under a UI-test harness: those screens run on local fixtures and
    /// call no AI callable, so a token there would only add console noise and network traffic.
    static func provider(for context: AppCheckLaunchContext) -> AppCheckProviderChoice {
        guard context.isDebugBuild else {
            return .appAttest
        }

        return context.isUITestHarness ? .noProvider : .debugProvider
    }
}

extension AppCheckLaunchContext {
    static var current: AppCheckLaunchContext {
        #if DEBUG
        AppCheckLaunchContext(
            isDebugBuild: true,
            isUITestHarness: UITestLaunchOptions.isAnyHarnessEnabled
        )
        #else
        AppCheckLaunchContext(isDebugBuild: false, isUITestHarness: false)
        #endif
    }
}
