import UIKit

/// A hidden child that tells the presenter when its parent has left the screen for good — by a
/// swipe, by SwiftUI's `dismiss`, or because the cover underneath closed and took it along.
///
/// A child rather than a `UIHostingController` subclass keeps `TopmostPresenting` free of any
/// particular controller type, and SwiftUI's `dismiss` keeps working because the hosting
/// controller itself is what gets presented.
final class DisappearanceSentinel: UIViewController {
    private let onDisappear: @MainActor () -> Void
    private var hasReported = false

    private init(onDisappear: @escaping @MainActor () -> Void) {
        self.onDisappear = onDisappear
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func attach(to parent: UIViewController, onDisappear: @escaping @MainActor () -> Void) {
        let sentinel = DisappearanceSentinel(onDisappear: onDisappear)
        parent.addChild(sentinel)
        parent.view.addSubview(sentinel.view)
        sentinel.didMove(toParent: parent)
    }

    override func loadView() {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // This also fires when a full-screen controller covers the sheet, which is not a
        // disappearance. Decide now, while UIKit still marks what is being dismissed, rather than
        // guessing when it clears the presentation links afterwards.
        guard !hasReported, let parent, Self.hasLeftForGood(parent) else { return }
        hasReported = true
        onDisappear()
    }

    /// Gone means dismissed itself (a swipe, SwiftUI's `dismiss`), or carried off by a controller
    /// below it being dismissed — the cover underneath closing — or no longer presented at all.
    private static func hasLeftForGood(_ controller: UIViewController) -> Bool {
        if controller.isBeingDismissed { return true }

        var presenting = controller.presentingViewController
        guard presenting != nil else { return true }

        while let current = presenting {
            if current.isBeingDismissed { return true }
            presenting = current.presentingViewController
        }
        return false
    }
}
