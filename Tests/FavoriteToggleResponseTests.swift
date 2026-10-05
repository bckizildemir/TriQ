import XCTest
@testable import TTB

final class FavoriteToggleResponseTests: XCTestCase {
    func testParseBool_acceptsTrueFalse() {
        XCTAssertEqual(FavoriteToggleResponse.parseBool(from: true), true)
        XCTAssertEqual(FavoriteToggleResponse.parseBool(from: false), false)
    }

    func testParseBool_acceptsNSNumber() {
        XCTAssertEqual(FavoriteToggleResponse.parseBool(from: NSNumber(value: 1)), true)
        XCTAssertEqual(FavoriteToggleResponse.parseBool(from: NSNumber(value: 0)), false)
    }

    func testParseBool_rejectsNSNumberOutsideBooleanDomain() {
        XCTAssertNil(FavoriteToggleResponse.parseBool(from: NSNumber(value: -1)))
        XCTAssertNil(FavoriteToggleResponse.parseBool(from: NSNumber(value: 2)))
        XCTAssertNil(FavoriteToggleResponse.parseBool(from: NSNumber(value: Double.nan)))
    }

    func testParseBool_rejectsStringAndNil() {
        XCTAssertNil(FavoriteToggleResponse.parseBool(from: "true"))
        XCTAssertNil(FavoriteToggleResponse.parseBool(from: nil))
    }

    func testResolve_returnsServerBool() throws {
        let resolved = try FavoriteToggleResponse.resolve(
            data: ["isFavorite": true],
            currentFavoriteState: false
        )
        XCTAssertTrue(resolved)
    }

    func testResolve_fallsBackWhenMissingIsFavorite() throws {
        let resolved = try FavoriteToggleResponse.resolve(
            data: [:],
            currentFavoriteState: true
        )
        XCTAssertFalse(resolved)
    }

    func testResolve_throwsWhenMissingIsFavoriteAndNoCurrent() {
        XCTAssertThrowsError(
            try FavoriteToggleResponse.resolve(data: [:], currentFavoriteState: nil)
        ) { error in
            XCTAssertEqual(error as? FavoriteToggleResponseError, .invalidPayload)
        }
    }

    func testResolve_rejectsMalformedIsFavoriteEvenWhenCurrentStateExists() {
        XCTAssertThrowsError(
            try FavoriteToggleResponse.resolve(
                data: ["isFavorite": NSNumber(value: 2)],
                currentFavoriteState: false
            )
        ) { error in
            XCTAssertEqual(error as? FavoriteToggleResponseError, .invalidPayload)
        }
    }
}
