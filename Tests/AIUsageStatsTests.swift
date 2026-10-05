import FirebaseFirestore
import XCTest
@testable import TTB

final class AIUsageStatsTests: XCTestCase {
    func testFirestoreDecodingClampsNegativeUsageCountersToZero() throws {
        let stats = try XCTUnwrap(AIUsageStats.fromFirestore([
            "dailyQueries": -1,
            "weeklyQueries": -2,
            "monthlyQueries": -3,
            "totalQueries": -4,
            "lastResetDate": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000)),
        ]))

        XCTAssertEqual(stats.dailyQueries, 0)
        XCTAssertEqual(stats.weeklyQueries, 0)
        XCTAssertEqual(stats.monthlyQueries, 0)
        XCTAssertEqual(stats.totalQueries, 0)
        XCTAssertTrue(stats.canMakeQuery)
        XCTAssertEqual(stats.usagePercentage, 0)
    }

    func testIncrementUsageSaturatesCorruptedMaximumCounters() {
        let stats = AIUsageStats(
            dailyQueries: .max,
            weeklyQueries: .max,
            monthlyQueries: .max,
            totalQueries: .max,
            lastResetDate: Date()
        )

        let incremented = stats.incrementUsage(category: .other)

        XCTAssertEqual(incremented.dailyQueries, .max)
        XCTAssertEqual(incremented.weeklyQueries, .max)
        XCTAssertEqual(incremented.monthlyQueries, .max)
        XCTAssertEqual(incremented.totalQueries, .max)
        XCTAssertFalse(incremented.canMakeQuery)
    }
}
