import Foundation

#if DEBUG
/// A list service whose create always fails, so a UI test can reach the "Not saved" row without
/// Firebase. Every other call does nothing.
actor UITestFailingQuestionListService: QuestionListServicing {
    struct CreateFailed: LocalizedError {
        var errorDescription: String? { "UI test create failure" }
    }

    func setupQuestionListsListener(
        userId: String,
        completion: @escaping @MainActor @Sendable (Result<[QuestionList], Error>) -> Void
    ) async -> FirestoreListenerHandle {
        FirestoreListenerHandle(registration: nil)
    }

    func createList(named name: String, ownerId: String) async throws -> String {
        throw CreateFailed()
    }

    func updateList(listId: String, name: String) async throws {}

    func deleteList(listId: String) async throws {}

    func setQuestion(_ questionId: String, in listId: String, isIncluded: Bool) async throws {}
}
#endif
