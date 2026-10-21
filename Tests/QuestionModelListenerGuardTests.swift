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

        completions[0]([makeQuestion(id: "stale")])
        #expect(model.questions.isEmpty)

        completions[1]([makeQuestion(id: "current")])
        #expect(model.questions.map(\.id) == ["current"])
    }

    private func liveCount(_ feed: Feed, in fake: FakeQuestionFeedListener) async -> Int {
        await fake.registrations(for: feed).count { !$0.isRemoved }
    }

    private func makeQuestion(id: String) -> Question {
        Question(id: id, text: "Question \(id)", category: Question.categories[0], contentId: id, source: .seeded)
    }
}
