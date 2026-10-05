import XCTest
@testable import TTB

final class FavoriteMigrationResponseTests: XCTestCase {
    func testUnavailableQuestionIDsReturnsValidatedIDs() throws {
        let result = try FavoriteMigrationResponse.unavailableQuestionIDs(
            from: ["unavailableQuestionIds": ["q2", "q3"]],
            requestedQuestionIDs: ["q1", "q2", "q3"]
        )

        XCTAssertEqual(result, ["q2", "q3"])
    }

    func testUnavailableQuestionIDsAcceptsExplicitEmptyList() throws {
        let result = try FavoriteMigrationResponse.unavailableQuestionIDs(
            from: ["unavailableQuestionIds": [String]()],
            requestedQuestionIDs: ["q1"]
        )

        XCTAssertEqual(result, [])
    }

    func testUnavailableQuestionIDsRejectsOlderResponseWithoutIDList() {
        XCTAssertThrowsError(
            try FavoriteMigrationResponse.unavailableQuestionIDs(
                from: ["added": 1, "alreadyFavorite": 0, "unavailable": 1],
                requestedQuestionIDs: ["q1", "q2"]
            )
        ) { error in
            XCTAssertEqual(error as? FavoriteMigrationResponseError, .invalidPayload)
        }
    }

    func testUnavailableQuestionIDsRejectsIDsOutsideRequest() {
        XCTAssertThrowsError(
            try FavoriteMigrationResponse.unavailableQuestionIDs(
                from: ["unavailableQuestionIds": ["not-requested"]],
                requestedQuestionIDs: ["q1"]
            )
        ) { error in
            XCTAssertEqual(error as? FavoriteMigrationResponseError, .invalidPayload)
        }
    }
}
