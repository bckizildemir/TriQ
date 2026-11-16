import Testing
@testable import TTB

/// `DraftDismissalStyle` — what a swipe that would close the answer editor does to an unsaved
/// draft. The card-zoom cover must never let the swipe drop typed text.
struct DraftDismissalStyleTests {
    @Test(arguments: [true, false])
    func zoomCoverAlwaysBlocksTheSwipe(dialogAvailable: Bool) {
        let style = DraftDismissalStyle.resolve(isInZoomCover: true, dialogAvailable: dialogAvailable)

        #expect(style == .blockSwipe)
    }

    @Test func sheetOnIOS27AsksToSaveOrDrop() {
        let style = DraftDismissalStyle.resolve(isInZoomCover: false, dialogAvailable: true)

        #expect(style == .confirmationDialog)
    }

    @Test func sheetBeforeIOS27BlocksTheSwipe() {
        let style = DraftDismissalStyle.resolve(isInZoomCover: false, dialogAvailable: false)

        #expect(style == .blockSwipe)
    }
}
