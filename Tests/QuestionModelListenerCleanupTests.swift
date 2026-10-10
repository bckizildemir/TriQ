import Testing
@testable import TTB

@MainActor
struct QuestionModelListenerCleanupTests {
    @Test func releasingTheModelRemovesEveryFirestoreListener() {
        let seeded = MockQuestionListListenerRegistration()
        let featuredHome = MockQuestionListListenerRegistration()
        let trio = MockQuestionListListenerRegistration()
        let userAnswers = MockQuestionListListenerRegistration()
        var model: QuestionModel? = QuestionModel(localQuestions: [])
        model?.installListenersForTesting(
            seeded: FirestoreListenerHandle(registration: seeded),
            featuredHome: FirestoreListenerHandle(registration: featuredHome),
            trio: FirestoreListenerHandle(registration: trio),
            userAnswers: FirestoreListenerHandle(registration: userAnswers)
        )
        weak let releasedModel = model

        model = nil

        #expect(releasedModel == nil)
        #expect(seeded.isRemoved)
        #expect(featuredHome.isRemoved)
        #expect(trio.isRemoved)
        #expect(userAnswers.isRemoved)
    }
}
