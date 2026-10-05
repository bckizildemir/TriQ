import XCTest
@testable import TTB

final class QuickAnswerSuggestionTests: XCTestCase {
    func testQuickAnswerCandidatesAggregateCountsAndExcludeDuplicates() {
        let question = Question(
            id: "q1",
            text: "En sevdiğin renkler neler?",
            category: "Personal",
            answerStats: [
                "0": [
                    "Blue": 3,
                    "  green ": 2
                ],
                "1": [
                    "blue": 4,
                    "Red": 5
                ],
                "2": [
                    "GREEN": 3,
                    "": 10
                ]
            ]
        )

        let candidates = question.quickAnswerCandidates(limit: 3, excluding: ["green"])

        XCTAssertEqual(candidates, ["Blue", "Red"])
    }

    func testQuickAnswerCandidatesCanFilterToQuestionLanguage() {
        let question = Question(
            id: "q-english",
            text: "What were the first things that came to your mind when you woke up in the morning?",
            category: "Daily",
            answerStats: [
                "0": [
                    "Karar verdim": 10,
                    "Checked the time": 4
                ],
                "1": [
                    "Ruyami hatirlamaya calistim": 8,
                    "My meeting": 3
                ],
                "2": [
                    "Coffee": 2
                ]
            ]
        )

        let candidates = question.quickAnswerCandidates(limit: 5, preferredLanguageCode: "en")

        XCTAssertEqual(candidates, ["Checked the time", "My meeting", "Coffee"])
    }

    func testQuickAnswerCandidatesFilterPartyGameSuggestionsToTurkish() {
        let question = Question(
            id: "q-party-games",
            text: "What are your 3 favorite party games?",
            category: "Creativity",
            answerStats: [
                "0": [
                    "Kaos oyunu": 8,
                    "Truth or Dare": 7
                ],
                "1": [
                    "Pictionary": 6,
                    "Sessiz sinema": 5
                ],
                "2": [
                    "Charades": 4,
                    "Tabu": 3
                ]
            ]
        )

        let candidates = question.quickAnswerCandidates(limit: 5, preferredLanguageCode: "tr")

        XCTAssertEqual(candidates, ["Kaos oyunu", "Sessiz sinema", "Tabu"])
    }

    func testQuickAnswerCandidatesSaturateOverflowAndIgnoreNonPositiveCounts() {
        let question = Question(
            id: "q-corrupted-stats",
            text: "What are your favorites?",
            category: "Personal",
            answerStats: [
                "0": [
                    "Safe answer": Int.max,
                    "Poisoned answer": -1,
                ],
                "1": [
                    " safe answer ": 1,
                    "Zero answer": 0,
                ],
            ]
        )

        let candidates = question.quickAnswerCandidates(limit: 3)

        XCTAssertEqual(candidates, ["Safe answer"])
    }

    func testMergePrioritizesLocalThenAIFallbackWithoutRepeats() {
        let merged = QuickAnswerSuggestionResolver.merge(
            localCandidates: ["Blue", "Green"],
            aiCandidates: ["green", "Red", "Blue", "Yellow"],
            excluding: ["Purple"],
            limit: 4
        )

        XCTAssertEqual(merged, ["Blue", "Green", "Red", "Yellow"])
    }
}
