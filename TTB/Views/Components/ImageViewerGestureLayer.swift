import SwiftUI
import UIKit

/// A transparent layer over the whole answer image viewer that reads its touches: pinch, pan, tap and
/// double tap.
///
/// SwiftUI's `MagnifyGesture` reports where the fingers started but not where they are now, and a
/// `DragGesture` does not follow the midpoint of two fingers. UIKit's recognizers give the midpoint of
/// the touches at every step, which is what zooming around the fingers and panning during a pinch need.
/// Points are in the layer's own space; the layer fills the viewer, so they are container points.
///
/// A pinch does not end when one finger lifts, only when both do. So the layer counts the touches itself
/// and, whenever the count changes during a gesture, sends `.rebase`: the viewer takes new start values
/// and the pinch scale restarts at 1.
struct ImageViewerGestureLayer: UIViewRepresentable {
    let onEvent: (ImageViewerInteraction.Event) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> TouchReportingView {
        let view = TouchReportingView()
        view.backgroundColor = .clear
        view.onTouchesChanged = { [weak coordinator = context.coordinator] event in
            coordinator?.touchesChanged(event)
        }
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ uiView: TouchReportingView, context: Context) {
        context.coordinator.onEvent = onEvent
    }

    /// Keeps the set of touches on the view and reports each change, before any recognizer decides.
    final class TouchReportingView: UIView {
        enum Change {
            case began
            case countChanged(count: Int, centroid: CGPoint)
        }

        var onTouchesChanged: ((Change) -> Void)?
        private var activeTouches = Set<UITouch>()

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouches.formUnion(touches)
            onTouchesChanged?(.began)
            reportCount()
            super.touchesBegan(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouches.subtract(touches)
            reportCount()
            super.touchesEnded(touches, with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            activeTouches.subtract(touches)
            reportCount()
            super.touchesCancelled(touches, with: event)
        }

        private func reportCount() {
            guard !activeTouches.isEmpty else {
                onTouchesChanged?(.countChanged(count: 0, centroid: .zero))
                return
            }
            let points = activeTouches.map { $0.location(in: self) }
            let centroid = CGPoint(
                x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
            )
            onTouchesChanged?(.countChanged(count: points.count, centroid: centroid))
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onEvent: (ImageViewerInteraction.Event) -> Void
        private let pan = UIPanGestureRecognizer()
        private let pinch = UIPinchGestureRecognizer()
        private var lastTouchCount = 0

        init(onEvent: @escaping (ImageViewerInteraction.Event) -> Void) {
            self.onEvent = onEvent
        }

        func install(on view: UIView) {
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 2
            pan.addTarget(self, action: #selector(handlePan(_:)))
            pinch.addTarget(self, action: #selector(handlePinch(_:)))

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            singleTap.require(toFail: doubleTap)

            for recognizer in [pan, pinch, doubleTap, singleTap] as [UIGestureRecognizer] {
                recognizer.delegate = self
                // The view keeps getting every touch, so its touch count stays right.
                recognizer.cancelsTouchesInView = false
                view.addGestureRecognizer(recognizer)
            }
        }

        func touchesChanged(_ change: TouchReportingView.Change) {
            switch change {
            case .began:
                onEvent(.touchDown)
            case let .countChanged(count, centroid):
                defer { lastTouchCount = count }
                guard count != lastTouchCount, count > 0 else { return }
                // The pinch scale restarts, so the new start values and the scale agree.
                pinch.scale = 1
                onEvent(.rebase(location: centroid, touchCount: count))
            }
        }

        /// Pinch and pan run together; the taps stay apart from them.
        func gestureRecognizer(
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
                onEvent(.panBegan(
                    location: location,
                    translation: translationSize,
                    touchCount: recognizer.numberOfTouches
                ))
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
                onEvent(.pinchEnded)
            default:
                break
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onEvent(.tap(location: recognizer.location(in: recognizer.view)))
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onEvent(.doubleTap(location: recognizer.location(in: recognizer.view)))
        }
    }
}
