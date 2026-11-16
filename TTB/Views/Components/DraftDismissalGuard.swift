import SwiftUI

extension View {
    /// Keeps a swipe that would close the editor from dropping an unsaved answer draft.
    ///
    /// In a sheet below iOS 27 the sheet springs back while there are changes. In a sheet from
    /// iOS 27 the swipe asks to save or drop instead; interactive dismissal must stay enabled
    /// there, or the dialog never fires. In the card-zoom `fullScreenCover` (see
    /// `questionCardZoomCover`), whose zoom brings a swipe-down to close, the swipe is refused
    /// while there are changes on every iOS: the Close button asks to save or drop. A pushed
    /// editor has no swipe to guard. `onSave` must not dismiss: the dialog's actions let the
    /// system finish the dismissal.
    func draftDismissalGuard(
        hasUnsavedChanges: Bool,
        onSave: @escaping () -> Void
    ) -> some View {
        modifier(DraftDismissalGuard(hasUnsavedChanges: hasUnsavedChanges, onSave: onSave))
    }
}

private struct DraftDismissalGuard: ViewModifier {
    let hasUnsavedChanges: Bool
    let onSave: () -> Void

    @Environment(\.isInQuestionCardZoomCover) private var isInZoomCover

    func body(content: Content) -> some View {
        // The iOS 26 SDK marks this API unavailable on iOS, so `#available` alone cannot hide it
        // from an Xcode 26 build (CI). Swift 6.4 ships with Xcode 27, the first SDK that has it.
        #if compiler(>=6.4)
        if #available(iOS 27, *),
           DraftDismissalStyle.resolve(isInZoomCover: isInZoomCover, dialogAvailable: true) == .confirmationDialog {
            content
                .dismissalConfirmationDialog(
                    "question.expanded.unsavedChangesTitle",
                    shouldPresent: hasUnsavedChanges
                ) {
                    Button(String(localized: "question.expanded.saveAndClose"), action: onSave)
                    // Destructive replaces the system close action; it just lets the sheet go.
                    Button(String(localized: "question.expanded.closeWithoutSaving"), role: .destructive) {}
                }
        } else {
            content
                .interactiveDismissDisabled(hasUnsavedChanges)
        }
        #else
        content
            .interactiveDismissDisabled(hasUnsavedChanges)
        #endif
    }
}
