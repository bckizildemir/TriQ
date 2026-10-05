import Foundation
import FirebaseFirestore

actor AnswerService {
    private let db = Firestore.firestore()

    func getAnswerStatistics() async throws -> AnswerStatistics {
        let snapshot = try await db.collection("questions").getDocuments()
        let questions = snapshot.documents.compactMap { Question.fromFirestore($0.data(), id: $0.documentID) }
        
        let calendar = Calendar.current
        let now = Date()
        
        let dailyCount = questions.filter { question in
            guard let lastAnswered = question.lastAnsweredAt else { return false }
            return calendar.isDateInToday(lastAnswered)
        }.count
        
        let weeklyCount = questions.filter { question in
            guard let lastAnswered = question.lastAnsweredAt else { return false }
            let daysAgo = calendar.dateComponents([.day], from: lastAnswered, to: now).day ?? 0
            return daysAgo <= 7
        }.count
        
        let totalCount = questions.filter { !$0.answers.isEmpty }.count
        
        return AnswerStatistics(
            dailyCount: dailyCount,
            weeklyCount: weeklyCount,
            totalCount: totalCount
        )
    }
}
