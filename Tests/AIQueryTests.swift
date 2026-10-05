import XCTest
@testable import TTB

final class AIQueryTests: XCTestCase {
    func testQueryWithBlankResponsesIsNotComplete() {
        let query = AIQuery(
            question: "What are your favorites?",
            responses: ["One", "   ", "\n"],
            category: .other
        )

        XCTAssertFalse(query.isComplete)
    }
}
