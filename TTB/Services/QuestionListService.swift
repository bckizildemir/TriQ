import FirebaseFirestore
import FirebaseFunctions
import Foundation
import os

protocol QuestionListServicing: Sendable {
    func setupQuestionListsListener(
        userId: String,
        completion: @escaping (Result<[QuestionList], Error>) -> Void
    ) async -> ListenerRegistration
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
    private let db = Firestore.firestore()
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

    func setupQuestionListsListener(
        userId: String,
        completion: @escaping (Result<[QuestionList], Error>) -> Void
    ) async -> ListenerRegistration {
        db.collection("questionLists")
            .whereField("ownerId", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [logger] snapshot, error in
                if let error {
                    logger.error("Question lists listener error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                let lists = snapshot?.documents.compactMap { document in
                    QuestionList.fromFirestore(document.data(), id: document.documentID)
                } ?? []
                completion(.success(lists))
            }
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
