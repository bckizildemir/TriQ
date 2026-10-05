import Foundation
@testable import TTB

struct MockAccountDeletionUser: AccountDeletionAuthUser {
    let uid: String
    let isAnonymous: Bool
    let email: String?
}

struct MockAccountDeletionAuth: AccountDeletionAuthProviding {
    var currentUserValue: (any AccountDeletionAuthUser)?

    func currentUser() -> (any AccountDeletionAuthUser)? {
        currentUserValue
    }
}

final class MockAccountDeletionOperations: AccountDeletionOperations {
    private(set) var callLog: [String] = []
    var favoriteQuestionIds: [String] = []
    var failures: [String: Error] = [:]

    func reauthenticate(user: any AccountDeletionAuthUser, password: String?) async throws {
        callLog.append("reauthenticate")
        if let error = failures["reauthenticate"] { throw error }
    }

    func purgeAnswers() async throws {
        callLog.append("purgeAnswers")
        if let error = failures["purgeAnswers"] { throw error }
    }

    func favoriteQuestionReferences(for userId: String) async throws -> [String] {
        _ = userId
        callLog.append("favoriteQuestionReferences")
        if let error = failures["favoriteQuestionReferences"] { throw error }
        return favoriteQuestionIds
    }

    func removeFavorites(userId: String, questionIds: [String]) async throws {
        _ = userId
        callLog.append("removeFavorites")
        if let error = failures["removeFavorites"] { throw error }
        _ = questionIds
    }

    func deleteAIDocuments(userId: String) async throws {
        _ = userId
        callLog.append("deleteAI")
        if let error = failures["deleteAI"] { throw error }
    }

    func deleteProfileAssets(userId: String) async throws {
        _ = userId
        callLog.append("deleteProfileAssets")
        if let error = failures["deleteProfileAssets"] { throw error }
    }

    func deleteUserDocument(userId: String) async throws {
        _ = userId
        callLog.append("deleteUserDocument")
        if let error = failures["deleteUserDocument"] { throw error }
    }

    func deleteAuthUser(_ user: any AccountDeletionAuthUser) async throws {
        _ = user
        callLog.append("deleteAuthUser")
        if let error = failures["deleteAuthUser"] { throw error }
    }
}
