@testable import TTB

/// Emits permanent-account ids by hand, so a test can replay a guest upgrade (same uid, no
/// sign-in state change) without Firebase Auth.
@MainActor
final class FakePermanentAccountObserver: PermanentAccountObserving {
    private var handlers: [Int: @MainActor @Sendable (String) -> Void] = [:]
    private var nextToken = 0

    var activeObservationCount: Int { handlers.count }

    nonisolated init() {}

    func observe(
        _ handler: @escaping @MainActor @Sendable (String) -> Void
    ) -> PermanentAccountObservation {
        let token = nextToken
        nextToken += 1
        handlers[token] = handler
        return PermanentAccountObservation { [weak self] in
            self?.handlers[token] = nil
        }
    }

    func emit(_ permanentUserID: String) {
        for handler in handlers.values {
            handler(permanentUserID)
        }
    }
}
