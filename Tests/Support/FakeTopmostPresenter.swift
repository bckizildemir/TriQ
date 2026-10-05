import UIKit
@testable import TTB

/// Stands in for the window's topmost controller. Like UIKit, it reports a controller's
/// disappearance for every dismissal — a system one and the one `dismiss` asked for — so the
/// presenter under test has to tell the two apart itself.
@MainActor
final class FakeTopmostPresenter: TopmostPresenting {
    private(set) var presentedControllers: [UIViewController] = []
    private(set) var dismissedControllers: [UIViewController] = []
    private var disappearanceHandlers: [ObjectIdentifier: @MainActor () -> Void] = [:]
    private var pendingDismissals: [(UIViewController, @MainActor () -> Void)] = []

    /// Refuses every presentation the way UIKit does mid-transition: the controller never shows,
    /// and its disappearance is reported before `present` returns.
    var refusesPresentation = false

    func present(
        _ controller: UIViewController,
        onDisappear: @escaping @MainActor () -> Void
    ) {
        guard refusesPresentation == false else {
            onDisappear()
            return
        }

        presentedControllers.append(controller)
        disappearanceHandlers[ObjectIdentifier(controller)] = onDisappear
    }

    func dismiss(_ controller: UIViewController, completion: @escaping @MainActor () -> Void) {
        dismissedControllers.append(controller)
        pendingDismissals.append((controller, completion))
    }

    /// Ends every dismissal `dismiss` started, the way UIKit does once the animation finishes.
    func finishDismissals() {
        let dismissals = pendingDismissals
        pendingDismissals = []
        for (controller, completion) in dismissals {
            disappear(controller)
            completion()
        }
    }

    /// A dismissal nobody asked the presenter for: a swipe down, or the cover underneath closing.
    func dismissBySystem(_ controller: UIViewController) {
        disappear(controller)
    }

    private func disappear(_ controller: UIViewController) {
        disappearanceHandlers.removeValue(forKey: ObjectIdentifier(controller))?()
    }
}
