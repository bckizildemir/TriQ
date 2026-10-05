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

    static let categories: [Category] = Category.defaultCategories.filter {
        $0.id == "Daily" || $0.id == categoryID
    }
}
#endif
