import QuartzCore
import UIKit

/// Runs the glide of a released pan, frame by frame, so a touch can stop it exactly where it is.
///
/// A SwiftUI animation only knows its end value: a touch during it would read the end, and the image
/// would jump there. Here the view's own offset is updated each frame, so the offset is always where
/// the image is on screen.
@MainActor
final class ImageViewerGlide: NSObject {
    private var link: CADisplayLink?
    private var math = ImageViewerPanMath(containerSize: .zero, fittedSize: .zero)
    private var scale: CGFloat = 1
    private var offset = CGSize.zero
    private var velocity = CGSize.zero
    private var lastTimestamp: CFTimeInterval = 0
    private var onFrame: ((CGSize) -> Void)?
    private var onFinish: (() -> Void)?

    /// Starts gliding from `offset` at `velocity` (points per second). `onFrame` gets each new offset;
    /// `onFinish` runs when the glide ends on its own (a `stop()` does not call it).
    func start(
        from offset: CGSize,
        velocity: CGSize,
        scale: CGFloat,
        math: ImageViewerPanMath,
        onFrame: @escaping (CGSize) -> Void,
        onFinish: @escaping () -> Void
    ) {
        stop()
        self.offset = offset
        self.velocity = velocity
        self.scale = scale
        self.math = math
        self.onFrame = onFrame
        self.onFinish = onFinish
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        lastTimestamp = CACurrentMediaTime()
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Stops the glide; the last offset it reported stays.
    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
        onFinish = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        // A dropped frame must not make the image leap: cap the step.
        let deltaTime = min(link.timestamp - lastTimestamp, 1.0 / 30)
        lastTimestamp = link.timestamp
        guard deltaTime > 0 else { return }
        let step = math.glideStep(offset: offset, velocity: velocity, deltaTime: deltaTime, at: scale)
        offset = step.offset
        velocity = step.velocity
        onFrame?(step.offset)
        if step.isFinished {
            let finish = onFinish
            stop()
            finish?()
        }
    }
}
