import Testing
@testable import TTB

struct AnswerImageViewerDismissalTests {
    @Test func longSlowDragDismisses() {
        #expect(AnswerImageViewerDismissal.shouldDismiss(translation: 120, predictedEndTranslation: 130))
        #expect(AnswerImageViewerDismissal.shouldDismiss(translation: -120, predictedEndTranslation: -130))
    }

    @Test func shortFastFlickDismisses() {
        #expect(AnswerImageViewerDismissal.shouldDismiss(translation: 60, predictedEndTranslation: 400))
        #expect(AnswerImageViewerDismissal.shouldDismiss(translation: -60, predictedEndTranslation: -400))
    }

    @Test func shortSlowDragSnapsBack() {
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: 40, predictedEndTranslation: 60))
    }

    @Test func thresholdsAreExclusive() {
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: 100, predictedEndTranslation: 200))
    }

    @Test func longDragFlickedBackStaysOpen() {
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: 150, predictedEndTranslation: 0))
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: 150, predictedEndTranslation: -20))
    }

    @Test func longDragFlickedMostlyBackStaysOpen() {
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: 150, predictedEndTranslation: 40))
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: -150, predictedEndTranslation: -40))
    }

    @Test func fastFlickAgainstTheDragStaysOpen() {
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: 60, predictedEndTranslation: -300))
        #expect(!AnswerImageViewerDismissal.shouldDismiss(translation: -60, predictedEndTranslation: 300))
    }
}
