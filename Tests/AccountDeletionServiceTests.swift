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
        XCTAssertEqual(operations.callLog.first, "purgeAnswers")
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
                "purgeAnswers",
                "favoriteQuestionReferences",
                "removeFavorites",
                "deleteAI",
                "deleteProfileAssets",
                "deleteUserDocument",
                "deleteAuthUser",
            ]
        )
    }

    func testDelete_stopsOnFirstFailure() async {
        let operations = MockAccountDeletionOperations()
        operations.failures["purgeAnswers"] = NSError(domain: "test", code: 1)
        let auth = MockAccountDeletionAuth(
            currentUserValue: MockAccountDeletionUser(uid: "anon-1", isAnonymous: true, email: nil)
        )
        let service = AccountDeletionService(operations: operations, auth: auth)

        do {
            try await service.deleteCurrentAccount(password: nil)
            XCTFail("Expected purgeAnswers failure")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "test")
            XCTAssertEqual(error.code, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(operations.callLog.contains("removeFavorites"))
    }

    func testFirestoreBatchPlannerCoversBoundaryCountsWithoutOversizedBatches() {
        let cases: [(itemCount: Int, expectedSizes: [Int])] = [
            (0, []),
            (399, [399]),
            (400, [400]),
            (401, [400, 1]),
            (800, [400, 400]),
            (801, [400, 400, 1]),
        ]

        for testCase in cases {
            let ranges = FirestoreBatchPlanner.ranges(
                itemCount: testCase.itemCount,
                limit: 400
            )

            XCTAssertEqual(ranges.map(\.count), testCase.expectedSizes)
            XCTAssertEqual(ranges.flatMap(Array.init), Array(0..<testCase.itemCount))
            XCTAssertTrue(ranges.allSatisfy { !$0.isEmpty && $0.count <= 400 })
        }
    }
}
