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
        var summary = AccountDeletionSummary(profileImageURL: nil)
        var failures: [String: any Error] = [:]
    }

    private let state = Mutex(State())

    var callLog: [String] { state.withLock { $0.callLog } }

    var summary: AccountDeletionSummary {
        get { state.withLock { $0.summary } }
        set { state.withLock { $0.summary = newValue } }
    }

    var failures: [String: any Error] {
        get { state.withLock { $0.failures } }
        set { state.withLock { $0.failures = newValue } }
    }

    private func record(_ call: String) throws {
        let failure = state.withLock { state -> (any Error)? in
            state.callLog.append(call)
            return state.failures[call]
        }
        if let failure { throw failure }
    }

    func reauthenticate(user: any AccountDeletionAuthUser, password: String?) async throws {
        try record("reauthenticate")
    }

    func deleteAccountData() async throws -> AccountDeletionSummary {
        try record("deleteAccountData")
        return summary
    }

    func deleteLocalProfileImage(userId: String) async {
        try? record("deleteLocalProfileImage")
    }

    func signOut() async {
        try? record("signOut")
    }
}
