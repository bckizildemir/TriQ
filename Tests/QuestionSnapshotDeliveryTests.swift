import FirebaseFirestore
import Foundation
import os
import Testing
@testable import TTB

/// The path a live Firestore snapshot takes from a `QuestionService` listener closure to
/// `QuestionModel`: map the documents, then hop to the main actor. `QuestionModel` tests never
/// start a live listener, so this path is tested here on its own, without Firebase.
struct QuestionSnapshotDeliveryTests {
    private let logger = Logger(subsystem: "TTBTests", category: "QuestionSnapshotDeliveryTests")

    // MARK: - Question feeds

    @Test func validDocumentsMapToQuestionsAndInvalidOnesAreDropped() throws {
        let questions = QuestionService.questions(
            fromSnapshot: [
                (id: "q1", data: ["text": "First?", "category": "life"]),
                (id: "broken", data: ["text": "No category"]),
            ],
            error: nil,
            feed: "Test",
            logger: logger
        )

        #expect(try #require(questions).map(\.id) == ["q1"])
    }

    @Test func aListenerErrorMapsToNothingToDeliver() {
        let questions = QuestionService.questions(
            fromSnapshot: [(id: "q1", data: ["text": "First?", "category": "life"])],
            error: URLError(.notConnectedToInternet),
            feed: "Test",
            logger: logger
        )

        #expect(questions == nil)
    }

    @Test func aMissingSnapshotMapsToNothingToDeliver() {
        let questions = QuestionService.questions(
            fromSnapshot: nil,
            error: nil,
            feed: "Test",
            logger: logger
        )

        #expect(questions == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func questionsReachTheCallbackOnTheMainActor() async {
        let questions: [Question] = await withCheckedContinuation { continuation in
            QuestionService.deliverQuestions(
                documents: [(id: "q1", data: ["text": "First?", "category": "life"])],
                error: nil,
                feed: "Test",
                logger: logger
            ) { questions in
                MainActor.assertIsolated()
                continuation.resume(returning: questions)
            }
        }

        #expect(questions.map(\.id) == ["q1"])
    }

    // MARK: - User answers

    @Test func answerDocumentsMapToAnswersKeyedByTheirQuestion() throws {
        let answeredAt = Date(timeIntervalSince1970: 1_000)
        let answers = try #require(QuestionService.userAnswers(
            fromSnapshot: [
                (
                    path: "questions/q1/userAnswers/user-1",
                    data: [
                        "answers": ["a", "b", "c"],
                        "answeredAt": Timestamp(date: answeredAt),
                        "imageURLs": ["https://example.com/1.jpg", "", "https://example.com/3.jpg"],
                    ]
                ),
                (path: "userAnswers/orphan", data: ["answers": ["x"]]),
            ],
            error: nil,
            userId: "user-1",
            logger: logger
        ))

        #expect(answers.keys.sorted() == ["q1"])
        let answer = try #require(answers["q1"])
        #expect(answer.questionId == "q1")
        #expect(answer.userId == "user-1")
        #expect(answer.answers == ["a", "b", "c"])
        #expect(answer.answeredAt == answeredAt)
        #expect(answer.imageURLs == ["https://example.com/1.jpg", nil, "https://example.com/3.jpg"])
        #expect(answer.imageAttributions == [nil, nil, nil])
    }

    @Test func aMissingAnswersSnapshotMapsToNoAnswers() {
        let answers = QuestionService.userAnswers(
            fromSnapshot: nil,
            error: nil,
            userId: "user-1",
            logger: logger
        )

        #expect(answers?.isEmpty == true)
    }

    @Test func anAnswersListenerErrorMapsToNothingToDeliver() {
        let answers = QuestionService.userAnswers(
            fromSnapshot: [(path: "questions/q1/userAnswers/user-1", data: [:])],
            error: URLError(.notConnectedToInternet),
            userId: "user-1",
            logger: logger
        )

        #expect(answers == nil)
    }

    @Test(arguments: [
        ("questions/q1/userAnswers/user-1", "q1"),
        ("archive/2026/questions/q9/userAnswers/user-1", "q9"),
        ("userAnswers/user-1", nil),
    ] as [(String, String?)])
    func theOwningQuestionIsTheDocumentTwoLevelsUp(path: String, questionID: String?) {
        #expect(QuestionService.questionID(fromUserAnswerPath: path) == questionID)
    }

    @Test(.timeLimit(.minutes(1)))
    func answersReachTheCallbackOnTheMainActor() async {
        let answers: [String: UserAnswer] = await withCheckedContinuation { continuation in
            QuestionService.deliverUserAnswers(
                documents: [(path: "questions/q1/userAnswers/user-1", data: ["answers": ["a"]])],
                error: nil,
                userId: "user-1",
                logger: logger
            ) { answers in
                MainActor.assertIsolated()
                continuation.resume(returning: answers)
            }
        }

        #expect(answers["q1"]?.answers == ["a"])
    }
}
