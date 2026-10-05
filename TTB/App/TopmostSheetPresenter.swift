import UIKit

/// Presents one sheet from the topmost controller, driven by a flag the app root owns.
///
/// A SwiftUI `.sheet` presents only from the view it is attached to, so a root-owned sheet never
/// appears while a `fullScreenCover` is up. This presents over whatever is on top instead, which is
/// how the Upgrade Prompt reaches a guest inside the expanded question card. See `docs/adr/0010`.
@MainActor
final class TopmostSheetPresenter {
    private let presenter: any TopmostPresenting
    private var presentedController: UIViewController?

    init(presenter: any TopmostPresenting) {
        self.presenter = presenter
    }

    /// Presents when `isPresented` rises and dismisses when it falls. `onDismissedBySystem` lets
    /// the owner lower its flag when the sheet goes away without it — otherwise the flag stays
    /// raised and the sheet never shows again.
    func update(
        isPresented: Bool,
        makeController: () -> UIViewController,
        onDismissedBySystem: @escaping @MainActor () -> Void
    ) {
        guard isPresented else {
            dismiss {}
            return
        }
        guard presentedController == nil else { return }

        let controller = makeController()
        presentedController = controller
        presenter.present(controller) { [weak self, weak controller] in
            // A dismissal this presenter asked for has already cleared `presentedController`.
            guard let self, let controller, presentedController === controller else { return }
            presentedController = nil
            onDismissedBySystem()
        }
    }

    /// Dismisses the sheet, then runs `followUp` once it is off screen — at once when no sheet is
    /// up. UIKit refuses to present from a controller mid-dismissal, so a second sheet that follows
    /// this one has to be raised from `followUp`.
    func dismiss(then followUp: @escaping @MainActor () -> Void) {
        guard let controller = presentedController else {
            followUp()
            return
        }

        presentedController = nil
        presenter.dismiss(controller, completion: followUp)
    }
}
