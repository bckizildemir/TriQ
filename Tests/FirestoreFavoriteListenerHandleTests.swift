import FirebaseFirestore
import Foundation
import Synchronization
import Testing
@testable import TTB

struct FirestoreFavoriteListenerHandleTests {
    @Test func cancelRemovesTheRegistrationOnce() {
        let removals = RemovalCounter()
        let handle = FirestoreFavoriteListenerHandle(
            registration: CountingListenerRegistration(removals: removals)
        )

        handle.cancel()
        handle.cancel()

        #expect(removals.count == 1)
    }
}

/// The registration is sent into the handle, so the test reads its removals through this
/// Sendable counter rather than through the registration itself.
private final class RemovalCounter: Sendable {
    private let removals = Mutex(0)

    var count: Int { removals.withLock { $0 } }

    func record() {
        removals.withLock { $0 += 1 }
    }
}

private final class CountingListenerRegistration: NSObject, ListenerRegistration {
    private let removals: RemovalCounter

    init(removals: RemovalCounter) {
        self.removals = removals
    }

    func remove() {
        removals.record()
    }
}
