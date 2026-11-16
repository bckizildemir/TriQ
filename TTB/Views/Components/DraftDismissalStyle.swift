/// How a swipe that would close the answer editor treats an unsaved draft.
enum DraftDismissalStyle: Equatable {
    /// The swipe asks to save or drop the draft (iOS 27 sheets).
    case confirmationDialog
    /// The swipe is refused while the draft has changes; the Close button still asks.
    case blockSwipe

    /// - Parameters:
    ///   - isInZoomCover: The editor sits in the card-zoom `fullScreenCover`. No documentation says
    ///     the iOS 27 dismissal dialog hooks the zoom's swipe on a cover, but blocking interactive
    ///     dismissal does (`isModalInPresentation`). Never losing a typed answer wins, so the
    ///     cover always blocks.
    ///   - dialogAvailable: The OS has `dismissalConfirmationDialog` (iOS 27).
    static func resolve(isInZoomCover: Bool, dialogAvailable: Bool) -> DraftDismissalStyle {
        dialogAvailable && !isInZoomCover ? .confirmationDialog : .blockSwipe
    }
}
