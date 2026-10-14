import XCTest
@testable import TTB

final class AccountDeletionServiceTests: XCTestCase {
    func testDelete_throwsUnauthenticatedWhenNoUser() async {
        let operations = MockAccountDeletionOperations()
        let auth = MockAccountDeletionAuth(currentUserValue: nil)
        let service = AccountDeletionService(operations: operations, auth: auth)

        do {
            try await service.deleteCurrentAccount(password: nil)
            XCTFail("Expected unauthenticated error")
        } catch let error as AccountDeletionError {
            XCTAssertEqual(error, .unauthenticated)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(operations.callLog.isEmpty)
    }

    func testDelete_skipsReauthForAnonymousUser() async throws {
        let operations = MockAccountDeletionOperations()
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(uid: "anon-1", isAnonymous: true, email: nil)
        )
        let service = AccountDeletionService(operations: operations, auth: auth)

        try await service.deleteCurrentAccount(password: nil)

        XCTAssertFalse(operations.callLog.contains("reauthenticate"))
        XCTAssertEqual(operations.callLog.first, "deleteAccountData")
    }

    func testDelete_requiresPasswordForPermanentUser() async {
        let operations = MockAccountDeletionOperations()
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(
                uid: "user-1",
                isAnonymous: false,
                email: "user@example.com"
            )
        )
        let service = AccountDeletionService(operations: operations, auth: auth)

        do {
            try await service.deleteCurrentAccount(password: nil)
            XCTFail("Expected missingPassword error")
        } catch let error as AccountDeletionError {
            XCTAssertEqual(error, .missingPassword)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(operations.callLog.isEmpty)
    }

    func testDelete_requiresEmailForPermanentUser() async {
        let operations = MockAccountDeletionOperations()
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(uid: "user-1", isAnonymous: false, email: nil)
        )
        let service = AccountDeletionService(operations: operations, auth: auth)

        do {
            try await service.deleteCurrentAccount(password: "secret")
            XCTFail("Expected missingEmail error")
        } catch let error as AccountDeletionError {
            XCTAssertEqual(error, .missingEmail)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(operations.callLog.isEmpty)
    }

    func testDelete_executesStepsInOrder() async throws {
        let operations = MockAccountDeletionOperations()
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(
                uid: "user-1",
                isAnonymous: false,
                email: "user@example.com"
            )
        )
        let service = AccountDeletionService(operations: operations, auth: auth)

        try await service.deleteCurrentAccount(password: "secret")

        XCTAssertEqual(
            operations.callLog,
            [
                "reauthenticate",
                "deleteAccountData",
                "deleteLocalProfileImage",
                "signOut",
            ]
        )
    }

    func testDelete_stopsOnFirstFailure() async {
        let operations = MockAccountDeletionOperations()
        operations.failures["deleteAccountData"] = NSError(domain: "test", code: 1)
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(uid: "anon-1", isAnonymous: true, email: nil)
        )
        let service = AccountDeletionService(operations: operations, auth: auth)

        do {
            try await service.deleteCurrentAccount(password: nil)
            XCTFail("Expected deleteAccountData failure")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "test")
            XCTAssertEqual(error.code, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(operations.callLog.contains("signOut"))
    }
}
