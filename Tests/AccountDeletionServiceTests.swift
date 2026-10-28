import UIKit
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

    func testDelete_retryAfterAccountDeletedOnTheCallablePathSignsOut() async throws {
        let operations = MockAccountDeletionOperations()
        operations.failures["deleteAccountData"] = AccountDeletionError.accountAlreadyDeleted
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(uid: "anon-1", isAnonymous: true, email: nil)
        )
        let service = AccountDeletionService(operations: operations, auth: auth)

        try await service.deleteCurrentAccount(password: nil)

        XCTAssertEqual(
            operations.callLog,
            ["deleteAccountData", "deleteLocalProfileImage", "signOut"]
        )
    }

    func testDelete_retryAfterAccountDeletedOnTheReauthPathSignsOut() async throws {
        let operations = MockAccountDeletionOperations()
        operations.failures["reauthenticate"] = AccountDeletionError.accountAlreadyDeleted
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
            ["reauthenticate", "deleteLocalProfileImage", "signOut"]
        )
    }

    func testDelete_differentUserUnauthenticatedStillThrowsAndKeepsTheSession() async {
        let operations = MockAccountDeletionOperations()
        operations.failures["reauthenticate"] = AccountDeletionError.unauthenticated
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(
                uid: "user-1",
                isAnonymous: false,
                email: "user@example.com"
            )
        )
        let service = AccountDeletionService(operations: operations, auth: auth)

        do {
            try await service.deleteCurrentAccount(password: "secret")
            XCTFail("Expected unauthenticated error")
        } catch let error as AccountDeletionError {
            XCTAssertEqual(error, .unauthenticated)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(operations.callLog.contains("signOut"))
        XCTAssertFalse(operations.callLog.contains("deleteLocalProfileImage"))
    }

    func testDelete_evictsTheCachedProfilePhotoTheServerReported() async throws {
        let url = "https://firebasestorage.googleapis.com/v0/b/test/o/profiles%2Fu%2Fp.jpg?alt=media&token=t"
        let imageService = ImageService()
        await imageService.cacheImage(UIImage(), for: url)
        let operations = MockAccountDeletionOperations()
        operations.summary = AccountDeletionSummary(profileImageURL: url)
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(uid: "anon-1", isAnonymous: true, email: nil)
        )
        let service = AccountDeletionService(operations: operations, auth: auth, imageService: imageService)

        try await service.deleteCurrentAccount(password: nil)

        let cached = await imageService.cachedImage(for: url)
        XCTAssertNil(cached)
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
