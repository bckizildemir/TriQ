import FirebaseAuth
import FirebaseFirestore
import Foundation
import os

struct UserProfileSnapshot {
    let username: String?
    let email: String?
    let isAnonymous: Bool?
}

protocol AuthModelUser: AnyObject {
    var uid: String { get }
    var isAnonymous: Bool { get }
    var email: String? { get }
    nonisolated(nonsending) func deleteAsync() async throws
    func linkAccount(with credential: AuthCredential) async throws -> AuthModelUser
    nonisolated(nonsending) func forceRefreshIDToken() async throws
}

extension User: AuthModelUser {
    func linkAccount(with credential: AuthCredential) async throws -> AuthModelUser {
        let result = try await link(with: credential)
        return result.user
    }
}

typealias AuthStateListenerHandle = AuthStateDidChangeListenerHandle

/// Main-actor isolated because every caller is the `@MainActor` `AuthModel` and the requirements
/// read the provider's current user synchronously. `AuthModel`'s `deinit` is `isolated`, so
/// `removeStateDidChangeListener` needs no `nonisolated` exception.
@MainActor
protocol AuthModelAuthProviding: Sendable {
    var currentUser: AuthModelUser? { get }
    func createUser(withEmail email: String, password: String) async throws -> AuthModelUser
    func signIn(withEmail email: String, password: String) async throws
    func signOut() throws
    func signInAnonymously() async throws -> AuthModelUser
    func sendPasswordReset(withEmail email: String) async throws
    func addStateDidChangeListener(
        _ listener: @escaping (AuthModelUser?) -> Void
    ) -> AuthStateListenerHandle?
    func removeStateDidChangeListener(_ handle: AuthStateListenerHandle?)
}

protocol UsernameServiceProtocol: Sendable {
    func claimUsername(
        _ username: String,
        email: String?,
        isAnonymous: Bool?
    ) async throws -> ClaimedUsername
    func resolveEmail(for username: String) async throws -> String
    func releaseUsername(
        _ username: String,
        restoreUsername: String?,
        restoreEmail: String?,
        restoreIsAnonymous: Bool?
    ) async
}

extension UsernameService: UsernameServiceProtocol {}

@MainActor
protocol AuthUserDocumentManaging: Sendable {
    func ensureExists(for user: AuthModelUser) async
    func profileSnapshot(userId: String) async throws -> UserProfileSnapshot?
    func deleteUserAndAuth(user: AuthModelUser) async
}

protocol BadgeProgressBackfilling: Sendable {
    func backfillBadgeProgressIfNeeded() async
}

extension QuestionService: BadgeProgressBackfilling {}

struct AuthModelDependencies {
    let auth: AuthModelAuthProviding
    let usernameService: UsernameServiceProtocol
    let userDocumentManager: AuthUserDocumentManaging
    let accountDeletionService: AccountDeletionPerforming
    let badgeBackfillService: BadgeProgressBackfilling

    @MainActor
    static var live: AuthModelDependencies {
        AuthModelDependencies(
            auth: LiveAuthModelAuthProvider(),
            usernameService: UsernameService(),
            userDocumentManager: LiveAuthUserDocumentManager(),
            accountDeletionService: AccountDeletionService(),
            badgeBackfillService: QuestionService()
        )
    }
}

final class LiveAuthModelAuthProvider: AuthModelAuthProviding {
    // Computed, not stored: the provider keeps no non-Sendable Firebase state, so it
    // is Sendable. The SDK returns the same cached instance on every call.
    private nonisolated var auth: Auth { Auth.auth() }

    var currentUser: AuthModelUser? {
        auth.currentUser
    }

    func createUser(withEmail email: String, password: String) async throws -> AuthModelUser {
        let result = try await auth.createUser(withEmail: email, password: password)
        return result.user
    }

    func signIn(withEmail email: String, password: String) async throws {
        _ = try await auth.signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try auth.signOut()
    }

    func signInAnonymously() async throws -> AuthModelUser {
        let result = try await auth.signInAnonymously()
        return result.user
    }

    func sendPasswordReset(withEmail email: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            auth.sendPasswordReset(withEmail: email) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func addStateDidChangeListener(
        _ listener: @escaping (AuthModelUser?) -> Void
    ) -> AuthStateListenerHandle? {
        let handle = auth.addStateDidChangeListener { _, user in
            listener(user)
        }
        return handle
    }

    func removeStateDidChangeListener(_ handle: AuthStateListenerHandle?) {
        guard let handle else { return }
        auth.removeStateDidChangeListener(handle)
    }
}

final class LiveAuthUserDocumentManager: AuthUserDocumentManaging {
    /// What `ensureExists` writes for a user document, decided from the stored data alone.
    nonisolated enum UserDocumentWrite {
        case create
        case patch([String: Any])
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "LiveAuthUserDocumentManager")

    /// Pure decision: an absent document is created; a present one gets its missing fields.
    /// `updatedAt` is a server timestamp in every patch; `createdAt` is never in a patch.
    nonisolated static func writePlan(existing data: [String: Any]?, isAnonymous: Bool) -> UserDocumentWrite {
        guard let data else { return .create }
        var patch: [String: Any] = [:]
        if data["dailyAnswers"] == nil { patch["dailyAnswers"] = 0 }
        if data["weeklyAnswers"] == nil { patch["weeklyAnswers"] = 0 }
        if data["totalAnswered"] == nil { patch["totalAnswered"] = 0 }
        if data["completedQuestionIds"] == nil { patch["completedQuestionIds"] = [String]() }
        if data["categoryAnswers"] == nil { patch["categoryAnswers"] = [String: Int]() }
        if data["currentStreak"] == nil { patch["currentStreak"] = 0 }
        if data["unlockedBadges"] == nil { patch["unlockedBadges"] = [String]() }
        if data["badgeProgress"] == nil { patch["badgeProgress"] = [String: Double]() }
        if data["isAnonymous"] == nil { patch["isAnonymous"] = isAnonymous }
        if data["usernameNormalized"] == nil,
            let existingUsername = data["username"] as? String
        {
            patch["usernameNormalized"] = AuthModel.normalizedUsername(existingUsername)
        }
        patch["updatedAt"] = FieldValue.serverTimestamp()
        return .patch(patch)
    }

    func ensureExists(for user: AuthModelUser) async {
        let defaultData = defaultUserData(for: user)
        let isAnonymous = user.isAnonymous
        let userId = user.uid
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Self.runEnsureTransaction(
                    userId: userId, defaultData: defaultData, isAnonymous: isAnonymous
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            logger.error(
                "ensureExists failed for \(user.uid, privacy: .private): \(error.localizedDescription)")
        }
    }

    /// Read and write in one transaction: two racing callers cannot both create. Nonisolated
    /// because Firestore runs the update block on its own queue, not on the main actor.
    private nonisolated static func runEnsureTransaction(
        userId: String,
        defaultData: [String: Any],
        isAnonymous: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        db.runTransaction(
            { transaction, errorPointer in
                do {
                    let snapshot = try transaction.getDocument(userRef)
                    let existing: [String: Any]? = snapshot.exists ? (snapshot.data() ?? [:]) : nil
                    switch writePlan(existing: existing, isAnonymous: isAnonymous) {
                    case .create:
                        transaction.setData(defaultData, forDocument: userRef)
                    case .patch(let patch):
                        transaction.setData(patch, forDocument: userRef, merge: true)
                    }
                } catch {
                    errorPointer?.pointee = error as NSError
                }
                return nil
            },
            completion: { _, error in completion(error) })
    }

    func profileSnapshot(userId: String) async throws -> UserProfileSnapshot? {
        let db = Firestore.firestore()
        let snapshot = try await db.collection("users").document(userId).getDocument()
        guard let data = snapshot.data() else { return nil }
        return UserProfileSnapshot(
            username: data["username"] as? String,
            email: data["email"] as? String,
            isAnonymous: data["isAnonymous"] as? Bool
        )
    }

    func deleteUserAndAuth(user: AuthModelUser) async {
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(user.uid).delete()
            try await user.deleteAsync()
        } catch {
            // AuthModel logs failures at call site when needed.
        }
    }

    private func defaultUserData(for user: AuthModelUser) -> [String: Any] {
        let fallbackName = user.isAnonymous
            ? String(localized: "auth.placeholder.guestUser")
            : String(localized: "auth.placeholder.user")
        return [
            "username": fallbackName,
            "usernameNormalized": AuthModel.normalizedUsername(fallbackName),
            "email": user.email ?? "",
            "isAnonymous": user.isAnonymous,
            "dailyAnswers": 0,
            "weeklyAnswers": 0,
            "totalAnswered": 0,
            "completedQuestionIds": [String](),
            "categoryAnswers": [String: Int](),
            "currentStreak": 0,
            "unlockedBadges": [String](),
            "badgeProgress": [String: Double](),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }
}
