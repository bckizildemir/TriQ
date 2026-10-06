import FirebaseFirestore
import Foundation
import Testing
@testable import TTB

@MainActor
struct QuestionModelListenerCleanupTests {
    @Test func releasingTheModelRemovesEveryFirestoreListener() {
        let seeded = FakeListenerRegistration()
        let featuredHome = FakeListenerRegistration()
        let trio = FakeListenerRegistration()
        let userAnswers = FakeListenerRegistration()
        var model: QuestionModel? = QuestionModel(localQuestions: [])
        model?.installListenersForTesting(
            seeded: seeded,
            featuredHome: featuredHome,
            trio: trio,
            userAnswers: userAnswers
        )
        weak var releasedModel = model

        model = nil

        #expect(releasedModel == nil)
        #expect(seeded.removeCount == 1)
        #expect(featuredHome.removeCount == 1)
        #expect(trio.removeCount == 1)
        #expect(userAnswers.removeCount == 1)
    }
}

private final class FakeListenerRegistration: NSObject, ListenerRegistration {
    private(set) var removeCount = 0

    func remove() {
        removeCount += 1
    }
}
