import XCTest
@testable import TTB

@MainActor
final class MostAnsweredViewModelTests: XCTestCase {
    func testLoadPublishesRankedItemsWithoutAnswerEnrichment() async {
        let dailyQuestion = Question(
            id: "q-daily",
            text: "Daily question?",
            category: "Daily",
            totalRespondents: 3,
            todayRespondents: 3
        )
        let allTimeQuestion = Question(
            id: "q-all-time",
            text: "All-time question?",
            category: "Goals",
            totalRespondents: 12
        )
        var loadCallCount = 0
        let viewModel = MostAnsweredViewModel {
            loadCallCount += 1
            return (
                [MostAnsweredItem(question: dailyQuestion, userAnswers: [])],
                [MostAnsweredItem(question: allTimeQuestion, userAnswers: [])]
            )
        }

        await viewModel.load()

        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(viewModel.dailyItems.map(\.question.id), [dailyQuestion.id])
        XCTAssertEqual(viewModel.allTimeItems.map(\.question.id), [allTimeQuestion.id])
        XCTAssertEqual(viewModel.dailyItems[0].userAnswers, [])
        XCTAssertEqual(viewModel.dailyItems[0].imageURLs, [nil, nil, nil])
    }

    func testItemResolvesLiveUserAnswersAndImageURLs() {
        let question = Question(
            id: "q-live-answer",
            text: "Question?",
            category: "Daily"
        )
        let item = MostAnsweredItem(
            question: question,
            userAnswers: ["Stale", "", ""],
            imageURLs: [nil, nil, nil]
        )
        let liveAnswer = UserAnswer(
            questionId: question.id,
            userId: "user-1",
            answers: ["Live", "Answer", ""],
            answeredAt: Date(timeIntervalSince1970: 456),
            imageURLs: ["https://example.com/live.jpg", nil, nil]
        )

        let resolvedItem = item.resolvingUserAnswer(liveAnswer)

        XCTAssertEqual(resolvedItem.question.id, question.id)
        XCTAssertEqual(resolvedItem.userAnswers, ["Live", "Answer", ""])
        XCTAssertEqual(resolvedItem.imageURLs, ["https://example.com/live.jpg", nil, nil])
    }

    func testItemKeepsPreloadedAnswersWhenNoLiveUserAnswerExists() {
        let question = Question(
            id: "q-preloaded",
            text: "Question?",
            category: "Daily"
        )
        let item = MostAnsweredItem(
            question: question,
            userAnswers: ["Preloaded", "", ""],
            imageURLs: [nil, "https://example.com/preloaded.jpg", nil]
        )

        let resolvedItem = item.resolvingUserAnswer(nil)

        XCTAssertEqual(resolvedItem.userAnswers, item.userAnswers)
        XCTAssertEqual(resolvedItem.imageURLs, item.imageURLs)
    }

    // The two tests that lived here drove MostAnsweredViewModel.updateLocalFavoriteState, a
    // third optimistic patcher over favorite state. FavoriteStore owns that state now, so the
    // patcher and its coverage are gone — see FavoriteStoreTests.
}
