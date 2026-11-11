@testable import TTB

/// Emits permanent-account ids by hand, so a test can replay a guest upgrade (same uid, no
/// sign-in state change) without Firebase Auth.
///
/// Like the live ID-token listener, `observe` reports the current id once at registration, so a
/// store starts from the same value a real session would hand it (#121).
@MainActor
final class FakePermanentAccountObserver: PermanentAccountObserving {
    private var handlers: [Int: @MainActor @Sendable (String) -> Void] = [:]
    private var nextToken = 0
    /// What a new observation reports first, and what the last `emit` left behind.
    private var currentPermanentUserID: String

    var activeObservationCount: Int { handlers.count }

    nonisolated init(currentPermanentUserID: String = "") {
        self.currentPermanentUserID = currentPermanentUserID
    }

    func observe(
        _ handler: @escaping @MainActor @Sendable (String) -> Void
    ) -> PermanentAccountObservation {
        let token = nextToken
        nextToken += 1
        handlers[token] = handler
        handler(currentPermanentUserID)
        return PermanentAccountObservation { [weak self] in
            self?.handlers[token] = nil
        }
    }

    func emit(_ permanentUserID: String) {
        currentPermanentUserID = permanentUserID
        for handler in handlers.values {
            handler(permanentUserID)
        }
    }
}
