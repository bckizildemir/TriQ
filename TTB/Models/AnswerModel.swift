import Foundation
import FirebaseFirestore

struct AnswerStatistics {
    let dailyCount: Int
    let weeklyCount: Int
    let totalCount: Int
}

/// Manages aggregate answer statistics. The answered-questions list is derived
/// directly from QuestionModel.currentUserAnswers in AnswersContentView.
@MainActor
class AnswerModel: ObservableObject {
    @Published var error: String?
    @Published private(set) var statistics = AnswerStatistics(dailyCount: 0, weeklyCount: 0, totalCount: 0)

    private let answerService: AnswerService

    init(answerService: AnswerService = AnswerService()) {
        self.answerService = answerService
    }

    func fetchStatistics() async {
        do {
            statistics = try await answerService.getAnswerStatistics()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
