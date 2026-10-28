import Foundation
import Testing
@testable import TTB

@MainActor
struct AppDeepLinkRouterTests {
    private let questionURL = URL(string: "https://ttbp-9d652.web.app/q/question-1")!
    private let otherQuestionURL = URL(string: "https://ttbp-9d652.web.app/q/question-2")!
    private let listURL = URL(string: "https://ttbp-9d652.web.app/l/list-code")!

    @Test func questionLinkThenListLinkKeepsTheQuestionOpen() {
        let router = AppDeepLinkRouter()

        router.handle(questionURL)
        router.handle(listURL)

        #expect(router.sharedQuestion?.questionId == "question-1")
        #expect(router.sharedQuestionList == nil)
    }

    @Test func listLinkThenQuestionLinkKeepsTheListOpen() {
        let router = AppDeepLinkRouter()

        router.handle(listURL)
        router.handle(questionURL)

        #expect(router.sharedQuestionList?.shareCode == "list-code")
        #expect(router.sharedQuestion == nil)
    }

    @Test func secondQuestionLinkWaitsWhileOneIsOpen() {
        let router = AppDeepLinkRouter()

        router.handle(questionURL)
        router.handle(otherQuestionURL)

        #expect(router.sharedQuestion?.questionId == "question-1")
    }

    @Test func pendingLinkShowsWhenTheOpenOneCloses() {
        let router = AppDeepLinkRouter()
        router.handle(questionURL)
        router.handle(listURL)

        router.sharedQuestion = nil

        #expect(router.sharedQuestion == nil)
        #expect(router.sharedQuestionList?.shareCode == "list-code")
    }

    @Test func latestPendingLinkWins() {
        let router = AppDeepLinkRouter()
        router.handle(questionURL)
        router.handle(listURL)
        router.handle(otherQuestionURL)

        router.sharedQuestion = nil

        #expect(router.sharedQuestion?.questionId == "question-2")
        #expect(router.sharedQuestionList == nil)
    }

    @Test func sameQuestionLinkWhileOpenIsIgnoredAndDoesNotHoldTheRouter() {
        let router = AppDeepLinkRouter()
        let thirdURL = URL(string: "https://ttbp-9d652.web.app/q/question-3")!

        router.handle(questionURL)
        router.handle(questionURL)
        router.sharedQuestion = nil

        #expect(router.sharedQuestion == nil)
        #expect(router.sharedQuestionList == nil)

        router.handle(thirdURL)

        #expect(router.sharedQuestion?.questionId == "question-3")
    }

    @Test func sameListLinkWhileOpenIsIgnored() {
        let router = AppDeepLinkRouter()

        router.handle(listURL)
        router.handle(listURL)
        router.sharedQuestionList = nil

        #expect(router.sharedQuestion == nil)
        #expect(router.sharedQuestionList == nil)
    }

    @Test func linkShowsAtOnceWhenNothingIsOpen() {
        let router = AppDeepLinkRouter()

        router.handle(listURL)
        router.sharedQuestionList = nil
        router.handle(questionURL)

        #expect(router.sharedQuestion?.questionId == "question-1")
    }
}
