import Testing
@testable import TTB

/// The path a live ID-token change takes from the Firebase closure to the store: map the uid, then
/// hop to the main actor. `FakePermanentAccountObserver` calls the stores directly and skips this
/// path, so it is tested here on its own, without Firebase (#121).
@Suite(.timeLimit(.minutes(1)))
struct PermanentAccountObserverTests {
    @Test func aPermanentAccountDeliversItsUidOnTheMainActor() async {
        let delivered = await deliver(uid: "uid-1", isAnonymous: false)

        #expect(delivered == "uid-1")
    }

    @Test func aGuestDeliversAnEmptyUid() async {
        let delivered = await deliver(uid: "uid-1", isAnonymous: true)

        #expect(delivered.isEmpty)
    }

    @Test func aSignedOutUserDeliversAnEmptyUid() async {
        let delivered = await deliver(uid: nil, isAnonymous: false)

        #expect(delivered.isEmpty)
    }

    private func deliver(uid: String?, isAnonymous: Bool) async -> String {
        await withCheckedContinuation { continuation in
            LivePermanentAccountObserver.deliver(uid: uid, isAnonymous: isAnonymous) { id in
                MainActor.assertIsolated()
                continuation.resume(returning: id)
            }
        }
    }
}
