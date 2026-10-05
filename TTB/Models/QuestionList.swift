import FirebaseFirestore
import Foundation

struct QuestionList: Identifiable, Equatable {
    let id: String
    let ownerId: String
    var name: String
    var questionIds: [String]
    let visibility: String
    let createdAt: Date
    var updatedAt: Date

    static func fromFirestore(_ data: [String: Any], id: String) -> QuestionList? {
        guard let ownerId = data["ownerId"] as? String,
              let name = data["name"] as? String
        else {
            return nil
        }

        let questionIds = data["questionIds"] as? [String] ?? []
        let visibility = data["visibility"] as? String ?? "private"
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        return QuestionList(
            id: id,
            ownerId: ownerId,
            name: name,
            questionIds: questionIds,
            visibility: visibility,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
