import FirebaseAuth

/// Stops a `PermanentAccountObserving` subscription. `cancel()` is safe to call more than once.
@MainActor
final class PermanentAccountObservation {
    private var onCancel: (@MainActor () -> Void)?

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        let work = onCancel
        onCancel = nil
        work?()
    }
}

/// Tells a store which permanent (non-anonymous) account is signed in.
///
/// The handler gets the permanent uid, or `""` for a guest or a signed-out user. It runs once at
/// registration and again on every change, including a guest upgrade: linking a guest to an email
/// account keeps the uid, so a state listener stays silent, but the ID token refreshes and an
/// ID-token listener fires (#119).
protocol PermanentAccountObserving: Sendable {
    @MainActor
    func observe(
        _ handler: @escaping @MainActor @Sendable (String) -> Void
    ) -> PermanentAccountObservation
}

/// The live adapter: the Firebase closure forwards raw values to `permanentUserID` and hops to
/// the main actor, and does nothing else.
struct LivePermanentAccountObserver: PermanentAccountObserving {
    /// `""` for a guest or a signed-out user, the uid for a permanent account.
    static func permanentUserID(uid: String?, isAnonymous: Bool) -> String {
        isAnonymous ? "" : uid ?? ""
    }

    @MainActor
    func observe(
        _ handler: @escaping @MainActor @Sendable (String) -> Void
    ) -> PermanentAccountObservation {
        let auth = Auth.auth()
        let registration = auth.addIDTokenDidChangeListener { _, user in
            let id = Self.permanentUserID(uid: user?.uid, isAnonymous: user?.isAnonymous ?? false)
            Task { @MainActor in
                handler(id)
            }
        }
        return PermanentAccountObservation {
            Auth.auth().removeIDTokenDidChangeListener(registration)
        }
    }
}
