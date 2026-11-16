import CoreGraphics

/// The clamp and momentum math for panning a zoomed answer image.
///
/// The image is laid out aspect-fit inside the container (`fittedSize`), scaled around its
/// centre, then offset in screen points. The offset is clamped so the scaled image always
/// covers the area it covered at its fitted size: an axis where the scaled image is still
/// smaller than the container stays centred.
struct ImageViewerPanMath: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 5
    /// Zoom a double tap jumps to.
    static let doubleTapScale: CGFloat = 2.5
    /// A pinch released below this snaps back to exactly 1x.
    static let restScaleTolerance: CGFloat = 1.05
    /// The share of the release's predicted extra travel that the settle carries.
    static let momentumFactor: CGFloat = 0.35

    /// The area the image may fill (the viewer's size).
    var containerSize: CGSize
    /// The image's size at 1x, after aspect-fit.
    var fittedSize: CGSize
    /// How far the image's resting centre sits from the container's centre. The image is fitted to
    /// the safe area, the container is the full screen: with a notch and no home bar the two
    /// centres differ.
    var restCenterShift: CGSize = .zero

    /// What one finger's drag does, decided when it begins and kept until it ends.
    enum DragMode: Equatable {
        /// No drag running.
        case idle
        /// A drag at 1x: it may close the viewer.
        case dismiss
        /// A drag that began zoomed: it pans and never closes.
        case pan
        /// A drag that saw a pinch, or began during one: it does nothing.
        case ignored
    }

    /// The mode a drag starts in.
    static func dragMode(isZoomed: Bool, isPinching: Bool) -> DragMode {
        if isZoomed { return .pan }
        return isPinching ? .ignored : .dismiss
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

    /// The offset after a pinch changes the zoom from `oldScale` to `newScale`: the image point
    /// that sat at the centre stays there, then the result is clamped.
    func rescaledOffset(_ offset: CGSize, from oldScale: CGFloat, to newScale: CGFloat) -> CGSize {
        guard oldScale > 0 else { return .zero }
        let ratio = newScale / oldScale
        return clamp(CGSize(width: offset.width * ratio, height: offset.height * ratio), at: newScale)
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

    /// Whether a touch at `point` (in the container's space) lands on the visible image.
    func imageContains(_ point: CGPoint, at scale: CGFloat, offset: CGSize) -> Bool {
        visibleImageRect(at: scale, offset: offset).contains(point)
    }

    /// The release speed as a share of the glide's distance per second, the unit
    /// `Animation.interpolatingSpring(initialVelocity:)` takes: the velocity's component along the
    /// glide divided by its length. Zero when the glide is too short to matter or runs against
    /// the finger.
    static func initialVelocity(from current: CGSize, to target: CGSize, releaseVelocity: CGSize) -> Double {
        let dx = target.width - current.width
        let dy = target.height - current.height
        let distanceSquared = dx * dx + dy * dy
        guard distanceSquared > 1 else { return 0 }
        let along = (releaseVelocity.width * dx + releaseVelocity.height * dy) / distanceSquared
        return Double(min(max(along, 0), maximumInitialVelocity))
    }

    /// A cap so a very short glide does not start with an absurd speed.
    static let maximumInitialVelocity: CGFloat = 20

    /// Where a drag released at `offset + translation` settles. `predictedEndTranslation` folds in
    /// the release velocity; a share of its extra travel carries on, and the result is clamped.
    /// Without momentum (Reduce Motion) the drag only settles inside the clamp.
    func settledOffset(
        offset: CGSize,
        translation: CGSize,
        predictedEndTranslation: CGSize,
        at scale: CGFloat,
        withMomentum: Bool
    ) -> CGSize {
        var target = CGSize(
            width: offset.width + translation.width,
            height: offset.height + translation.height
        )
        if withMomentum {
            target.width += (predictedEndTranslation.width - translation.width) * Self.momentumFactor
            target.height += (predictedEndTranslation.height - translation.height) * Self.momentumFactor
        }
        return clamp(target, at: scale)
    }
}
