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
    private let functions = Functions.functions(region: "europe-west1")
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
        let result: Result<[QuestionList], Error>
        if let error {
            logger.error("Question lists listener error: \(error.localizedDescription)")
            result = .failure(error)
        } else {
            result = .success((documents ?? []).compactMap { document in
                QuestionList.fromFirestore(document.data, id: document.id)
            })
        }

        Task { @MainActor in completion(result) }
    }

    func createList(named name: String, ownerId: String) async throws -> String {
        let result = try await functions.httpsCallable("createQuestionList").call([
            "name": name,
        ])

        guard let data = result.data as? [String: Any],
              let listId = data["listId"] as? String,
              !listId.isEmpty
        else {
            throw QuestionListError.invalidResponse
        }

        return listId
    }

    func updateList(listId: String, name: String) async throws {
        _ = try await functions.httpsCallable("updateQuestionList").call([
            "listId": listId,
            "name": name,
        ])
    }

    func deleteList(listId: String) async throws {
        _ = try await functions.httpsCallable("deleteQuestionList").call([
            "listId": listId,
        ])
    }

    func setQuestion(_ questionId: String, in listId: String, isIncluded: Bool) async throws {
        _ = try await functions.httpsCallable("setQuestionInList").call([
            "listId": listId,
            "questionId": questionId,
            "isIncluded": isIncluded,
        ])
    }
}
