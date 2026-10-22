import FirebaseFirestore
import Synchronization

/// Owns a Firebase listener registration, which is not `Sendable`, behind a lock, so a service
/// actor can hand it to a main-actor model. The first `cancel()` removes the registration; later
/// calls do nothing.
///
/// One handle serves the question, list, share and favorites listeners. A `nil` registration (the
/// empty-`userId` favorites case) makes every `cancel()` do nothing. A service actor can send a
/// registration in here only if it builds it from a `Firestore` it fetches in the method: one
/// built from a stored `Firestore` joins the actor's region and cannot leave it.
final class FirestoreListenerHandle: FavoriteListenerHandle {
    private let registration: Mutex<(any ListenerRegistration)?>

    init(registration: sending (any ListenerRegistration)?) {
        self.registration = Mutex(registration)
    }

    /// A handle that is overwritten or dropped must still remove its registration, or the
    /// listener stays live for the rest of the process (TriQ#50).
    deinit {
        cancel()
    }

    func cancel() {
        // Take the registration out under the lock and remove it after, so Firebase never runs
        // while the lock is held.
        let removed = registration.withLock { $0.take() }
        removed?.remove()
    }
}
