import Foundation

/// The rules behind the card-to-editor zoom: which card the answer editor grows out of, and how
/// it moves when it cannot zoom.
///
/// The editor opens in a `fullScreenCover` that uses the system zoom transition (iOS 18): the
/// tapped card grows into the editor, and closing shrinks the editor back into the card. A card
/// marks itself as the zoom source with the same transition ID the presenting screen computes, so
/// both sides must build it here.
enum QuestionCardZoom {
    /// How the editor's cover appears and goes away.
    enum Style: Equatable {
        /// Grows out of the card with this transition ID and shrinks back into it.
        case zoom(transitionID: String)
        /// Fades in and out (Reduce Motion). Before iOS 27 this is the standard cover.
        case crossFade
        /// The standard cover, which slides up from the bottom: there is no card to zoom from.
        case standard
    }

    /// The ID a card registers as its zoom source. A card's `sourceID` names the list it sits in
    /// (`home.today`, `favorites`), so the same question in two lists of one screen gets two IDs.
    /// The same shape as the card's accessibility identifier, `question-card-<sourceID>-<id>`.
    static func transitionID(cardSourceID: String, questionID: String) -> String {
        "\(cardSourceID)-\(questionID)"
    }

    /// The style for an editor opened with `state`.
    ///
    /// - Parameters:
    ///   - state: What the screen asked to open. Its `cardSourceID` wins when set: a screen with
    ///     more than one card list (Home) records which list the tapped card was in.
    ///   - fallbackCardSourceID: The `sourceID` of the screen's only card list, or `nil`.
    ///   - reduceMotion: The Reduce Motion setting when the editor opens.
    static func style(
        for state: ExpandedQuestionState,
        fallbackCardSourceID: String?,
        reduceMotion: Bool
    ) -> Style {
        guard let cardSourceID = state.cardSourceID ?? fallbackCardSourceID else {
            return .standard
        }

        if reduceMotion {
            return .crossFade
        }

        return .zoom(
            transitionID: transitionID(cardSourceID: cardSourceID, questionID: state.question.id)
        )
    }
}
