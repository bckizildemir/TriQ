import CryptoKit
import Foundation
import XCTest
@testable import TTB

final class TodaysQuestionSelectorTests: XCTestCase {

    private let selector = TodaysQuestionSelector(
        count: 7,
        timeZone: TimeZone(secondsFromGMT: 0) ?? .current
    )

    func testReturnsSameQuestionsForSameDateRegardlessOfInputOrder() {
        let questions = seededQuestions(count: 12)
        let date = Date(timeIntervalSince1970: 1_774_627_200)

        let originalIDs = selector.select(from: questions, on: date).map(\.contentId)
        let reversedIDs = selector.select(from: Array(questions.reversed()), on: date).map(\.contentId)

        XCTAssertEqual(originalIDs, reversedIDs)
    }

    func testDuplicateContentIDsChooseSameCanonicalQuestionRegardlessOfInputOrder() {
        let selector = TodaysQuestionSelector(
            count: 1,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )
        let questions = [
            makeQuestion(
                id: "document-b",
                contentId: "duplicate-content",
                category: "Daily",
                source: .seeded
            ),
            makeQuestion(
                id: "document-a",
                contentId: "duplicate-content",
                category: "Daily",
                source: .seeded
            ),
        ]
        let date = Date(timeIntervalSince1970: 1_774_627_200)

        let originalIDs = selector.select(from: questions, on: date).map(\.id)
        let reversedIDs = selector.select(from: Array(questions.reversed()), on: date).map(\.id)

        XCTAssertEqual(originalIDs, ["document-a"])
        XCTAssertEqual(reversedIDs, ["document-a"])
    }

    func testChangesSelectionWhenDateChanges() {
        let questions = seededQuestions(count: 12)
        let firstDate = Date(timeIntervalSince1970: 1_774_627_200)
        let secondDate = Date(timeIntervalSince1970: 1_774_713_600)

        let firstIDs = selector.select(from: questions, on: firstDate).map(\.contentId)
        let secondIDs = selector.select(from: questions, on: secondDate).map(\.contentId)

        XCTAssertNotEqual(firstIDs, secondIDs)
    }

    func testExcludesUserCreatedQuestions() {
        let questions = seededQuestions(count: 7) + userCreatedQuestions(count: 5)
        let date = Date(timeIntervalSince1970: 1_774_627_200)

        let selectedQuestions = selector.select(from: questions, on: date)

        XCTAssertEqual(selectedQuestions.count, 7)
        XCTAssertTrue(selectedQuestions.allSatisfy { $0.source == .seeded })
    }

    func testReturnsAllEligibleQuestionsWhenFewerThanRequested() {
        let questions = seededQuestions(count: 3) + userCreatedQuestions(count: 5)
        let date = Date(timeIntervalSince1970: 1_774_627_200)

        let selectedQuestions = selector.select(from: questions, on: date)

        XCTAssertEqual(selectedQuestions.count, 3)
        XCTAssertEqual(Set(selectedQuestions.map(\.contentId)), Set(["seeded-1", "seeded-2", "seeded-3"]))
    }

    /// Pins the selection against the hex-string ranking this selector used before the digest was
    /// stored as integer words. Lexicographic order over lowercase hex encodings and over the
    /// underlying digest bytes are the same ordering, so the selection must be byte-identical.
    func testSelectionMatchesHexStringRanking() {
        let questions = seededQuestions(count: 120)

        for dayOffset in 0 ..< 5 {
            let date = Date(timeIntervalSince1970: 1_774_627_200 + Double(dayOffset) * 86_400)

            let selected = selector.select(from: questions, on: date).map(\.contentId)
            let expected = Self.hexRankedSelection(
                from: questions,
                on: date,
                count: 7,
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current
            )

            XCTAssertEqual(selected, expected, "Selection diverged for day offset \(dayOffset)")
        }
    }

    /// The pre-refactor ranking, kept here as the reference implementation.
    private static func hexRankedSelection(
        from questions: [Question],
        on date: Date,
        count: Int,
        timeZone: TimeZone
    ) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )

        var ranked: [(contentId: String, rank: String)] = []
        for question in questions where question.source == .seeded {
            let payload: String = "\(dayKey)|\(question.contentId)"
            let digest = SHA256.hash(data: Data(payload.utf8))
            let hex: String = digest.map { byte in String(format: "%02x", byte) }.joined()
            ranked.append((contentId: question.contentId, rank: hex))
        }

        ranked.sort { lhs, rhs in
            if lhs.rank == rhs.rank {
                return lhs.contentId < rhs.contentId
            }
            return lhs.rank < rhs.rank
        }

        return ranked.prefix(count).map(\.contentId)
    }

    func testNegativeRequestedCountReturnsNoQuestions() {
        let selector = TodaysQuestionSelector(
            count: -1,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )

        let selectedQuestions = selector.select(
            from: seededQuestions(count: 3),
            on: Date(timeIntervalSince1970: 1_774_627_200)
        )

        XCTAssertTrue(selectedQuestions.isEmpty)
    }

    private func seededQuestions(count: Int) -> [Question] {
        (1...count).map { index in
            makeQuestion(
                id: "seeded-\(index)",
                category: Question.categories[(index - 1) % Question.categories.count],
                source: .seeded
            )
        }
    }

    private func userCreatedQuestions(count: Int) -> [Question] {
        (1...count).map { index in
            makeQuestion(
                id: "user-\(index)",
                category: Question.categories[(index - 1) % Question.categories.count],
                source: .userCreated
            )
        }
    }

    private func makeQuestion(
        id: String,
        contentId: String? = nil,
        category: String,
        source: QuestionSource
    ) -> Question {
        Question(
            id: id,
            text: "Question \(id)",
            category: category,
            contentId: contentId ?? id,
            source: source
        )
    }
}
