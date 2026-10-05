import SwiftUI

/// The app's root: one environment, installed once.
///
/// This used to take eleven models and carry the whole cross-screen behaviour block in its `body`,
/// which is why six UI-test harnesses re-declared the wiring instead of passing through it. Both
/// halves now live behind `AppEnvironment` and `appRoot(_:)`, so this type is the production caller
/// of a seam every harness also uses.
///
/// There is no injectable init any more. A harness applies `appRoot(_:)` to the screen its test
/// drives, because `AppRootView` leads to the onboarding gate — see `docs/adr/0008`. What used to
/// justify the injection is now guaranteed by the modifier instead: this body is two lines, so
/// there is nothing left here for a harness to diverge from.
struct AppEnvironmentRootView: View {
    @StateObject private var environment: AppEnvironment

    /// `StateObject`'s `wrappedValue` is an autoclosure, so the live models are built once on first
    /// render rather than on every `init` — which matters here, because building them opens
    /// Firestore listeners.
    @MainActor
    init(initialDeepLinkURL: URL? = nil) {
        _environment = StateObject(wrappedValue: .live(initialDeepLinkURL: initialDeepLinkURL))
    }

    var body: some View {
        AppRootView()
            .appRoot(environment)
    }
}
