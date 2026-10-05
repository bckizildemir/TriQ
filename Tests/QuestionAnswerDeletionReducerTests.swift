import XCTest
@testable import TTB

final class QuestionAnswerDeletionReducerTests: XCTestCase {

    func testApplyRemovesAnswerStatsAndDecrementsRespondentCounts() {
        let answeredAt = makeDate(year: 2026, month: 3, day: 22)
        let state = QuestionAnswerAggregateState(
            answerStats: [
                "0": ["Blue": 2],
                "1": ["Red": 1, "Green": 3]
            ],
            totalRespondents: 4,
            todayRespondents: 2,
            todayDate: "2026-03-22",
            lastAnsweredAt: Date(timeIntervalSince1970: 500)
        )

        let updatedState = QuestionAnswerDeletionReducer.apply(
            to: state,
            removingAnswers: ["Blue", "Red", ""],
            answeredAt: answeredAt,
            replacementLastAnsweredAt: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(updatedState.answerStats["0"]?["Blue"], 1)
        XCTAssertNil(updatedState.answerStats["1"]?["Red"])
        XCTAssertEqual(updatedState.answerStats["1"]?["Green"], 3)
        XCTAssertEqual(updatedState.totalRespondents, 3)
        XCTAssertEqual(updatedState.todayRespondents, 1)
        XCTAssertEqual(updatedState.todayDate, "2026-03-22")
        XCTAssertEqual(updatedState.lastAnsweredAt, Date(timeIntervalSince1970: 400))
    }

    func testApplyClearsTodayDateWhenLastRespondentForDayIsRemoved() {
        let answeredAt = makeDate(year: 2026, month: 3, day: 22)
        let state = QuestionAnswerAggregateState(
            answerStats: [
                "0": ["Solo": 1]
            ],
            totalRespondents: 1,
            todayRespondents: 1,
            todayDate: "2026-03-22",
            lastAnsweredAt: Date(timeIntervalSince1970: 500)
        )

        let updatedState = QuestionAnswerDeletionReducer.apply(
            to: state,
            removingAnswers: ["Solo", "", ""],
            answeredAt: answeredAt,
            replacementLastAnsweredAt: nil
        )

        XCTAssertTrue(updatedState.answerStats.isEmpty)
        XCTAssertEqual(updatedState.totalRespondents, 0)
        XCTAssertEqual(updatedState.todayRespondents, 0)
        XCTAssertEqual(updatedState.todayDate, "")
        XCTAssertNil(updatedState.lastAnsweredAt)
    }

    func testApplyDoesNotTouchTodayRespondentsForDifferentStoredDate() {
        let answeredAt = makeDate(year: 2026, month: 3, day: 22)
        let state = QuestionAnswerAggregateState(
            answerStats: [
                "0": ["Archive": 1]
            ],
            totalRespondents: 2,
            todayRespondents: 5,
            todayDate: "2026-03-21",
            lastAnsweredAt: Date(timeIntervalSince1970: 500)
        )

        let updatedState = QuestionAnswerDeletionReducer.apply(
            to: state,
            removingAnswers: ["Archive", "", ""],
            answeredAt: answeredAt,
            replacementLastAnsweredAt: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(updatedState.totalRespondents, 1)
        XCTAssertEqual(updatedState.todayRespondents, 5)
        XCTAssertEqual(updatedState.todayDate, "2026-03-21")
        XCTAssertEqual(updatedState.lastAnsweredAt, Date(timeIntervalSince1970: 400))
    }

    func testApplyClampsCountsAtZero() {
        let answeredAt = makeDate(year: 2026, month: 3, day: 22)
        let state = QuestionAnswerAggregateState(
            answerStats: [:],
            totalRespondents: 0,
            todayRespondents: 0,
            todayDate: "",
            lastAnsweredAt: nil
        )

        let updatedState = QuestionAnswerDeletionReducer.apply(
            to: state,
            removingAnswers: ["Missing", "", ""],
            answeredAt: answeredAt,
            replacementLastAnsweredAt: nil
        )

        XCTAssertEqual(updatedState.totalRespondents, 0)
        XCTAssertEqual(updatedState.todayRespondents, 0)
        XCTAssertEqual(updatedState.todayDate, "")
        XCTAssertNil(updatedState.lastAnsweredAt)
    }

    func testApplySafelyRepairsNegativeAndMinimumCounters() {
        let answeredAt = makeDate(year: 2026, month: 3, day: 22)
        let state = QuestionAnswerAggregateState(
            answerStats: ["0": ["Corrupt": Int.min]],
            totalRespondents: Int.min,
            todayRespondents: -1,
            todayDate: "2026-03-22",
            lastAnsweredAt: nil
        )

        let updatedState = QuestionAnswerDeletionReducer.apply(
            to: state,
            removingAnswers: ["Corrupt", "", ""],
            answeredAt: answeredAt,
            replacementLastAnsweredAt: nil
        )

        XCTAssertTrue(updatedState.answerStats.isEmpty)
        XCTAssertEqual(updatedState.totalRespondents, 0)
        XCTAssertEqual(updatedState.todayRespondents, 0)
        XCTAssertEqual(updatedState.todayDate, "")
    }

    func testApplyRepairsCorruptUntouchedCountersForDifferentStoredDate() {
        let answeredAt = makeDate(year: 2026, month: 3, day: 22)
        let state = QuestionAnswerAggregateState(
            answerStats: [
                "0": ["Removed": 1],
                "1": ["Unrelated corruption": Int.min],
            ],
            totalRespondents: 1,
            todayRespondents: Int.min,
            todayDate: "2026-03-21",
            lastAnsweredAt: nil
        )

        let updatedState = QuestionAnswerDeletionReducer.apply(
            to: state,
            removingAnswers: ["Removed", "", ""],
            answeredAt: answeredAt,
            replacementLastAnsweredAt: nil
        )

        XCTAssertTrue(updatedState.answerStats.isEmpty)
        XCTAssertEqual(updatedState.totalRespondents, 0)
        XCTAssertEqual(updatedState.todayRespondents, 0)
        XCTAssertEqual(updatedState.todayDate, "")
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        return components.date ?? .distantPast
    }
}
