import Foundation

/// Cancels a question-list-share snapshot subscription.
///
/// Exists so the seam never names a Firebase type: the live adapter wraps a
/// `ListenerRegistration`, and the in-memory adapter returns something that does nothing.
protocol QuestionListShareListenerHandle {
    func remove()
}

/// Everything `SharedQuestionListStore` needs from the backend to own question-list-share state.
///
/// Two adapters satisfy this: `QuestionListShareService`, the live Firestore/Cloud Functions
/// actor, and `InMemoryQuestionListShareService`, which reproduces the same lifecycle in memory.
///
/// `Sendable` so a `@MainActor` caller can hold the existential and await its `nonisolated`
/// requirements without sending a non-`Sendable` value off the main actor. Conformers must be
/// `Sendable`, in practice an `actor` or a `@MainActor` type.
protocol QuestionListShareServicing: Sendable {
    func ownedSharesListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShare], Error>) -> Void
    ) async -> QuestionListShareListenerHandle

    func acceptedRecipientsListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShareRecipient], Error>) -> Void
    ) async -> QuestionListShareListenerHandle

    func fetchShare(shareId: String) async throws -> QuestionListShare
    func fetchRecipients(shareId: String) async throws -> [QuestionListShareRecipient]
    func fetchAcceptedShare(shareId: String, recipientId: String) async throws -> AcceptedQuestionListShare

    @discardableResult
    func createShare(listId: String, includeOwnerAnswers: Bool) async throws -> QuestionListShareCreationResult
    func previewShare(shareCode: String) async throws -> QuestionListSharePreview
    /// `currentUserId` is the identity accepting the share. The live actor ignores it — Firebase
    /// Auth alone determines who's accepting server-side — but the in-memory adapter needs it
    /// explicitly, since it has no auth session to read from and a local test can simulate a
    /// recipient other than whatever identity it was constructed with.
    @discardableResult
    func acceptShare(shareCode: String, actingAs currentUserId: String) async throws -> String
    func disableShare(shareId: String) async throws
    func regenerateLink(shareId: String) async throws -> QuestionListShareCreationResult
    func revokeShare(shareId: String) async throws
    func leaveShare(shareId: String) async throws
    func sendReply(shareId: String) async throws
    func markReplySeen(shareId: String, recipientId: String) async throws
}
