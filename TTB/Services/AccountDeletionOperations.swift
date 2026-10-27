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

/// Sendable copy of the fields account deletion reads from the live Firebase `User`.
/// The live `User` stays inside `LiveAccountDeletionOperations`, which looks it up again.
struct AccountDeletionUserSnapshot: AccountDeletionAuthUser, Equatable {
    let uid: String
    let isAnonymous: Bool
    let email: String?
}

extension AccountDeletionUserSnapshot {
    init(_ user: User) {
        self.init(uid: user.uid, isAnonymous: user.isAnonymous, email: user.email)
    }
}

protocol AccountDeletionAuthProviding: Sendable {
    func currentUser() -> (any AccountDeletionAuthUser)?
}

struct LiveAccountDeletionAuth: AccountDeletionAuthProviding {
    func currentUser() -> (any AccountDeletionAuthUser)? {
        guard let user = Auth.auth().currentUser else { return nil }
        return AccountDeletionUserSnapshot(user)
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

actor LiveAccountDeletionOperations: AccountDeletionOperations {
    private let fileManager: LocalFileManager
    private let batchWriteLimit = 400

    private let imageService: ImageService

    init(fileManager: LocalFileManager = .shared, imageService: ImageService = .shared) {
        self.fileManager = fileManager
        self.imageService = imageService
    }

    func reauthenticate(user: any AccountDeletionAuthUser, password: String?) async throws {
        let firebaseUser = try currentFirebaseUser(matching: user)
        try await AccountDeletionService.reauthenticatePermanentUser(
            user: firebaseUser,
            password: password
        )
    }

    func purgeAnswers() async throws {
        _ = try await Functions.europeWest1.httpsCallable("purgeOwnAnswersForAccountDeletion").call()
    }

    func favoriteQuestionReferences(for userId: String) async throws -> [String] {
        let snapshot = try await Firestore.firestore().collection("questions")
            .whereField("favoriteUserIds", arrayContains: userId)
            .getDocuments()
        return snapshot.documents.map(\.documentID)
    }

    func removeFavorites(userId: String, questionIds: [String]) async throws {
        guard !questionIds.isEmpty else { return }

        let questions = Firestore.firestore().collection("questions")
        let references = questionIds.map { questions.document($0) }
        try await updateDocumentBatches(references) { batch, reference in
            batch.updateData([
                "favoriteUserIds": FieldValue.arrayRemove([userId])
            ], forDocument: reference)
        }
    }

    func deleteAIDocuments(userId: String) async throws {
        let userRef = Firestore.firestore().collection("users").document(userId)

        let aiQueries = try await userRef.collection("aiQueries").getDocuments()
        try await deleteDocumentBatches(aiQueries.documents.map(\.reference))

        try await userRef.collection("aiUsage").document("stats").delete()
    }

    func deleteProfileAssets(userId: String) async throws {
        // Read before the delete: the cache key is the download URL, which only the user document
        // holds. A failed read only means the photo stays in memory until the app quits.
        let snapshot = try? await Firestore.firestore().collection("users").document(userId).getDocument()
        let downloadURL = snapshot?.data()?["profileImageURL"] as? String
        try await ignoreMissingStorageObject {
            try await imageService.deleteProfileImage(userId: userId)
        }
        await evictCachedProfilePhoto(downloadURL: downloadURL)
        fileManager.deleteImage(name: "profile_\(userId)")
    }

    /// Drops the profile photo from the in-memory cache once its Storage file is gone (#85).
    /// Internal, not private, so a test can run it against a fresh `ImageService`.
    func evictCachedProfilePhoto(downloadURL: String?) async {
        guard let downloadURL, !downloadURL.isEmpty else { return }
        await imageService.evictProfileImage(downloadURL: downloadURL)
    }

    func deleteUserDocument(userId: String) async throws {
        try await Firestore.firestore().collection("users").document(userId).delete()
    }

    func deleteAuthUser(_ user: any AccountDeletionAuthUser) async throws {
        let firebaseUser = try currentFirebaseUser(matching: user)
        try await firebaseUser.deleteAsync()
    }

    private func currentFirebaseUser(matching snapshot: any AccountDeletionAuthUser) throws -> User {
        let firebaseUser = Auth.auth().currentUser
        try Self.requireSameUser(currentUserID: firebaseUser?.uid, expectedUserID: snapshot.uid)
        guard let firebaseUser else { throw AccountDeletionError.unauthenticated }
        return firebaseUser
    }

    /// Fails unless the signed-in user is the one the caller read earlier (TriQ#17): the live `User`
    /// is looked up again here, and the account may have changed in between. Pure, so a test needs
    /// no Firebase.
    static func requireSameUser(currentUserID: String?, expectedUserID: String) throws {
        guard let currentUserID, currentUserID == expectedUserID else {
            throw AccountDeletionError.unauthenticated
        }
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
            let batch = Firestore.firestore().batch()

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
        } catch where ImageService.isMissingStorageObject(error) {
            return
        }
    }
}

protocol AccountDeletionPerforming: Sendable {
    func deleteCurrentAccount(password: String?) async throws
}

extension AccountDeletionService: AccountDeletionPerforming {}
