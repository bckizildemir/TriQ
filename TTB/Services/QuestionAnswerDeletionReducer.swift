import Foundation

struct QuestionAnswerAggregateState: Equatable {
    var answerStats: [String: [String: Int]]
    var totalRespondents: Int
    var todayRespondents: Int
    var todayDate: String
    var lastAnsweredAt: Date?
}

enum QuestionAnswerDeletionReducer {
    static func apply(
        to state: QuestionAnswerAggregateState,
        removingAnswers answers: [String],
        answeredAt: Date,
        replacementLastAnsweredAt: Date?
    ) -> QuestionAnswerAggregateState {
        var updatedState = state
        updatedState.answerStats = normalizedAnswerStats(state.answerStats)
        updatedState.todayRespondents = max(0, state.todayRespondents)

        for (index, answer) in answers.enumerated() where !answer.isEmpty {
            let slotKey = "\(index)"
            guard var slotStats = updatedState.answerStats[slotKey] else { continue }

            let updatedCount = decrementedCount(slotStats[answer] ?? 0)
            if updatedCount == 0 {
                slotStats.removeValue(forKey: answer)
            } else {
                slotStats[answer] = updatedCount
            }

            if slotStats.isEmpty {
                updatedState.answerStats.removeValue(forKey: slotKey)
            } else {
                updatedState.answerStats[slotKey] = slotStats
            }
        }

        updatedState.totalRespondents = decrementedCount(state.totalRespondents)

        let answeredDateString = QuestionService.dateString(for: answeredAt)
        if state.todayDate == answeredDateString {
            updatedState.todayRespondents = decrementedCount(updatedState.todayRespondents)
        }
        if updatedState.todayRespondents == 0 {
            updatedState.todayDate = ""
        }

        updatedState.lastAnsweredAt = replacementLastAnsweredAt
        return updatedState
    }

    private static func decrementedCount(_ count: Int) -> Int {
        count > 0 ? count - 1 : 0
    }

    private static func normalizedAnswerStats(
        _ answerStats: [String: [String: Int]]
    ) -> [String: [String: Int]] {
        answerStats.reduce(into: [:]) { normalizedStats, slot in
            let positiveCounts = slot.value.filter { $0.value > 0 }
            if !positiveCounts.isEmpty {
                normalizedStats[slot.key] = positiveCounts
            }
        }
    }
}
