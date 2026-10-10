import Foundation

#if DEBUG
enum UITestHomeFixture {
    static let categoryID = "Career"
    static let firstQuestionID = "home-question-1"

    static let questions: [Question] = [
        Question(
            id: firstQuestionID,
            text: "What kind of progress would make this week feel meaningful for your work?",
            category: categoryID,
            localizedTexts: [
                "en": "What kind of progress would make this week feel meaningful for your work?"
            ]
        )
    ]

    static let savedAnswerText = "Ship the onboarding fix"

    /// A saved answer on the first question, for tests that edit it and then drop or keep the draft.
    static func savedAnswers(userId: String) -> [String: UserAnswer] {
        [
            firstQuestionID: UserAnswer(
                questionId: firstQuestionID,
                userId: userId,
                answers: [savedAnswerText, "", ""],
                answeredAt: Date(timeIntervalSince1970: 200)
            )
        ]
    }

    static let categories: [Category] = Category.defaultCategories.filter {
        $0.id == "Daily" || $0.id == categoryID
    }
}
#endif
