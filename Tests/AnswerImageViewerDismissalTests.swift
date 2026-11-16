import Testing
@testable import TTB

struct AnswerImageViewerDismissalTests {
    @Test func longSlowDragDismisses() {
        #expect(AnswerImageViewerDismissal.shouldDismiss(translation: 120, predictedEndTranslation: 130))
        #expect(AnswerImageViewerDismissal.shouldDismiss(translation: -120, predictedEndTranslation: -130))
    }

    @Test func shortFastFlickDismisses() {
        #expect(AnswerImageViewerDismissal.shouldDismiss(translation: 60, predictedEndTranslation: 300))
        #expect(AnswerImageViewerDismissal.shouldDismiss(translation: -60, predictedEndTranslation: -300))
    }

    @Test func shortSlowDragSnapsBack() {
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: 40, predictedEndTranslation: 60))
    }

    @Test func thresholdsAreExclusive() {
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: 100, predictedEndTranslation: 240))
    }
}
