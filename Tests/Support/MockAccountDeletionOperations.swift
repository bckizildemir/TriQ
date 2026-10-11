import Foundation
import Synchronization
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
    private struct State {
        var callLog: [String] = []
        var favoriteQuestionIds: [String] = []
        var failures: [String: Error] = [:]
    }

    private let state = Mutex(State())

    var callLog: [String] { state.withLock { $0.callLog } }

    var favoriteQuestionIds: [String] {
        get { state.withLock { $0.favoriteQuestionIds } }
        set { state.withLock { $0.favoriteQuestionIds = newValue } }
    }

    var failures: [String: Error] {
        get { state.withLock { $0.failures } }
        set { state.withLock { $0.failures = newValue } }
    }

    private func record(_ call: String) {
        state.withLock { $0.callLog.append(call) }
    }

    func reauthenticate(user: any AccountDeletionAuthUser, password: String?) async throws {
        record("reauthenticate")
        if let error = failures["reauthenticate"] { throw error }
    }

    func purgeAnswers() async throws {
        record("purgeAnswers")
        if let error = failures["purgeAnswers"] { throw error }
    }

    func favoriteQuestionReferences(for userId: String) async throws -> [String] {
        _ = userId
        record("favoriteQuestionReferences")
        if let error = failures["favoriteQuestionReferences"] { throw error }
        return favoriteQuestionIds
    }

    func removeFavorites(userId: String, questionIds: [String]) async throws {
        _ = userId
        record("removeFavorites")
        if let error = failures["removeFavorites"] { throw error }
        _ = questionIds
    }

    func deleteAIDocuments(userId: String) async throws {
        _ = userId
        record("deleteAI")
        if let error = failures["deleteAI"] { throw error }
    }

    func deleteProfileAssets(userId: String) async throws {
        _ = userId
        record("deleteProfileAssets")
        if let error = failures["deleteProfileAssets"] { throw error }
    }

    func deleteUserDocument(userId: String) async throws {
        _ = userId
        record("deleteUserDocument")
        if let error = failures["deleteUserDocument"] { throw error }
    }

    func deleteAuthUser(_ user: any AccountDeletionAuthUser) async throws {
        _ = user
        record("deleteAuthUser")
        if let error = failures["deleteAuthUser"] { throw error }
    }
}
