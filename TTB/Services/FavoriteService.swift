import Foundation
import FirebaseFirestore
import FirebaseFunctions
import os
import Synchronization

actor FavoriteService {
    private let functions = Functions.functions(region: "europe-west1")
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "FavoriteService")
    
    enum FavoriteError: LocalizedError {
        case invalidUserId
        case documentNotFound
        case transactionFailed
        case unknown(Error)

        var errorDescription: String? {
            switch self {
            case .invalidUserId:
                return "Favorite update requires a signed-in user."
            case .documentNotFound:
                return "Question not found."
            case .transactionFailed:
                return "Favorite update failed."
            case .unknown(let error):
                return error.localizedDescription
            }
        }
    }
    
    /// Returns a `sending` registration so the caller can hand it to a `Sendable` handle. That only
    /// holds because `Firestore` is fetched here: a registration built from a stored `Firestore`
    /// would join the actor's region and could not leave it.
    func setupFavoritesListener(
        userId: String,
        completion: @escaping @MainActor @Sendable (Result<[Question], Error>) -> Void
    ) -> sending ListenerRegistration {
        let questions = Firestore.firestore().collection("questions")
        guard !userId.isEmpty else {
            Task { @MainActor in completion(.failure(FavoriteError.invalidUserId)) }
            return questions.addSnapshotListener { _, _ in }
        }

        return questions
            .whereField("favoriteUserIds", arrayContains: userId)
            .addSnapshotListener { snapshot, error in
                let result: Result<[Question], Error>
                if let error = error {
                    result = .failure(FavoriteError.unknown(error))
                } else {
                    let documents = snapshot?.documents ?? []
                    result = .success(documents.compactMap { document in
                        Question.fromFirestore(document.data(), id: document.documentID)
                    })
                }

                Task { @MainActor in completion(result) }
            }
    }
    
    func toggleFavorite(
        questionId: String,
        userId: String,
        currentFavoriteState: Bool? = nil
    ) async throws -> Bool {
        guard !userId.isEmpty else {
            throw FavoriteError.invalidUserId
        }

        let result = try await functions.httpsCallable("toggleQuestionFavorite").call([
            "questionId": questionId
        ])
        guard let data = result.data as? [String: Any] else {
            throw FavoriteError.transactionFailed
        }

        do {
            let isFavorite = try FavoriteToggleResponse.resolve(
                data: data,
                currentFavoriteState: currentFavoriteState
            )
            logger.debug("toggleQuestionFavorite returned isFavorite=\(isFavorite) for question \(questionId)")
            return isFavorite
        } catch FavoriteToggleResponseError.invalidPayload {
            logger.error("toggleQuestionFavorite missing isFavorite for question \(questionId)")
            throw FavoriteError.transactionFailed
        }
    }

    func addFavorites(questionIds: [String]) async throws -> Set<String> {
        guard !questionIds.isEmpty else { return [] }

        // A client write to `favoriteUserIds` is rejected by firestore.rules, which lets a
        // non-admin update only `creatorUsername` on a question. The callable is the only path.
        let result = try await functions.httpsCallable("addQuestionFavorites").call([
            "questionIds": questionIds
        ])
        guard let data = result.data as? [String: Any] else {
            throw FavoriteError.transactionFailed
        }
        do {
            return try FavoriteMigrationResponse.unavailableQuestionIDs(
                from: data,
                requestedQuestionIDs: questionIds
            )
        } catch FavoriteMigrationResponseError.invalidPayload {
            logger.error("addQuestionFavorites returned an invalid migration response")
            throw FavoriteError.transactionFailed
        }
    }
}

// MARK: - FavoriteServicing

/// The live adapter at the favorites seam. Method-for-method with the actor's own surface — the
/// renaming exists so the protocol reads as a capability rather than as this class's history.
extension FavoriteService: FavoriteServicing {
    func favoritesListener(
        userId: String,
        onChange: @escaping @MainActor @Sendable (Result<[Question], Error>) -> Void
    ) -> FavoriteListenerHandle {
        FirestoreFavoriteListenerHandle(
            registration: setupFavoritesListener(userId: userId, completion: onChange)
        )
    }

    func toggle(questionId: String, userId: String, currentState: Bool?) async throws -> Bool {
        try await toggleFavorite(
            questionId: questionId,
            userId: userId,
            currentFavoriteState: currentState
        )
    }
}

/// Owns the Firebase registration, which is not `Sendable`, behind a lock, so the handle can
/// cross from this actor to the main-actor store. The first `cancel()` removes the registration;
/// later calls do nothing.
final class FirestoreFavoriteListenerHandle: FavoriteListenerHandle {
    private let registration: Mutex<ListenerRegistration?>

    init(registration: sending ListenerRegistration) {
        self.registration = Mutex(registration)
    }

    func cancel() {
        registration.withLock { registration in
            registration?.remove()
            registration = nil
        }
    }
}
