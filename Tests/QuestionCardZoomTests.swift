import Testing
@testable import TTB

/// `QuestionCardZoom` — which card the answer editor grows out of, and how it moves when it
/// cannot zoom. A card and its presenting screen must compute the same transition ID, or the
/// editor opens with no card to grow from.
struct QuestionCardZoomTests {
    private static var question: Question {
        Question(id: "q42", text: "Three good things today?", category: "Daily")
    }

    @Test func transitionIDJoinsTheListAndTheQuestionLikeTheCardsAccessibilityIdentifier() {
        let id = QuestionCardZoom.transitionID(cardSourceID: "home.today", questionID: "q42")

        #expect(id == "home.today-q42")
    }

    @Test func theSameQuestionInTwoListsGetsTwoTransitionIDs() {
        let today = QuestionCardZoom.transitionID(cardSourceID: "home.today", questionID: "q42")
        let category = QuestionCardZoom.transitionID(cardSourceID: "home.category.Daily", questionID: "q42")

        #expect(today != category)
    }

    @Test func screenWithOneCardListZoomsFromTheCardItsCardsRegister() {
        let state = ExpandedQuestionState(question: Self.question, headerStyle: .plain)

        let style = QuestionCardZoom.style(for: state, fallbackCardSourceID: "favorites", reduceMotion: false)

        let cardID = QuestionCardZoom.transitionID(cardSourceID: "favorites", questionID: Self.question.id)
        #expect(style == .zoom(transitionID: cardID))
    }

    @Test func listNamedInTheStateWinsOverTheScreensDefault() {
        let state = ExpandedQuestionState(
            question: Self.question,
            headerStyle: .plain,
            cardSourceID: "home.category.Daily"
        )

        let style = QuestionCardZoom.style(for: state, fallbackCardSourceID: "home.today", reduceMotion: false)

        #expect(style == .zoom(transitionID: "home.category.Daily-q42"))
    }

    @Test func noCardToZoomFromOpensTheStandardCover() {
        let state = ExpandedQuestionState(question: Self.question, headerStyle: .plain)

        let style = QuestionCardZoom.style(for: state, fallbackCardSourceID: nil, reduceMotion: false)

        #expect(style == .standard)
    }

    @Test func reduceMotionFadesInsteadOfZooming() {
        let state = ExpandedQuestionState(question: Self.question, headerStyle: .plain)

        let style = QuestionCardZoom.style(for: state, fallbackCardSourceID: "favorites", reduceMotion: true)

        #expect(style == .crossFade)
    }

    @Test func reduceMotionWithNoCardKeepsTheStandardCover() {
        let state = ExpandedQuestionState(question: Self.question, headerStyle: .plain)

        let style = QuestionCardZoom.style(for: state, fallbackCardSourceID: nil, reduceMotion: true)

        #expect(style == .standard)
    }
}
