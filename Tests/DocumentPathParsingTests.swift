import Testing
@testable import TTB

/// The parent-document id reads that used to sit inside Firebase closures
/// (`reference.parent.parent?.documentID`). Each parser takes `reference.path`.
struct DocumentPathParsingTests {
    @Test(arguments: [
        ("questions/q1/userAnswers/u1", "q1"),
        ("/questions/q1/userAnswers/u1", "q1"),
        ("a/b/questions/q2/userAnswers/u2", "q2"),
    ])
    func answerProgressReadsTheQuestionId(path: String, expected: String) {
        #expect(AnswerProgressService.questionId(fromUserAnswerPath: path) == expected)
    }

    @Test(arguments: ["", "/", "questions", "questions/q1", "userAnswers/u1/", "q1/u1/x"])
    func answerProgressReturnsEmptyForAPathWithoutAParentDocument(path: String) {
        #expect(AnswerProgressService.questionId(fromUserAnswerPath: path).isEmpty)
    }

    @Test(arguments: [
        ("questions/q1/userAnswers/u1", "q1"),
        ("questions/q1/userAnswers/u1/", "q1"),
    ])
    func questionServiceReadsTheQuestionId(path: String, expected: String) {
        #expect(QuestionService.questionId(fromUserAnswerPath: path) == expected)
    }

    @Test(arguments: ["", "/", "questions", "questions/q1", "questions/q1/userAnswers"])
    func questionServiceReturnsEmptyForAPathWithoutAParentDocument(path: String) {
        #expect(QuestionService.questionId(fromUserAnswerPath: path).isEmpty)
    }

    @Test func shareServiceReadsTheShareId() {
        #expect(QuestionListShareService.shareId(fromRecipientPath: "questionListShares/s1/recipients/r1") == "s1")
    }

    @Test(arguments: ["", "/", "recipients", "recipients/r1", "questionListShares/s1/recipients"])
    func shareServiceReturnsNilForAPathWithoutAParentDocument(path: String) {
        #expect(QuestionListShareService.shareId(fromRecipientPath: path) == nil)
    }
}
