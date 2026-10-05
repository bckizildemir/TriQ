import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

protocol AccountDeletionAuthUser: Sendable {
    var uid: String { get }
    var isAnonymous: Bool { get }
    var email: String? { get }
}

extension User: AccountDeletionAuthUser {}

protocol AccountDeletionAuthProviding: Sendable {
    func currentUser() -> (any AccountDeletionAuthUser)?
}

struct LiveAccountDeletionAuth: AccountDeletionAuthProviding {
    func currentUser() -> (any AccountDeletionAuthUser)? {
        Auth.auth().currentUser
    }
}

protocol AccountDeletionOperations: Sendable {
    func reauthenticate(user: any AccountDeletionAuthUser, password: String?) async throws
    func purgeAnswers() async throws
    func favoriteQuestionReferences(for userId: String) async throws -> [String]
    func removeFavorites(userId: String, questionIds: [String]) async throws
    func deleteAIDocuments(userId: String) async throws
    func deleteProfileAssets(userId: String) async throws
    func deleteUserDocument(userId: String) async throws
    func deleteAuthUser(_ user: any AccountDeletionAuthUser) async throws
}

struct LiveAccountDeletionOperations: AccountDeletionOperations {
    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "europe-west1")
    private let fileManager: LocalFileManager
    private let batchWriteLimit = 400

    init(fileManager: LocalFileManager = .shared) {
        self.fileManager = fileManager
    }

    func reauthenticate(user: any AccountDeletionAuthUser, password: String?) async throws {
        guard let firebaseUser = user as? User else {
            throw AccountDeletionError.unauthenticated
        }
        try await AccountDeletionService.reauthenticatePermanentUser(
            user: firebaseUser,
            password: password
        )
    }

    func purgeAnswers() async throws {
        _ = try await functions.httpsCallable("purgeOwnAnswersForAccountDeletion").call()
    }

    func favoriteQuestionReferences(for userId: String) async throws -> [String] {
        let snapshot = try await db.collection("questions")
            .whereField("favoriteUserIds", arrayContains: userId)
            .getDocuments()
        return snapshot.documents.map(\.documentID)
    }

    func removeFavorites(userId: String, questionIds: [String]) async throws {
        guard !questionIds.isEmpty else { return }

        let references = questionIds.map { db.collection("questions").document($0) }
        try await updateDocumentBatches(references) { batch, reference in
            batch.updateData([
                "favoriteUserIds": FieldValue.arrayRemove([userId])
            ], forDocument: reference)
        }
    }

    func deleteAIDocuments(userId: String) async throws {
        let userRef = db.collection("users").document(userId)

        let aiQueries = try await userRef.collection("aiQueries").getDocuments()
        try await deleteDocumentBatches(aiQueries.documents.map(\.reference))

        try await userRef.collection("aiUsage").document("stats").delete()
    }

    func deleteProfileAssets(userId: String) async throws {
        try await ignoreMissingStorageObject {
            try await ImageService.shared.deleteProfileImage()
        }
        fileManager.deleteImage(name: "profile_\(userId)")
    }

    func deleteUserDocument(userId: String) async throws {
        try await db.collection("users").document(userId).delete()
    }

    func deleteAuthUser(_ user: any AccountDeletionAuthUser) async throws {
        guard let firebaseUser = user as? User else {
            throw AccountDeletionError.unauthenticated
        }
        try await firebaseUser.deleteAsync()
    }

    private func updateDocumentBatches(
        _ references: [DocumentReference],
        operation: (WriteBatch, DocumentReference) -> Void
    ) async throws {
        guard !references.isEmpty else { return }

        for range in FirestoreBatchPlanner.ranges(
            itemCount: references.count,
            limit: batchWriteLimit
        ) {
            let batch = db.batch()

            for reference in references[range] {
                operation(batch, reference)
            }

            try await batch.commit()
        }
    }

    private func deleteDocumentBatches(_ references: [DocumentReference]) async throws {
        try await updateDocumentBatches(references) { batch, reference in
            batch.deleteDocument(reference)
        }
    }

    private func ignoreMissingStorageObject(_ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch let error as NSError where error.domain == StorageErrorDomain
            && error.code == StorageErrorCode.objectNotFound.rawValue {
            return
        } catch let imageError as ImageServiceError {
            switch imageError {
            case .deleteFailed(let error as NSError)
                where error.domain == StorageErrorDomain
                && error.code == StorageErrorCode.objectNotFound.rawValue:
                return
            default:
                throw imageError
            }
        } catch {
            throw error
        }
    }
}

extension User {
    func reauthenticateAsync(with credential: AuthCredential) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reauthenticate(with: credential) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func deleteAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

protocol AccountDeletionPerforming: Sendable {
    func deleteCurrentAccount(password: String?) async throws
}

extension AccountDeletionService: AccountDeletionPerforming {}
