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

    @Test func cancelFromAnotherIsolationRemovesTheRegistration() async {
        let registration = MockQuestionListListenerRegistration()
        let handle = FirestoreListenerHandle(registration: registration)

        await Task.detached { handle.cancel() }.value

        #expect(registration.isRemoved)
    }
}
