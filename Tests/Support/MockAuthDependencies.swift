import FirebaseAuth
import Foundation
@testable import TTB

final class MockAuthUser: AuthModelUser {
    let uid: String
    let isAnonymous: Bool
    let email: String?
    var linkShouldFail = false
    private(set) var deleteCalled = false

    init(uid: String = UUID().uuidString, isAnonymous: Bool = false, email: String? = nil) {
        self.uid = uid
        self.isAnonymous = isAnonymous
        self.email = email
    }

    func delete() async throws {
        deleteCalled = true
    }

    func link(with credential: AuthCredential) async throws -> AuthModelUser {
        _ = credential
        if linkShouldFail {
            throw NSError(domain: "MockAuthUser", code: 1, userInfo: nil)
        }
        return MockAuthUser(uid: uid, isAnonymous: false, email: email)
    }

    func forceRefreshIDToken() async throws {}
}

final class MockAuthProvider: AuthModelAuthProviding {
    var currentUserValue: AuthModelUser?
    private(set) var createUserCalls: [(email: String, password: String)] = []
    private(set) var signInCalls: [(email: String, password: String)] = []
    private(set) var signOutCalled = false
    var createUserError: Error?
    var signInError: Error?
    private var authStateListener: ((AuthModelUser?) -> Void)?

    var currentUser: AuthModelUser? {
        currentUserValue
    }

    func createUser(withEmail email: String, password: String) async throws -> AuthModelUser {
        createUserCalls.append((email, password))
        if let createUserError { throw createUserError }
        let user = MockAuthUser(uid: "created-user", isAnonymous: false, email: email)
        currentUserValue = user
        return user
    }

    func signIn(withEmail email: String, password: String) async throws {
        signInCalls.append((email, password))
        if let signInError { throw signInError }
    }

    func signOut() throws {
        signOutCalled = true
        currentUserValue = nil
    }

    func signInAnonymously() async throws -> AuthModelUser {
        let user = MockAuthUser(uid: "anon-user", isAnonymous: true, email: nil)
        currentUserValue = user
        return user
    }

    func sendPasswordReset(withEmail email: String) async throws {
        _ = email
    }

    func addStateDidChangeListener(
        _ listener: @escaping (AuthModelUser?) -> Void
    ) -> AuthStateListenerHandle? {
        authStateListener = listener
        return nil
    }

    nonisolated func removeStateDidChangeListener(_ handle: AuthStateListenerHandle?) {
        _ = handle
    }

    func emitAuthState(_ user: AuthModelUser?) {
        currentUserValue = user
        authStateListener?(user)
    }
}

@MainActor
final class MockUsernameService: UsernameServiceProtocol {
    private(set) var claimCalls: [(username: String, email: String?, isAnonymous: Bool?)] = []
    private(set) var releaseCalls: [(username: String, restoreUsername: String?, restoreEmail: String?, restoreIsAnonymous: Bool?)] = []
    private(set) var resolveEmailCalls: [String] = []
    var claimShouldFail = false
    var claimError: Error = UsernameServiceError.usernameAlreadyExists
    var resolveEmailResult = "resolved@example.com"

    func claimUsername(
        _ username: String,
        email: String?,
        isAnonymous: Bool?
    ) async throws -> ClaimedUsername {
        claimCalls.append((username, email, isAnonymous))
        if claimShouldFail {
            throw claimError
        }
        return ClaimedUsername(username: username, usernameNormalized: username.lowercased())
    }

    func resolveEmail(for username: String) async throws -> String {
        resolveEmailCalls.append(username)
        return resolveEmailResult
    }

    func releaseUsername(
        _ username: String,
        restoreUsername: String?,
        restoreEmail: String?,
        restoreIsAnonymous: Bool?
    ) async {
        releaseCalls.append((username, restoreUsername, restoreEmail, restoreIsAnonymous))
    }
}

@MainActor
final class MockUserDocumentManager: AuthUserDocumentManaging {
    private(set) var ensuredUserIDs: [String] = []
    private(set) var deletedUserIDs: [String] = []
    private(set) var deleteUserCalled = false
    var profileSnapshotResult: UserProfileSnapshot?
    private var blockedEnsureUserIDs: Set<String> = []
    private var ensureStartedUserIDs: Set<String> = []
    private var ensureContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var ensureStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    func ensureExists(for user: AuthModelUser) async {
        ensuredUserIDs.append(user.uid)
        ensureStartedUserIDs.insert(user.uid)
        ensureStartedContinuations.removeValue(forKey: user.uid)?.resume()

        if blockedEnsureUserIDs.contains(user.uid) {
            await withCheckedContinuation { continuation in
                ensureContinuations[user.uid] = continuation
            }
        }
    }

    func profileSnapshot(userId: String) async throws -> UserProfileSnapshot? {
        _ = userId
        return profileSnapshotResult
    }

    func deleteUserAndAuth(user: AuthModelUser) async {
        deletedUserIDs.append(user.uid)
        deleteUserCalled = true
        if let mockUser = user as? MockAuthUser {
            try? await mockUser.delete()
        }
    }

    func blockEnsure(for userID: String) {
        blockedEnsureUserIDs.insert(userID)
    }

    func waitUntilEnsureStarts(for userID: String) async {
        guard !ensureStartedUserIDs.contains(userID) else { return }
        await withCheckedContinuation { continuation in
            ensureStartedContinuations[userID] = continuation
        }
    }

    func resumeEnsure(for userID: String) {
        blockedEnsureUserIDs.remove(userID)
        ensureContinuations.removeValue(forKey: userID)?.resume()
    }
}

actor MockAccountDeletionPerforming: AccountDeletionPerforming {
    private(set) var deleteCalls = 0
    var shouldFail = false
    var blocksUntilResume = false
    private var resumeGate: CheckedContinuation<Void, Never>?
    private var deletionStarted = false
    private var deletionStartedContinuation: CheckedContinuation<Void, Never>?

    func deleteCurrentAccount(password: String?) async throws {
        _ = password
        deleteCalls += 1
        deletionStarted = true
        deletionStartedContinuation?.resume()
        deletionStartedContinuation = nil
        if shouldFail {
            throw AccountDeletionError.missingPassword
        }
        if blocksUntilResume, deleteCalls == 1 {
            await withCheckedContinuation { resumeGate = $0 }
        }
    }

    func resumePendingDeletion() {
        resumeGate?.resume()
        resumeGate = nil
    }

    func setBlocksUntilResume(_ value: Bool) {
        blocksUntilResume = value
    }

    func waitUntilDeletionStarts() async {
        guard !deletionStarted else { return }
        await withCheckedContinuation { continuation in
            deletionStartedContinuation = continuation
        }
    }
}

struct MockBadgeProgressBackfill: BadgeProgressBackfilling {
    func backfillBadgeProgressIfNeeded() async {}
}

@MainActor
func makeAuthModelForTesting(
    auth: MockAuthProvider = MockAuthProvider(),
    usernameService: MockUsernameService = MockUsernameService(),
    userDocumentManager: MockUserDocumentManager? = nil,
    accountDeletionService: AccountDeletionPerforming = MockAccountDeletionPerforming(),
    badgeBackfillService: BadgeProgressBackfilling = MockBadgeProgressBackfill(),
    registersAuthListener: Bool = false
) -> (AuthModel, MockAuthProvider, MockUsernameService, MockUserDocumentManager) {
    let resolvedUserDocumentManager = userDocumentManager ?? MockUserDocumentManager()
    let dependencies = AuthModelDependencies(
        auth: auth,
        usernameService: usernameService,
        userDocumentManager: resolvedUserDocumentManager,
        accountDeletionService: accountDeletionService,
        badgeBackfillService: badgeBackfillService
    )
    let model = AuthModel(
        dependencies: dependencies,
        registersAuthListener: registersAuthListener
    )
    return (model, auth, usernameService, resolvedUserDocumentManager)
}
