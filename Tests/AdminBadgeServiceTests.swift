import XCTest
@testable import TTB

final class AdminBadgeServiceTests: XCTestCase {
    func testRestorableBadgesOnlyReturnsMissingDefaults() throws {
        let json = """
        [
          {
            "id": "badge-one",
            "title": "Badge One",
            "description": "Desc One",
            "icon": "star.fill",
            "requirement": "Do one thing",
            "targetCount": 1,
            "type": "total",
            "category": null
          },
          {
            "id": "badge-two",
            "title": "Badge Two",
            "description": "Desc Two",
            "icon": "heart.fill",
            "requirement": "Do two things",
            "targetCount": 2,
            "type": "category",
            "category": "Relationships"
          }
        ]
        """.data(using: .utf8)!

        let badges = try AdminBadgeService.restorableBadges(
            from: json,
            excluding: ["badge-one", "custom-badge"]
        )

        XCTAssertEqual(badges.map(\.id), ["badge-two"])
        XCTAssertEqual(badges.first?.type, .category)
        XCTAssertEqual(badges.first?.category, "Relationships")
    }
}
