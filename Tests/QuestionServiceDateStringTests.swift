import XCTest
@testable import TTB

final class QuestionServiceDateStringTests: XCTestCase {
    func testDateStringUsesUTCDateKeyMatchingCloudFunction() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Europe/Istanbul")
        components.year = 2026
        components.month = 6
        components.day = 23
        components.hour = 0
        components.minute = 30

        let date = try XCTUnwrap(components.date)

        XCTAssertEqual(QuestionService.dateString(for: date), "2026-06-22")
    }
}
