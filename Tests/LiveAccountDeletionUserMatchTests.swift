import Testing
@testable import TTB

/// The uid check `LiveAccountDeletionOperations` runs before it touches the live Firebase `User`
/// (TriQ#17). The adapter itself needs Firebase, so the comparison is tested on its own.
struct LiveAccountDeletionUserMatchTests {
    @Test func matchingUserIDPasses() throws {
        try LiveAccountDeletionOperations.requireSameUser(currentUserID: "u1", expectedUserID: "u1")
    }

    @Test func differentUserIDIsUnauthenticated() {
        #expect(throws: AccountDeletionError.unauthenticated) {
            try LiveAccountDeletionOperations.requireSameUser(currentUserID: "u2", expectedUserID: "u1")
        }
    }

    @Test func noSignedInUserIsUnauthenticated() {
        #expect(throws: AccountDeletionError.unauthenticated) {
            try LiveAccountDeletionOperations.requireSameUser(currentUserID: nil, expectedUserID: "u1")
        }
    }
}
