import SwiftUI

extension View {
    /// Keeps a swipe down on an enclosing sheet from dropping an unsaved answer draft.
    ///
    /// Below iOS 27 the sheet springs back while there are changes. From iOS 27 the swipe asks to
    /// save or drop instead; interactive dismissal must stay enabled there, or the dialog never
    /// fires. Both reach the nearest sheet, so they do nothing in a pushed or full-screen editor.
    /// `onSave` must not dismiss: the dialog's actions let the system finish the dismissal.
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

    func body(content: Content) -> some View {
        // The iOS 26 SDK marks this API unavailable on iOS, so `#available` alone cannot hide it
        // from an Xcode 26 build (CI). Swift 6.4 ships with Xcode 27, the first SDK that has it.
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
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
