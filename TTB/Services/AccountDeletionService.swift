import FirebaseAuth
import Foundation

enum AccountDeletionError: LocalizedError, Equatable {
    case unauthenticated
    case missingPassword
    case missingEmail
    /// The `deleteOwnAccountData` callable failed or answered without `success: true`. The Auth
    /// account is kept, so the user can retry.
    case dataDeletionFailed
    /// The server no longer knows this Auth user: a retry after the callable deleted the user but
    /// the response was lost. Distinct from `.unauthenticated`, which also means "a different user
    /// is signed in" and must never sign anybody out. `AccountDeletionService` swallows this case.
    case accountAlreadyDeleted

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return AppLocalization.prefersEnglish
                ? "No active session was found for deleting this account."
                : "Hesabı silmek için aktif bir oturum bulunamadı."
        case .missingPassword:
            return AppLocalization.prefersEnglish
                ? "You need to re-enter your password before deleting your account."
                : "Hesabını silmek için şifreni tekrar girmelisin."
        case .missingEmail:
            return AppLocalization.prefersEnglish
                ? "No email address was found to re-authenticate this account."
                : "Bu hesabı yeniden doğrulamak için bir e-posta adresi bulunamadı."
        case .dataDeletionFailed:
            return String(localized: "profile.deleteAccount.failed.message")
        case .accountAlreadyDeleted:
            return AppLocalization.prefersEnglish
                ? "This account was already deleted."
                : "Bu hesap zaten silinmiş."
        }
    }
}

actor AccountDeletionService {
    private let operations: any AccountDeletionOperations
    private let auth: any AccountDeletionAuthProviding
    private let imageService: ImageService

    init(
        operations: any AccountDeletionOperations = LiveAccountDeletionOperations(),
        auth: any AccountDeletionAuthProviding = LiveAccountDeletionAuth(),
        imageService: ImageService = .shared
    ) {
        self.operations = operations
        self.auth = auth
        self.imageService = imageService
    }

    /// Reauthenticates a permanent user, then the server deletes all of the user's data and the
    /// Auth user last (TriQ#88); the client only signs out locally. If the server step fails, the
    /// account stays, and a retry runs the whole server step again; it is idempotent.
    ///
    /// If an earlier attempt deleted the Auth user but the response was lost, the retry fails with
    /// `.accountAlreadyDeleted` from the reauthentication or the callable. That counts as done:
    /// the service removes the local photo, signs out, and returns normally. There is no photo URL
    /// to evict in that case.
    func deleteCurrentAccount(password: String?) async throws {
        guard let currentUser = auth.currentUser() else {
            throw AccountDeletionError.unauthenticated
        }

        let summary: AccountDeletionSummary
        do {
            if !currentUser.isAnonymous {
                try Self.validatePermanentUserReauthentication(user: currentUser, password: password)
                try await operations.reauthenticate(user: currentUser, password: password)
            }
            summary = try await operations.deleteAccountData()
        } catch AccountDeletionError.accountAlreadyDeleted {
            await operations.deleteLocalProfileImage(userId: currentUser.uid)
            await operations.signOut()
            return
        }

        // The server deleted the photo from Storage; drop the copies this device still holds.
        if let profileImageURL = summary.profileImageURL {
            await imageService.evictProfileImage(downloadURL: profileImageURL)
        }
        await operations.deleteLocalProfileImage(userId: currentUser.uid)

        await operations.signOut()
    }

    static func validatePermanentUserReauthentication(
        user: any AccountDeletionAuthUser,
        password: String?
    ) throws {
        guard let email = user.email, !email.isEmpty else {
            throw AccountDeletionError.missingEmail
        }

        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPassword.isEmpty else {
            throw AccountDeletionError.missingPassword
        }
    }

    nonisolated(nonsending) static func reauthenticatePermanentUser(user: User, password: String?) async throws {
        try validatePermanentUserReauthentication(
            user: AccountDeletionUserSnapshot(user),
            password: password
        )

        let email = user.email ?? ""
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let credential = EmailAuthProvider.credential(withEmail: email, password: trimmedPassword)
        try await user.reauthenticateAsync(with: credential)
    }
}
