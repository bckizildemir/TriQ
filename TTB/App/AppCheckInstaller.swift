import FirebaseAppCheck
import FirebaseCore
import Foundation
import os

/// Installs the App Check provider for this launch.
///
/// This is the adapter half of the seam. `AppCheckPolicy` decides, this puts the decision into the
/// Firebase SDK, and `AppDelegate` calls it once. The debug provider is compiled out of a release
/// binary rather than merely unreachable in it: harness-only code that reaches the app target is
/// what FIX-1 had to clean up.
enum AppCheckInstaller {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "AppCheck")

    /// Must run before `FirebaseApp.configure()`. Firebase reads the factory while it configures,
    /// so a factory installed afterwards is ignored and every request goes out unattested.
    static func install(_ choice: AppCheckProviderChoice) {
        switch choice {
        case .appAttest:
            AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())

        case .debugProvider:
            #if DEBUG
            // The provider logs its token on first launch. Register that token in
            // Firebase console › App Check › Apps › TTB › Manage debug tokens, or the AI callables
            // reject this build.
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
            logger.info("App Check uses the debug provider. Register the logged token to call AI functions.")
            #endif

        case .noProvider:
            break
        }
    }
}

/// The SDK ships a factory for the debug provider and one for DeviceCheck, but none for App Attest,
/// so the App Attest case needs this. `AppAttestProvider` returns nil when the `FirebaseApp` is
/// missing something it needs; the SDK treats a nil provider as "no token", which enforcement then
/// rejects — a loud failure rather than a silent downgrade.
private final class AppAttestProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}
