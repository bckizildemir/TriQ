import FirebaseFirestore
import FirebaseFunctions
import Foundation
import os

/// `Sendable` because the `@MainActor` `QuestionListStore` hands this existential to `nonisolated async`
/// requirements. `QuestionListService` and the test mock are both `actor`s.
protocol QuestionListServicing: Sendable {
    /// `completion` runs on the main actor: its one consumer is `QuestionListStore`, so the
    /// adapter makes the hop once and the store applies each snapshot synchronously.
    func setupQuestionListsListener(
        userId: String,
        completion: @escaping @MainActor @Sendable (Result<[QuestionList], Error>) -> Void
    ) async -> FirestoreListenerHandle
    func createList(named name: String, ownerId: String) async throws -> String
    func updateList(listId: String, name: String) async throws
    func deleteList(listId: String) async throws
    func setQuestion(
        _ questionId: String,
        in listId: String,
        isIncluded: Bool
    ) async throws
}

actor QuestionListService: QuestionListServicing {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "QuestionListService")

    enum QuestionListError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return String(localized: "questionLists.error.invalidResponse")
            }
        }
    }

    /// Fetches `Firestore` here instead of storing it: a registration built from a stored
    /// `Firestore` joins this actor's region and cannot be sent into the `Sendable` handle.
    func setupQuestionListsListener(
        userId: String,
        completion: @escaping @MainActor @Sendable (Result<[QuestionList], Error>) -> Void
    ) async -> FirestoreListenerHandle {
        let registration = Firestore.firestore().collection("questionLists")
            .whereField("ownerId", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [logger] snapshot, error in
                Self.deliverSnapshot(
                    documents: snapshot?.documents.map { (id: $0.documentID, data: $0.data()) },
                    error: error,
                    logger: logger,
                    to: completion
                )
            }
        return FirestoreListenerHandle(registration: registration)
    }

    /// Maps one snapshot callback to the store's result and delivers it on the main actor.
    /// Documents that do not decode are dropped; a missing snapshot is no lists.
    ///
    /// Kept out of the Firebase closure so a test can run the exact path a live snapshot takes;
    /// `MockQuestionListService` calls the store directly and never exercises it.
    static func deliverSnapshot(
        documents: [(id: String, data: [String: Any])]?,
        error: Error?,
        logger: Logger,
        to completion: @escaping @MainActor @Sendable (Result<[QuestionList], Error>) -> Void
    ) {
        SnapshotDelivery.deliver(
            documents: documents,
            error: error,
            onError: { logger.error("Question lists listener error: \($0.localizedDescription)") },
            decode: { QuestionList.fromFirestore($0.data, id: $0.id) },
            to: completion
        )
    }

    func createList(named name: String, ownerId: String) async throws -> String {
        let result = try await Functions.europeWest1.httpsCallable("createQuestionList").call([
            "name": name,
        ])

        return try Self.listId(from: result.data)
    }

    /// Reads the new list's id from the `createQuestionList` payload. A payload that is not a
    /// dictionary, or has no non-empty `listId`, is `QuestionListError.invalidResponse`.
    static func listId(from payload: Any) throws -> String {
        guard let data = payload as? [String: Any],
              let listId = data["listId"] as? String,
              !listId.isEmpty
        else {
            throw QuestionListError.invalidResponse
        }

        return listId
    }

    func updateList(listId: String, name: String) async throws {
        _ = try await Functions.europeWest1.httpsCallable("updateQuestionList").call([
            "listId": listId,
            "name": name,
        ])
    }

    func deleteList(listId: String) async throws {
        _ = try await Functions.europeWest1.httpsCallable("deleteQuestionList").call([
            "listId": listId,
        ])
    }

    func setQuestion(_ questionId: String, in listId: String, isIncluded: Bool) async throws {
        _ = try await Functions.europeWest1.httpsCallable("setQuestionInList").call([
            "listId": listId,
            "questionId": questionId,
            "isIncluded": isIncluded,
        ])
    }
}
