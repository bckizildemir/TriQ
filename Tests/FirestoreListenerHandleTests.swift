import Testing
@testable import TTB

struct FirestoreListenerHandleTests {
    @Test func cancelRemovesTheRegistrationOnce() {
        let registration = MockQuestionListListenerRegistration()
        let handle = FirestoreListenerHandle(registration: registration)

        handle.cancel()
        handle.cancel()

        #expect(registration.removeCount == 1)
    }

    @Test func releasingTheLastReferenceRemovesTheRegistration() {
        let registration = MockQuestionListListenerRegistration()
        var handle: FirestoreListenerHandle? = FirestoreListenerHandle(registration: registration)
        #expect(!registration.isRemoved)

        handle = nil

        #expect(handle == nil)
        #expect(registration.removeCount == 1)
    }

    @Test func releasingACancelledHandleDoesNotRemoveTwice() {
        let registration = MockQuestionListListenerRegistration()
        var handle: FirestoreListenerHandle? = FirestoreListenerHandle(registration: registration)

        handle?.cancel()
        handle = nil

        #expect(handle == nil)
        #expect(registration.removeCount == 1)
    }

    @Test func cancelFromAnotherIsolationRemovesTheRegistration() async {
        let registration = MockQuestionListListenerRegistration()
        let handle = FirestoreListenerHandle(registration: registration)

        await Task.detached { handle.cancel() }.value

        #expect(registration.isRemoved)
    }

    /// The handle `FavoriteService` returns for an empty `userId`: it holds no registration, so
    /// the store can cancel it like any other handle.
    @Test func cancelWithoutARegistrationDoesNothing() {
        let handle = FirestoreListenerHandle(registration: nil)

        handle.cancel()
        handle.cancel()
    }

    @Test func handleServesTheFavoritesSeam() {
        let registration = MockQuestionListListenerRegistration()
        let handle: any FavoriteListenerHandle = FirestoreListenerHandle(registration: registration)

        handle.cancel()

        #expect(registration.removeCount == 1)
    }
}
