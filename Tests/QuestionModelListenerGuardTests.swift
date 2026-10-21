import Foundation
import Testing
@testable import TTB

@MainActor
struct QuestionModelListenerGuardTests {
    typealias Feed = FakeQuestionFeedListener.Feed

    @Test func overlappingRefreshesKeepOneSeededAndOneFeaturedRegistration() async {
        let fake = FakeQuestionFeedListener(holding: [.seeded])
        let model = QuestionModel(listenerService: fake)

        let first = Task { await model.refreshQuestions() }
        let second = Task { await model.refreshQuestions() }
        await fake.waitUntilHeld(.seeded, count: 2)
        await fake.release(.seeded, at: 0)
        await fake.release(.seeded, at: 1)
        await first.value
        await second.value

        // The older call lost the race, so it never reached the featured feed.
        #expect(await liveCount(.seeded, in: fake) == 1)
        #expect(await liveCount(.featuredHome, in: fake) == 1)
        #expect(await liveCount(.trio, in: fake) == 1)
        #expect(await fake.registrations(for: .seeded).first?.isRemoved == true)
    }

    @Test func overlappingRefreshesKeepOneTrioRegistration() async {
        let fake = FakeQuestionFeedListener(holding: [.trio])
        let model = QuestionModel(listenerService: fake)

        let first = Task { await model.refreshQuestions() }
        let second = Task { await model.refreshQuestions() }
        await fake.waitUntilHeld(.trio, count: 2)
        await fake.release(.trio, at: 0)
        await fake.release(.trio, at: 1)
        await first.value
        await second.value

        #expect(await liveCount(.trio, in: fake) == 1)
        #expect(await fake.registrations(for: .trio).first?.isRemoved == true)
    }

    @Test func aDeliveryFromAnOverwrittenListenerDoesNotChangeQuestions() async {
        let fake = FakeQuestionFeedListener()
        let model = QuestionModel(listenerService: fake)

        await model.refreshQuestions()
        await model.refreshQuestions()
        let completions = await fake.completions(for: .seeded)
        #expect(completions.count == 2)

        completions[0](.success([makeQuestion(id: "stale")]))
        #expect(model.questions.isEmpty)

        completions[1](.success([makeQuestion(id: "current")]))
        #expect(model.questions.map(\.id) == ["current"])
    }

    @Test func aSignOutDuringSeededSetupLeavesNoListenerAndNoState() async {
        let fake = FakeQuestionFeedListener(holding: [.seeded])
        let model = QuestionModel(listenerService: fake)

        let session = Task { await model.startRemoteSession() }
        await fake.waitUntilHeld(.seeded, count: 1)
        model.clearRemoteState()
        await fake.release(.seeded, at: 0)
        await session.value

        for feed in [Feed.seeded, .featuredHome, .trio, .userAnswers] {
            #expect(await liveCount(feed, in: fake) == 0)
        }
        // The later steps never ran.
        #expect(await fake.registrations(for: .featuredHome).isEmpty)
        #expect(await fake.registrations(for: .trio).isEmpty)
        #expect(await fake.registrations(for: .userAnswers).isEmpty)
        #expect(model.questions.isEmpty)
        #expect(model.trioQuestions.isEmpty)
        #expect(model.currentUserAnswers.isEmpty)
        #expect(!model.isLoading)
    }

    @Test func aSignOutDuringUserAnswersSetupCancelsItsHandle() async {
        let fake = FakeQuestionFeedListener(holding: [.userAnswers])
        let model = QuestionModel(listenerService: fake)

        let session = Task { await model.startRemoteSession() }
        await fake.waitUntilHeld(.userAnswers, count: 1)
        model.clearRemoteState()
        await fake.release(.userAnswers, at: 0)
        await session.value

        #expect(await fake.registrations(for: .userAnswers).count == 1)
        #expect(await liveCount(.userAnswers, in: fake) == 0)
    }

    @Test func aUserAnswersDeliveryFromBeforeSignOutIsDropped() async {
        let fake = FakeQuestionFeedListener()
        let model = QuestionModel(listenerService: fake)

        await model.startRemoteSession()
        let completions = await fake.userAnswersCompletions()
        #expect(completions.count == 1)
        model.clearRemoteState()

        let answer = UserAnswer(questionId: "q1", userId: "a", answers: ["x"], answeredAt: Date())
        completions[0](["q1": answer])
        #expect(model.currentUserAnswers.isEmpty)
    }

    @Test func aSeededDeliveryFromBeforeSignOutIsDropped() async {
        let fake = FakeQuestionFeedListener()
        let model = QuestionModel(listenerService: fake)

        await model.startRemoteSession()
        let completions = await fake.completions(for: .seeded)
        model.clearRemoteState()

        completions[0](.success([makeQuestion(id: "stale")]))
        #expect(model.questions.isEmpty)
    }

    @Test func aSeededFailureEndsLoadingSurfacesAnErrorAndKeepsQuestions() async throws {
        let fake = FakeQuestionFeedListener()
        let model = QuestionModel(listenerService: fake)

        await model.refreshQuestions()
        let first = try #require(await fake.completions(for: .seeded).last)
        first(.success([makeQuestion(id: "kept")]))
        await model.refreshQuestions()
        #expect(model.isLoading)

        let second = try #require(await fake.completions(for: .seeded).last)
        second(.failure(URLError(.notConnectedToInternet)))

        #expect(!model.isLoading)
        #expect(model.error != nil)
        #expect(model.questions.map(\.id) == ["kept"])
    }

    @Test func aSeededFailureAfterSignOutLeavesNoError() async {
        let fake = FakeQuestionFeedListener()
        let model = QuestionModel(listenerService: fake)

        await model.startRemoteSession()
        let completions = await fake.completions(for: .seeded)
        model.clearRemoteState()

        completions[0](.failure(URLError(.notConnectedToInternet)))
        #expect(model.error == nil)
        #expect(!model.isLoading)
    }

    @Test func aSeededFailureFromAnOverwrittenListenerLeavesNoErrorAndKeepsLoading() async {
        let fake = FakeQuestionFeedListener()
        let model = QuestionModel(listenerService: fake)

        await model.refreshQuestions()
        await model.refreshQuestions()
        let completions = await fake.completions(for: .seeded)
        #expect(completions.count == 2)

        completions[0](.failure(URLError(.notConnectedToInternet)))
        #expect(model.error == nil)
        #expect(model.isLoading)
    }

    @Test func aTrioFailureLeavesNoErrorAndKeepsTrioQuestions() async throws {
        let fake = FakeQuestionFeedListener()
        let model = QuestionModel(listenerService: fake)

        await model.refreshQuestions()
        let completions = await fake.completions(for: .trio)
        let trioQuestion = Question(
            id: "trio",
            text: "Question trio",
            category: Question.categories[0],
            contentId: "trio",
            languageCode: AppLocalization.currentLanguageCode,
            source: .userCreated
        )
        completions[0](.success([trioQuestion]))
        #expect(model.trioQuestions.map(\.id) == ["trio"])

        completions[0](.failure(URLError(.notConnectedToInternet)))

        #expect(model.error == nil)
        #expect(model.trioQuestions.map(\.id) == ["trio"])
    }

    private func liveCount(_ feed: Feed, in fake: FakeQuestionFeedListener) async -> Int {
        await fake.registrations(for: feed).count { !$0.isRemoved }
    }

    private func makeQuestion(id: String) -> Question {
        Question(id: id, text: "Question \(id)", category: Question.categories[0], contentId: id, source: .seeded)
    }
}
