import UIKit

/// Whatever controller is on top of the window right now — the app root, or the deepest
/// `fullScreenCover` above it. `TopmostSheetPresenter` talks to this rather than to UIKit so its
/// rules can be tested with a fake window. See `docs/adr/0010`.
@MainActor
protocol TopmostPresenting: AnyObject {
    /// Presents `controller` over the topmost controller. `onDisappear` runs once, whenever the
    /// controller leaves the screen — for any reason, including a `dismiss` asked for below.
    func present(_ controller: UIViewController, onDisappear: @escaping @MainActor () -> Void)

    /// Dismisses `controller`, then runs `completion` once it is off screen.
    func dismiss(_ controller: UIViewController, completion: @escaping @MainActor () -> Void)
}
