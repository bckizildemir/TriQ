import CoreGraphics
import Foundation

/// The zoom, pan and glide math of the answer image viewer.
///
/// The image is laid out aspect-fit inside the container (`fittedSize`), scaled around its
/// centre, then offset in screen points. The offset is clamped so the scaled image always
/// covers the area it covered at its fitted size: an axis where the scaled image is still
/// smaller than the container stays centred.
///
/// Points handed to `transform` are in the container's own space (origin at its top-left).
struct ImageViewerPanMath: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 5
    /// Zoom a double tap jumps to.
    static let doubleTapScale: CGFloat = 2.5
    /// A pinch released below this snaps back to exactly 1x.
    static let restScaleTolerance: CGFloat = 1.05
    /// A glide slower than this (points per second) is over.
    static let glideStopSpeed: CGFloat = 30
    /// The share of a glide's speed left after one second: `UIScrollView`'s normal deceleration
    /// (0.998 per millisecond).
    static let glideSpeedLeftAfterOneSecond: Double = 0.135
    /// How far ahead (seconds) a release's velocity is projected to judge a flick, the stand-in
    /// for `DragGesture`'s `predictedEndTranslation`, which UIKit does not give.
    static let projectionDuration: CGFloat = 0.25

    /// The area the image may fill (the viewer's size).
    var containerSize: CGSize
    /// The image's size at 1x, after aspect-fit.
    var fittedSize: CGSize
    /// How far the image's resting centre sits from the container's centre. The image is fitted to
    /// the safe area, the container is the full screen: with a notch and no home bar the two
    /// centres differ.
    var restCenterShift: CGSize = .zero

    /// A zoom and the offset that goes with it.
    struct Transform: Equatable {
        var scale: CGFloat
        var offset: CGSize
    }

    /// One step of a glide.
    struct GlideStep: Equatable {
        var offset: CGSize
        var velocity: CGSize
        var isFinished: Bool
    }

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    /// The zoom a VoiceOver zoom step moves to: 1x, then the double-tap zoom, then the maximum.
    static func steppedScale(from scale: CGFloat, zoomingIn: Bool) -> CGFloat {
        let steps = [minimumScale, doubleTapScale, maximumScale]
        let epsilon: CGFloat = 0.01
        if zoomingIn {
            return steps.first { $0 > scale + epsilon } ?? maximumScale
        }
        return steps.last { $0 < scale - epsilon } ?? minimumScale
    }

    /// Where a drag that is `translation` long and leaves at `velocity` is headed: the release's
    /// velocity projected a short time ahead.
    static func projectedEnd(translation: CGFloat, velocity: CGFloat) -> CGFloat {
        translation + velocity * projectionDuration
    }

    private static func clampAxis(_ value: CGFloat, overhang: CGFloat, shift: CGFloat) -> CGFloat {
        guard overhang > 0 else { return 0 }
        return min(max(value, -overhang - shift), overhang - shift)
    }

    /// The farthest the image may move from centre on each axis at `scale`.
    func maxOffset(at scale: CGFloat) -> CGSize {
        guard scale > Self.minimumScale else { return .zero }
        return CGSize(
            width: max(0, (fittedSize.width * scale - containerSize.width) / 2),
            height: max(0, (fittedSize.height * scale - containerSize.height) / 2)
        )
    }

    /// `offset` limited so the scaled image keeps covering the container's edges. An axis with no
    /// overhang, and any offset at 1x, stays at rest (zero).
    func clamp(_ offset: CGSize, at scale: CGFloat) -> CGSize {
        let overhang = maxOffset(at: scale)
        return CGSize(
            width: Self.clampAxis(offset.width, overhang: overhang.width, shift: restCenterShift.width),
            height: Self.clampAxis(offset.height, overhang: overhang.height, shift: restCenterShift.height)
        )
    }

    /// The screen rectangle the image covers at `scale` and `offset`: the fitted image scaled around
    /// its resting centre, then moved by the offset.
    func visibleImageRect(at scale: CGFloat, offset: CGSize) -> CGRect {
        let size = CGSize(width: fittedSize.width * scale, height: fittedSize.height * scale)
        return CGRect(
            x: containerSize.width / 2 + restCenterShift.width + offset.width - size.width / 2,
            y: containerSize.height / 2 + restCenterShift.height + offset.height - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The zoom and offset for one moment of a pinch and pan that run together.
    ///
    /// The gesture began at `startScale` and `startOffset` with the fingers' midpoint at `anchor`.
    /// Now the fingers have spread by `pinchFactor` (1 for a pan alone) and their midpoint is at
    /// `location`. The image point that sat under `anchor` is kept under `location`: with a factor of
    /// 1 that is a 1:1 pan, and with a changing factor it is a zoom around the fingers. The result is
    /// clamped to the supported zoom range and to the image's edges.
    func transform(
        startScale: CGFloat,
        startOffset: CGSize,
        anchor: CGPoint,
        pinchFactor: CGFloat,
        location: CGPoint
    ) -> Transform {
        let scale = Self.clampedScale(startScale * pinchFactor)
        guard startScale > 0 else { return Transform(scale: scale, offset: .zero) }
        let centre = CGPoint(
            x: containerSize.width / 2 + restCenterShift.width,
            y: containerSize.height / 2 + restCenterShift.height
        )
        // The point under the anchor, in the image's own unscaled coordinates from its centre.
        let pointX = (anchor.x - centre.x - startOffset.width) / startScale
        let pointY = (anchor.y - centre.y - startOffset.height) / startScale
        let offset = CGSize(
            width: location.x - centre.x - pointX * scale,
            height: location.y - centre.y - pointY * scale
        )
        return Transform(scale: scale, offset: clamp(offset, at: scale))
    }

    /// One frame of the glide after a release: the speed decays, the image moves, and an axis that
    /// reaches the image's edge stops there. Finished when it is too slow to see.
    func glideStep(offset: CGSize, velocity: CGSize, deltaTime: Double, at scale: CGFloat) -> GlideStep {
        let decay = CGFloat(pow(Self.glideSpeedLeftAfterOneSecond, deltaTime))
        var newVelocity = CGSize(width: velocity.width * decay, height: velocity.height * decay)
        let travelled = CGSize(
            width: offset.width + newVelocity.width * CGFloat(deltaTime),
            height: offset.height + newVelocity.height * CGFloat(deltaTime)
        )
        let clamped = clamp(travelled, at: scale)
        if clamped.width != travelled.width { newVelocity.width = 0 }
        if clamped.height != travelled.height { newVelocity.height = 0 }
        let speed = hypot(newVelocity.width, newVelocity.height)
        return GlideStep(offset: clamped, velocity: newVelocity, isFinished: speed < Self.glideStopSpeed)
    }
}
