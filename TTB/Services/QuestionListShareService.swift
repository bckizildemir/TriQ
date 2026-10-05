import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation
import os

actor QuestionListShareService {
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "europe-west1")
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "QuestionListShareService")

    enum ShareError: LocalizedError {
        case invalidResponse
        case missingUser
        case ownerCannotAccept
        case shareNotAcceptingRecipients
        case localShareUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Question list share returned an invalid response."
            case .missingUser:
                return "You need a permanent account to use shared question lists."
            case .ownerCannotAccept:
                return "Owners cannot accept their own share link."
            case .shareNotAcceptingRecipients:
                return "This share link is not accepting recipients."
            case .localShareUnavailable:
                return "Local shared list fixture is unavailable."
            }
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        if let shareError = error as? ShareError,
           let description = shareError.errorDescription {
            return description
        }

        let nsError = error as NSError
        let searchableMessage = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if searchableMessage.contains("owners cannot accept") {
            return "You cannot accept your own shared list link."
        }

        if searchableMessage.contains("local shared list fixture is unavailable") {
            return "Local shared list fixture is unavailable. Seed a local share before accepting."
        }

        if searchableMessage.contains("permanent account")
            || searchableMessage.contains("permission-denied")
            || searchableMessage.contains("permission denied") {
            return "Sign in with a permanent account to accept shared question lists."
        }

        if searchableMessage.contains("authentication is required")
            || searchableMessage.contains("unauthenticated") {
            return "Sign in to accept this shared list."
        }

        if searchableMessage.contains("recipient limit")
            || searchableMessage.contains("resource-exhausted")
            || searchableMessage.contains("resource exhausted") {
            return "This shared list has reached its recipient limit."
        }

        if searchableMessage.contains("not accepting recipients")
            || searchableMessage.contains("not-found")
            || searchableMessage.contains("not found")
            || searchableMessage.contains("failed-precondition")
            || searchableMessage.contains("failed precondition") {
            return "This shared list link is no longer accepting recipients."
        }

        if nsError.domain == NSURLErrorDomain {
            return "The shared list could not be reached. Check your connection and try again."
        }

        return error.localizedDescription
    }

    func setupOwnedSharesListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShare], Error>) -> Void
    ) -> ListenerRegistration {
        db.collection("questionListShares")
            .whereField("ownerId", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [logger] snapshot, error in
                if let error {
                    logger.error("Owned question list shares listener failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                let shares = snapshot?.documents.compactMap { document in
                    QuestionListShare.fromFirestore(document.data(), id: document.documentID)
                } ?? []
                completion(.success(shares))
            }
    }

    func setupAcceptedRecipientsListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShareRecipient], Error>) -> Void
    ) -> ListenerRegistration {
        db.collectionGroup("recipients")
            .whereField("recipientId", isEqualTo: userId)
            .whereField("status", isEqualTo: QuestionListShareStatus.accepted.rawValue)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [logger] snapshot, error in
                if let error {
                    logger.error("Accepted question list shares listener failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                let recipients = snapshot?.documents.compactMap { document -> QuestionListShareRecipient? in
                    guard let shareId = document.reference.parent.parent?.documentID else { return nil }
                    return QuestionListShareRecipient.fromFirestore(
                        document.data(),
                        id: document.documentID,
                        shareId: shareId
                    )
                } ?? []
                completion(.success(recipients))
            }
    }

    func fetchShare(shareId: String) async throws -> QuestionListShare {
        let snapshot = try await db.collection("questionListShares").document(shareId).getDocument()
        guard let data = snapshot.data(),
              let share = QuestionListShare.fromFirestore(data, id: snapshot.documentID)
        else {
            throw ShareError.invalidResponse
        }
        return share
    }

    func fetchRecipients(shareId: String) async throws -> [QuestionListShareRecipient] {
        let snapshot = try await db.collection("questionListShares")
            .document(shareId)
            .collection("recipients")
            .getDocuments()

        return snapshot.documents.compactMap { document in
            QuestionListShareRecipient.fromFirestore(
                document.data(),
                id: document.documentID,
                shareId: shareId
            )
        }
    }

    func fetchAcceptedShare(shareId: String, recipientId: String) async throws -> AcceptedQuestionListShare {
        async let share = fetchShare(shareId: shareId)
        async let recipient = fetchRecipient(shareId: shareId, recipientId: recipientId)
        return try await AcceptedQuestionListShare(share: share, recipient: recipient)
    }

    func fetchRecipient(shareId: String, recipientId: String) async throws -> QuestionListShareRecipient {
        let snapshot = try await db.collection("questionListShares")
            .document(shareId)
            .collection("recipients")
            .document(recipientId)
            .getDocument()
        guard let data = snapshot.data(),
              let recipient = QuestionListShareRecipient.fromFirestore(
                data,
                id: snapshot.documentID,
                shareId: shareId
              )
        else {
            throw ShareError.invalidResponse
        }
        return recipient
    }

    func createShare(listId: String, includeOwnerAnswers: Bool) async throws -> QuestionListShareCreationResult {
        let result = try await functions.httpsCallable("createQuestionListShare").call([
            "listId": listId,
            "includeOwnerAnswers": includeOwnerAnswers,
        ])
        return try Self.creationResult(from: result.data)
    }

    func previewShare(shareCode: String) async throws -> QuestionListSharePreview {
        let result = try await functions.httpsCallable("previewQuestionListShare").call([
            "shareCode": shareCode,
        ])
        guard let data = result.data as? [String: Any],
              let shareId = data["shareId"] as? String,
              let shareCode = data["shareCode"] as? String,
              let listName = data["listName"] as? String,
              let ownerDisplayName = data["ownerDisplayName"] as? String,
              let questionCount = data["questionCount"] as? Int,
              let includeOwnerAnswers = data["includeOwnerAnswers"] as? Bool,
              let recipientCap = data["recipientCap"] as? Int,
              let acceptedRecipientCount = data["acceptedRecipientCount"] as? Int,
              let isAccepted = data["isAccepted"] as? Bool
        else {
            throw ShareError.invalidResponse
        }

        return QuestionListSharePreview(
            shareId: shareId,
            shareCode: shareCode,
            listName: listName,
            ownerDisplayName: ownerDisplayName,
            questionCount: questionCount,
            includeOwnerAnswers: includeOwnerAnswers,
            recipientCap: recipientCap,
            acceptedRecipientCount: acceptedRecipientCount,
            isAccepted: isAccepted
        )
    }

    // Ignores `actingAs`: Firebase Auth alone determines who's accepting server-side.
    @discardableResult
    func acceptShare(shareCode: String, actingAs _: String) async throws -> String {
        let result = try await functions.httpsCallable("acceptQuestionListShare").call([
            "shareCode": shareCode,
        ])
        guard let data = result.data as? [String: Any],
              let shareId = data["shareId"] as? String
        else {
            throw ShareError.invalidResponse
        }
        return shareId
    }

    func disableShare(shareId: String) async throws {
        _ = try await functions.httpsCallable("disableQuestionListShare").call([
            "shareId": shareId,
        ])
    }

    func regenerateLink(shareId: String) async throws -> QuestionListShareCreationResult {
        let result = try await functions.httpsCallable("regenerateQuestionListShareLink").call([
            "shareId": shareId,
        ])
        return try Self.creationResult(from: result.data)
    }

    func revokeShare(shareId: String) async throws {
        _ = try await functions.httpsCallable("revokeQuestionListShare").call([
            "shareId": shareId,
        ])
    }

    func leaveShare(shareId: String) async throws {
        _ = try await functions.httpsCallable("leaveQuestionListShare").call([
            "shareId": shareId,
        ])
    }

    func sendReply(shareId: String) async throws {
        _ = try await functions.httpsCallable("sendQuestionListShareReply").call([
            "shareId": shareId,
        ])
    }

    func markReplySeen(shareId: String, recipientId: String) async throws {
        _ = try await functions.httpsCallable("markQuestionListShareReplySeen").call([
            "shareId": shareId,
            "recipientId": recipientId,
        ])
    }

    private static func creationResult(from value: Any) throws -> QuestionListShareCreationResult {
        guard let data = value as? [String: Any],
              let shareId = data["shareId"] as? String,
              let shareCode = data["shareCode"] as? String,
              let shareURLString = data["shareURL"] as? String,
              let shareURL = URL(string: shareURLString)
        else {
            throw ShareError.invalidResponse
        }

        return QuestionListShareCreationResult(
            shareId: shareId,
            shareCode: shareCode,
            shareURL: shareURL
        )
    }
}

// MARK: - QuestionListShareServicing

/// The live adapter at the question-list-share seam. Method-for-method with the actor's own
/// surface, except the two listener setups, which are renamed so the protocol never has to name
/// `ListenerRegistration`.
extension QuestionListShareService: QuestionListShareServicing {
    func ownedSharesListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShare], Error>) -> Void
    ) -> QuestionListShareListenerHandle {
        FirestoreQuestionListShareListenerHandle(
            registration: setupOwnedSharesListener(userId: userId, completion: completion)
        )
    }

    func acceptedRecipientsListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShareRecipient], Error>) -> Void
    ) -> QuestionListShareListenerHandle {
        FirestoreQuestionListShareListenerHandle(
            registration: setupAcceptedRecipientsListener(userId: userId, completion: completion)
        )
    }
}

private struct FirestoreQuestionListShareListenerHandle: QuestionListShareListenerHandle {
    let registration: ListenerRegistration

    func remove() {
        registration.remove()
    }
}
