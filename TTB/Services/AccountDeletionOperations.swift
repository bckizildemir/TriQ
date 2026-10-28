import FirebaseAuth
import FirebaseFunctions
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

/// What the `deleteOwnAccountData` callable reports back that the client uses.
struct AccountDeletionSummary: Equatable, Sendable {
    /// The profile photo's download URL the server read before it deleted the user document, so
    /// the client can drop the in-memory copy cached under it (#85).
    let profileImageURL: String?
}

protocol AccountDeletionOperations: Sendable {
    func reauthenticate(user: any AccountDeletionAuthUser, password: String?) async throws
    /// Deletes all of the user's data and then the Firebase Auth user on the server, in one
    /// callable (TriQ#88). Safe to call again.
    func deleteAccountData() async throws -> AccountDeletionSummary
    func deleteLocalProfileImage(userId: String) async
    /// Ends the local session after the server deleted the account.
    func signOut() async
}

actor LiveAccountDeletionOperations: AccountDeletionOperations {
    private let fileManager: LocalFileManager

    init(fileManager: LocalFileManager = .shared) {
        self.fileManager = fileManager
    }

    func reauthenticate(user: any AccountDeletionAuthUser, password: String?) async throws {
        let firebaseUser = try currentFirebaseUser(matching: user)
        do {
            try await AccountDeletionService.reauthenticatePermanentUser(
                user: firebaseUser,
                password: password
            )
        } catch {
            throw Self.deletionError(forReauthenticationError: error)
        }
    }

    /// The server deletes data and the Auth user in one callable and may take up to 300 s
    /// (`timeoutSeconds` in `functions/index.js`). The SDK default is 70 s, so the client waits a
    /// little longer than the server, or a slow success would show as a failure.
    static let callableTimeout: TimeInterval = 310

    func deleteAccountData() async throws -> AccountDeletionSummary {
        let data: Any
        do {
            // The one line no test reaches: it needs the live callable.
            let callable = Functions.europeWest1.httpsCallable("deleteOwnAccountData")
            callable.timeoutInterval = Self.callableTimeout
            data = try await callable.call().data
        } catch {
            throw Self.deletionError(forCallableError: error)
        }
        return try Self.summary(fromCallableData: data)
    }

    func deleteLocalProfileImage(userId: String) async {
        fileManager.deleteImage(name: "profile_\(userId)")
    }

    func signOut() async {
        // The account no longer exists on the server, so a failed local sign-out has nothing to
        // retry: the next token refresh fails and the auth listener signs the user out then.
        try? Auth.auth().signOut()
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

    /// Maps a `deleteOwnAccountData` failure to an error with a localized message, so the user never
    /// sees the raw SDK text. Pure, so a test needs no Firebase.
    static func deletionError(forCallableError error: any Error) -> AccountDeletionError {
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain,
           nsError.code == FunctionsErrorCode.unauthenticated.rawValue {
            // The user passed reauthentication a moment ago, so the Auth user is gone: an earlier
            // call deleted it and its response was lost.
            return .accountAlreadyDeleted
        }
        return .dataDeletionFailed
    }

    /// Maps a reauthentication failure. An Auth error that says the user no longer exists means an
    /// earlier attempt already deleted the account; every other error (wrong password, network)
    /// passes through unchanged. Pure, so a test needs no Firebase.
    static func deletionError(forReauthenticationError error: any Error) -> any Error {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else { return error }
        switch AuthErrorCode(rawValue: nsError.code) {
        case .userNotFound, .userTokenExpired, .invalidUserToken:
            return AccountDeletionError.accountAlreadyDeleted
        default:
            return error
        }
    }

    /// Checks the callable's response. Anything but `success: true` counts as a failure, so the
    /// app keeps the session and offers a retry while the account may still exist. Pure, so a test needs no Firebase.
    static func summary(fromCallableData data: Any) throws -> AccountDeletionSummary {
        guard let payload = data as? [String: Any], payload["success"] as? Bool == true else {
            throw AccountDeletionError.dataDeletionFailed
        }
        let url = (payload["profileImageURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return AccountDeletionSummary(profileImageURL: url)
    }
}

protocol AccountDeletionPerforming: Sendable {
    func deleteCurrentAccount(password: String?) async throws
}

extension AccountDeletionService: AccountDeletionPerforming {}
