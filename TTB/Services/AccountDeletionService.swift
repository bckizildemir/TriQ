import FirebaseAuth
import Foundation

enum AccountDeletionError: LocalizedError, Equatable {
    case unauthenticated
    case missingPassword
    case missingEmail

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
        }
    }
}

actor AccountDeletionService {
    private let operations: any AccountDeletionOperations
    private let auth: any AccountDeletionAuthProviding

    init(
        operations: any AccountDeletionOperations = LiveAccountDeletionOperations(),
        auth: any AccountDeletionAuthProviding = LiveAccountDeletionAuth()
    ) {
        self.operations = operations
        self.auth = auth
    }

    func deleteCurrentAccount(password: String?) async throws {
        guard let currentUser = auth.currentUser() else {
            throw AccountDeletionError.unauthenticated
        }

        if !currentUser.isAnonymous {
            try Self.validatePermanentUserReauthentication(user: currentUser, password: password)
            try await operations.reauthenticate(user: currentUser, password: password)
        }

        let userId = currentUser.uid

        try await operations.purgeAnswers()
        let favoriteQuestionIds = try await operations.favoriteQuestionReferences(for: userId)
        try await operations.removeFavorites(userId: userId, questionIds: favoriteQuestionIds)
        try await operations.deleteAIDocuments(userId: userId)
        try await operations.deleteProfileAssets(userId: userId)
        try await operations.deleteUserDocument(userId: userId)
        try await operations.deleteAuthUser(currentUser)
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

    static func reauthenticatePermanentUser(user: User, password: String?) async throws {
        try validatePermanentUserReauthentication(user: user, password: password)

        let email = user.email ?? ""
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let credential = EmailAuthProvider.credential(withEmail: email, password: trimmedPassword)
        try await user.reauthenticateAsync(with: credential)
    }
}
