import FirebaseAuth
import Foundation

#if DEBUG
final class UITestAuthUser: AuthModelUser {
    let uid: String
    let isAnonymous: Bool
    let email: String?

    /// Set by the provider that holds this user. Real Firebase publishes a linked user through the
    /// auth state listener, and the fixture has to do the same: `AuthModel.isAnonymous` is computed
    /// from `currentUser`, so without this a fixture guest stays anonymous after a successful
    /// upgrade. The guest-upgrade sheet waits on that value to dismiss, and guest-favorite
    /// migration waits on it to run.
    var onLink: ((AuthModelUser) -> Void)?

    init(uid: String, isAnonymous: Bool = false, email: String? = nil) {
        self.uid = uid
        self.isAnonymous = isAnonymous
        self.email = email
    }

    func delete() async throws {}

    func link(with credential: AuthCredential) async throws -> AuthModelUser {
        _ = credential
        // The uid survives the link, exactly as Firebase keeps it, so favorites and answers written
        // as a guest still belong to the same account afterwards.
        let linkedUser = UITestAuthUser(uid: uid, isAnonymous: false, email: email)
        onLink?(linkedUser)
        return linkedUser
    }

    func forceRefreshIDToken() async throws {}
}

final class UITestAuthProvider: AuthModelAuthProviding {
    var currentUser: AuthModelUser? {
        didSet { adoptCurrentUser() }
    }

    private var stateDidChange: ((AuthModelUser?) -> Void)?

    init(currentUser: AuthModelUser?) {
        self.currentUser = currentUser
        adoptCurrentUser()
    }

    /// Only `link` republishes. `signIn`, `createUser`, `signInAnonymously` and `signOut` swap
    /// `currentUser` without notifying, which is what the thirteen existing UI tests were written
    /// against. Widening that is a separate change with its own suite run.
    private func adoptCurrentUser() {
        guard let user = currentUser as? UITestAuthUser else { return }
        user.onLink = { [weak self] linkedUser in
            self?.currentUser = linkedUser
            self?.stateDidChange?(linkedUser)
        }
    }

    func createUser(withEmail email: String, password: String) async throws -> AuthModelUser {
        let user = UITestAuthUser(uid: "ui-test-created-user", isAnonymous: false, email: email)
        currentUser = user
        return user
    }

    func signIn(withEmail email: String, password: String) async throws {
        currentUser = UITestAuthUser(uid: "ui-test-signed-in-user", isAnonymous: false, email: email)
    }

    func signOut() throws {
        currentUser = nil
    }

    func signInAnonymously() async throws -> AuthModelUser {
        let user = UITestAuthUser(uid: "ui-test-anonymous-user", isAnonymous: true)
        currentUser = user
        return user
    }

    func sendPasswordReset(withEmail email: String) async throws {
        _ = email
    }

    func addStateDidChangeListener(
        _ listener: @escaping (AuthModelUser?) -> Void
    ) -> AuthStateListenerHandle? {
        stateDidChange = listener
        listener(currentUser)
        return nil
    }

    /// `AuthModel` calls this from its nonisolated `deinit`, so it cannot clear `stateDidChange`.
    /// The provider is released with that `AuthModel`, so the stale listener is never called.
    nonisolated func removeStateDidChangeListener(_ handle: AuthStateListenerHandle?) {
        _ = handle
    }
}

struct UITestUsernameService: UsernameServiceProtocol {
    func claimUsername(
        _ username: String,
        email: String?,
        isAnonymous: Bool?
    ) async throws -> ClaimedUsername {
        _ = email
        _ = isAnonymous
        return ClaimedUsername(username: username, usernameNormalized: username.lowercased())
    }

    func resolveEmail(for username: String) async throws -> String {
        "\(username)@example.com"
    }

    func releaseUsername(
        _ username: String,
        restoreUsername: String?,
        restoreEmail: String?,
        restoreIsAnonymous: Bool?
    ) async {
        _ = username
        _ = restoreUsername
        _ = restoreEmail
        _ = restoreIsAnonymous
    }
}

struct UITestUserDocumentManager: AuthUserDocumentManaging {
    func ensureExists(for user: AuthModelUser) async {
        _ = user
    }

    func profileSnapshot(userId: String) async throws -> UserProfileSnapshot? {
        _ = userId
        return nil
    }

    func deleteUserAndAuth(user: AuthModelUser) async {
        _ = user
    }
}

struct UITestBadgeProgressBackfill: BadgeProgressBackfilling {
    func backfillBadgeProgressIfNeeded() async {}
}

actor UITestAccountDeletionService: AccountDeletionPerforming {
    func deleteCurrentAccount(password: String?) async throws {
        _ = password
    }
}

@MainActor
enum UITestAuthModelFactory {
    static func permanentUser(uid: String) -> AuthModel {
        let dependencies = AuthModelDependencies(
            auth: UITestAuthProvider(
                currentUser: UITestAuthUser(uid: uid, isAnonymous: false, email: "uitest@example.com")
            ),
            usernameService: UITestUsernameService(),
            userDocumentManager: UITestUserDocumentManager(),
            accountDeletionService: UITestAccountDeletionService(),
            badgeBackfillService: UITestBadgeProgressBackfill()
        )
        return AuthModel(dependencies: dependencies, registersAuthListener: true)
    }

    static func anonymousUser() -> AuthModel {
        let dependencies = AuthModelDependencies(
            auth: UITestAuthProvider(
                currentUser: UITestAuthUser(uid: "ui-test-anonymous-user", isAnonymous: true)
            ),
            usernameService: UITestUsernameService(),
            userDocumentManager: UITestUserDocumentManager(),
            accountDeletionService: UITestAccountDeletionService(),
            badgeBackfillService: UITestBadgeProgressBackfill()
        )
        return AuthModel(dependencies: dependencies, registersAuthListener: true)
    }
}
#endif
