import UIKit

/// The live `TopmostPresenting`: presents over the deepest controller the key window shows, so a
/// sheet the app root owns still appears while a `fullScreenCover` is up. See `docs/adr/0010`.
///
/// This is the one place the Upgrade Prompt touches UIKit. The toast host does the same job with
/// its own window (`ToastOverlayInstaller`); a modal sheet needs no window of its own, only the
/// controller that is already on top.
@MainActor
final class WindowTopmostPresenter: TopmostPresenting {
    func present(_ controller: UIViewController, onDisappear: @escaping @MainActor () -> Void) {
        guard let topmost = Self.topmostController() else {
            // Nothing can present it, so report it gone and let the owner lower its flag.
            onDisappear()
            return
        }

        DisappearanceSentinel.attach(to: controller, onDisappear: onDisappear)
        topmost.present(controller, animated: true)

        // UIKit sets the link as soon as it accepts a presentation, and refuses some without an
        // error — mid-transition, say. A refused sheet never disappears, so report it gone now or
        // the owner would wait on it forever.
        if controller.presentingViewController == nil {
            onDisappear()
        }
    }

    func dismiss(_ controller: UIViewController, completion: @escaping @MainActor () -> Void) {
        Self.dismissOnceSettled(controller, completion: completion)
    }

    /// UIKit refuses a dismissal mid-transition — a tap that lands while the sheet is still
    /// presenting, or while a swipe is in progress — without an error and never runs the
    /// completion. So wait for the transition to end, then look again on the next turn.
    private static func dismissOnceSettled(
        _ controller: UIViewController,
        uncoordinatedRetries: Int = 5,
        completion: @escaping @MainActor () -> Void
    ) {
        let coordinator = controller.transitionCoordinator
        // A transition with no coordinator has not started yet, so give it a few turns. One that
        // never gets a coordinator is stuck; dismiss anyway rather than spin the main actor.
        if controller.isBeingPresented || controller.isBeingDismissed,
           coordinator != nil || uncoordinatedRetries > 0 {
            // The hop matters: UIKit runs the coordinator's completion while it still marks the
            // transition.
            let retriesLeft = coordinator == nil ? uncoordinatedRetries - 1 : uncoordinatedRetries
            let lookAgain: () -> Void = {
                Task { @MainActor in
                    dismissOnceSettled(controller, uncoordinatedRetries: retriesLeft, completion: completion)
                }
            }
            if let coordinator {
                coordinator.animate(alongsideTransition: nil) { _ in lookAgain() }
            } else {
                lookAgain()
            }
            return
        }

        guard let presenting = controller.presentingViewController else {
            // Already gone: a swipe finished it, or the cover underneath closed.
            completion()
            return
        }

        // Asking the controller underneath removes `controller` and anything it presents on top
        // of itself — an alert, say. `controller.dismiss` would remove only that child.
        presenting.dismiss(animated: true, completion: completion)
    }

    /// Walks the key window's presentation chain, skipping a controller already on its way out.
    private static func topmostController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        guard var topmost = scene?.keyWindow?.rootViewController else { return nil }

        while let presented = topmost.presentedViewController, !presented.isBeingDismissed {
            topmost = presented
        }
        return topmost
    }
}
