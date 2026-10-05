import Foundation

#if DEBUG
enum UITestCategoryQuestionsFixture {
    static let categoryID = "Career"
    static let firstQuestionID = "career-question-1"
    static let secondQuestionID = "career-question-2"
    static let thirdQuestionID = "career-question-3"

    static let questions: [Question] = [
        Question(
            id: firstQuestionID,
            text: "What currently feels most exciting or difficult on your career path?",
            category: categoryID,
            localizedTexts: [
                "en": "What currently feels most exciting or difficult on your career path?"
            ]
        ),
        Question(
            id: secondQuestionID,
            text: "Who are the mentors or role models that leave a mark on you?",
            category: categoryID,
            localizedTexts: [
                "en": "Who are the mentors or role models that leave a mark on you?"
            ],
            answerStats: [
                "0": [
                    "My manager": 8,
                    "My dad": 6,
                    "A close friend": 4
                ],
                "1": [
                    "My teacher": 5,
                    "A designer I follow": 3
                ]
            ]
        ),
        Question(
            id: thirdQuestionID,
            text: "Which habits are helping you become stronger at work this month?",
            category: categoryID,
            localizedTexts: [
                "en": "Which habits are helping you become stronger at work this month?"
            ]
        )
    ]

    static let userAnswers: [String: UserAnswer] = [
        firstQuestionID: UserAnswer(
            questionId: firstQuestionID,
            userId: "ui-test-user",
            answers: [
                "I am still at the beginning, but every step helps me discover what I care about and that uncertainty feels energizing.",
                "I am in the messy middle; I have momentum, but the path to the next level keeps narrowing and forcing sharper decisions.",
                "I am learning to value steady progress and to treat mistakes as useful signals instead of proof that I am behind."
            ],
            answeredAt: Date(timeIntervalSince1970: 1_717_000_000)
        )
    ]
}
#endif
