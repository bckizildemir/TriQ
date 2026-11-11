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

/// The live adapter: the Firebase closure forwards raw values to `deliver` and does nothing else.
struct LivePermanentAccountObserver: PermanentAccountObserving {
    /// `""` for a guest or a signed-out user, the uid for a permanent account.
    static func permanentUserID(uid: String?, isAnonymous: Bool) -> String {
        isAnonymous ? "" : uid ?? ""
    }

    /// Maps one ID-token callback to the handler's argument and delivers it on the main actor.
    ///
    /// Kept out of the Firebase closure so a test can run the exact path a live token change takes;
    /// `FakePermanentAccountObserver` calls the stores directly and never exercises it (#121).
    static func deliver(
        uid: String?,
        isAnonymous: Bool,
        to handler: @escaping @MainActor @Sendable (String) -> Void
    ) {
        let id = permanentUserID(uid: uid, isAnonymous: isAnonymous)
        Task { @MainActor in
            handler(id)
        }
    }

    @MainActor
    func observe(
        _ handler: @escaping @MainActor @Sendable (String) -> Void
    ) -> PermanentAccountObservation {
        let auth = Auth.auth()
        let registration = auth.addIDTokenDidChangeListener { _, user in
            Self.deliver(
                uid: user?.uid,
                isAnonymous: user?.isAnonymous ?? false,
                to: handler
            )
        }
        return PermanentAccountObservation {
            Auth.auth().removeIDTokenDidChangeListener(registration)
        }
    }
}
