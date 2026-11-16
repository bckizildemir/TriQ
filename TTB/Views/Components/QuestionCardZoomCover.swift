import SwiftUI

extension EnvironmentValues {
    /// The namespace a screen's question cards register their zoom source in. `nil` outside a
    /// screen that presents through `questionCardZoomCover`, so a card there is no zoom source.
    @Entry var questionCardZoomNamespace: Namespace.ID? = nil

    /// The view sits in the card-zoom cover, whose zoom brings a swipe-down to close.
    @Entry var isInQuestionCardZoomCover = false
}

extension View {
    /// Presents the answer editor in a full-screen cover that grows out of the tapped question
    /// card and shrinks back into it, like the App Store's Today cards. Use it in place of
    /// `fullScreenCover(item:)` on a screen that lists question cards.
    ///
    /// The zoom is the system's (`navigationTransition(.zoom)`, iOS 18), so it also gives the
    /// swipe-down to close. With Reduce Motion the cover fades instead (iOS 27; before that it
    /// slides up). An item whose card cannot be named opens with the standard cover.
    ///
    /// - Parameters:
    ///   - item: The question to open; `nil` closes the cover.
    ///   - cardSourceID: The `sourceID` the screen gives its cards, when it has one card list.
    ///     A screen with several lists sets `ExpandedQuestionState.cardSourceID` instead.
    ///   - content: The cover's content, usually `QuestionDetailModalShell`.
    func questionCardZoomCover<CoverContent: View>(
        item: Binding<ExpandedQuestionState?>,
        cardSourceID: String? = nil,
        @ViewBuilder content: @escaping (ExpandedQuestionState) -> CoverContent
    ) -> some View {
        modifier(
            QuestionCardZoomCoverModifier(
                item: item,
                cardSourceID: cardSourceID,
                coverContent: content
            )
        )
    }

    /// Marks a question card as the view the answer editor zooms out of and back into.
    /// Does nothing outside a screen that presents through `questionCardZoomCover`.
    func questionCardZoomSource(cardSourceID: String, questionID: String) -> some View {
        modifier(
            QuestionCardZoomSourceModifier(
                transitionID: QuestionCardZoom.transitionID(
                    cardSourceID: cardSourceID,
                    questionID: questionID
                )
            )
        )
    }
}

private struct QuestionCardZoomCoverModifier<CoverContent: View>: ViewModifier {
    @Binding var item: ExpandedQuestionState?
    let cardSourceID: String?
    let coverContent: (ExpandedQuestionState) -> CoverContent

    @Namespace private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // On the screen only, not on the cover: cards inside the editor's own sheets must
            // not register as sources of this zoom.
            .environment(\.questionCardZoomNamespace, zoomNamespace)
            .fullScreenCover(item: $item) { state in
                QuestionCardZoomTransitionHost(
                    style: QuestionCardZoom.style(
                        for: state,
                        fallbackCardSourceID: cardSourceID,
                        reduceMotion: reduceMotion
                    ),
                    namespace: zoomNamespace
                ) {
                    coverContent(state)
                }
                .environment(\.isInQuestionCardZoomCover, true)
            }
    }
}

/// The cover's root. It keeps the style it opened with: a style change while the editor is open
/// (Reduce Motion turned on) would swap the branch below, rebuild the editor and drop its draft.
private struct QuestionCardZoomTransitionHost<Content: View>: View {
    @State private var style: QuestionCardZoom.Style
    let namespace: Namespace.ID
    let content: Content

    init(
        style: QuestionCardZoom.Style,
        namespace: Namespace.ID,
        @ViewBuilder content: () -> Content
    ) {
        _style = State(initialValue: style)
        self.namespace = namespace
        self.content = content()
    }

    var body: some View {
        switch style {
        case .zoom(let transitionID):
            content
                .navigationTransition(.zoom(sourceID: transitionID, in: namespace))
        case .crossFade:
            content
                .backport.crossFadeNavigationTransition()
        case .standard:
            content
        }
    }
}

private struct QuestionCardZoomSourceModifier: ViewModifier {
    let transitionID: String

    @Environment(\.questionCardZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content
                .matchedTransitionSource(id: transitionID, in: namespace) { source in
                    // The card's own corners, so the editor grows out of the card's shape.
                    source
                        .clipShape(.rect(cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius))
                }
        } else {
            content
        }
    }
}
