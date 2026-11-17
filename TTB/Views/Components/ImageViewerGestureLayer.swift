import SwiftUI
import UIKit

/// A transparent layer over the whole answer image viewer that reads its touches: pinch, pan, tap and
/// double tap.
///
/// SwiftUI's `MagnifyGesture` reports where the fingers started but not where they are now, and a
/// `DragGesture` does not follow the midpoint of two fingers. UIKit's recognizers give the midpoint of
/// the touches at every step, which is what zooming around the fingers and panning during a pinch need.
/// Points are in the layer's own space; the layer fills the viewer, so they are container points.
struct ImageViewerGestureLayer: UIViewRepresentable {
    enum Event {
        /// A finger touched down. The glide stops here, before any gesture is recognized.
        case touchDown
        /// `translation` is how far the finger already moved when the pan was recognized.
        case panBegan(location: CGPoint, translation: CGSize)
        case panChanged(location: CGPoint, translation: CGSize)
        case panEnded(velocity: CGSize, isCancelled: Bool)
        case pinchBegan(location: CGPoint)
        /// `scale` is the spread of the fingers since the pinch began.
        case pinchChanged(scale: CGFloat, location: CGPoint)
        /// `remainingFinger` is where the one finger still down is, when a pan is running on it.
        case pinchEnded(remainingFinger: CGPoint?)
        case tap(location: CGPoint)
        case doubleTap
    }

    let onEvent: (Event) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> TouchReportingView {
        let view = TouchReportingView()
        view.backgroundColor = .clear
        view.onTouchDown = { [weak coordinator = context.coordinator] in
            coordinator?.onEvent(.touchDown)
        }
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ uiView: TouchReportingView, context: Context) {
        context.coordinator.onEvent = onEvent
    }

    /// Tells when a touch begins; recognizers only report once they have recognized something.
    final class TouchReportingView: UIView {
        var onTouchDown: (() -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouchDown?()
            super.touchesBegan(touches, with: event)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onEvent: (Event) -> Void
        private let pan = UIPanGestureRecognizer()
        private let pinch = UIPinchGestureRecognizer()

        init(onEvent: @escaping (Event) -> Void) {
            self.onEvent = onEvent
        }

        func install(on view: UIView) {
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 2
            pan.addTarget(self, action: #selector(handlePan(_:)))
            pinch.addTarget(self, action: #selector(handlePinch(_:)))

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            singleTap.require(toFail: doubleTap)

            for recognizer in [pan, pinch, doubleTap, singleTap] as [UIGestureRecognizer] {
                recognizer.delegate = self
                view.addGestureRecognizer(recognizer)
            }
        }

        /// Pinch and pan run together; the taps stay apart from them.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            (gestureRecognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
                || (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let view = recognizer.view
            let location = recognizer.location(in: view)
            let translation = recognizer.translation(in: view)
            let translationSize = CGSize(width: translation.x, height: translation.y)
            switch recognizer.state {
            case .began:
                onEvent(.panBegan(location: location, translation: translationSize))
            case .changed:
                onEvent(.panChanged(location: location, translation: translationSize))
            case .ended, .cancelled, .failed:
                let velocity = recognizer.velocity(in: view)
                onEvent(.panEnded(
                    velocity: CGSize(width: velocity.x, height: velocity.y),
                    isCancelled: recognizer.state != .ended
                ))
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began:
                onEvent(.pinchBegan(location: location))
            case .changed:
                onEvent(.pinchChanged(scale: recognizer.scale, location: location))
            case .ended, .cancelled, .failed:
                let panIsRunning = pan.state == .began || pan.state == .changed
                let remaining = panIsRunning && pan.numberOfTouches == 1
                    ? pan.location(in: pan.view)
                    : nil
                onEvent(.pinchEnded(remainingFinger: remaining))
            default:
                break
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onEvent(.tap(location: recognizer.location(in: recognizer.view)))
        }

        @objc private func handleDoubleTap() {
            onEvent(.doubleTap)
        }
    }
}
