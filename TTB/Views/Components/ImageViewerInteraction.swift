import CoreGraphics

/// The state machine of the answer image viewer's touches: events in, new state and effects out.
///
/// It owns the zoom, the pan offset and the downward drag, so every rule is testable without a view:
/// - One finger at 1x pulls the image down (`dismissDrag`) and may close the viewer; sideways and upward
///   movement does nothing. A two-finger start never closes it.
/// - Pinch and pan are one transform. The start values are re-taken (`rebase`) every time the finger
///   count changes, so a finger landing or lifting never makes the image jump.
/// - A release glides only when it was one finger panning: a pinch released never throws the image.
/// - Anything that changes the zoom or offset from outside (a touch, a tap, VoiceOver, the close
///   button, a new geometry) first stops a running glide, where it is.
struct ImageViewerInteraction: Equatable {
    enum Event: Equatable {
        /// A finger touched down.
        case touchDown
        /// The pan was recognized. `translation` is how far the finger moved before that.
        case panBegan(location: CGPoint, translation: CGSize, touchCount: Int)
        case panChanged(location: CGPoint, translation: CGSize)
        case panEnded(velocity: CGSize, isCancelled: Bool)
        case pinchBegan(location: CGPoint)
        /// `scale` is the spread of the fingers since the pinch began or the last rebase.
        case pinchChanged(scale: CGFloat, location: CGPoint)
        case pinchEnded
        /// The finger count changed to `touchCount` (1 or more) with the fingers' midpoint at `location`.
        case rebase(location: CGPoint, touchCount: Int)
        case tap(location: CGPoint)
        case doubleTap(location: CGPoint)
        /// VoiceOver's activate: zoom toggle around the image centre.
        case toggleZoom
        case zoomStep(zoomingIn: Bool)
        /// The close button, or VoiceOver's escape.
        case closeRequested
        /// The viewer's size or the image's size changed.
        case geometryChanged
        /// The glide moved the image.
        case glideFrame(offset: CGSize)
        case glideFinished
    }

    enum Effect: Equatable {
        /// The state changed in a way that should animate: assign the new state inside `withAnimation`.
        case animate
        case stopGlide
        case startGlide(velocity: CGSize)
        /// Close the viewer, keeping the pulled-down image where it is.
        case dismiss
        /// Close the viewer from rest: the state is already back at 1x, assign it without animation.
        case close
    }

    private enum Mode: Equatable {
        case idle
        /// One finger at 1x pulling the image down.
        case dismiss
        /// Panning and zooming.
        case transform
    }

    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero
    /// How far a downward drag at 1x has pulled the image.
    private(set) var dismissDrag: CGFloat = 0
    private(set) var isGliding = false

    private var mode = Mode.idle
    private var isPanning = false
    private var isPinching = false
    private var fingers = 0
    private var startScale: CGFloat = 1
    private var startOffset = CGSize.zero
    private var anchor = CGPoint.zero
    private var pinchFactor: CGFloat = 1

    var isZoomed: Bool { scale > ImageViewerPanMath.minimumScale }

    mutating func handle(_ event: Event, math: ImageViewerPanMath, reduceMotion: Bool = false) -> [Effect] {
        switch event {
        case .touchDown:
            return stopGlide()
        case let .panBegan(location, translation, touchCount):
            return beginPan(location: location, translation: translation, touchCount: touchCount, math: math)
        case let .panChanged(location, translation):
            return changePan(location: location, translation: translation, math: math)
        case let .panEnded(velocity, isCancelled):
            return endPan(velocity: velocity, isCancelled: isCancelled, reduceMotion: reduceMotion)
        case let .pinchBegan(location):
            return beginPinch(at: location)
        case let .pinchChanged(factor, location):
            guard mode == .transform, isPinching else { return [] }
            pinchFactor = factor
            apply(at: location, math: math)
            return []
        case .pinchEnded:
            guard isPinching else { return [] }
            isPinching = false
            pinchFactor = 1
            return finishIfIdle()
        case let .rebase(location, touchCount):
            return rebase(at: location, touchCount: touchCount)
        case let .tap(location):
            return tap(at: location, math: math)
        case let .doubleTap(location):
            return toggleZoom(around: location, math: math)
        case .toggleZoom:
            return toggleZoom(around: math.restCenter, math: math)
        case let .zoomStep(zoomingIn):
            var effects = stopGlide()
            scale = ImageViewerPanMath.steppedScale(from: scale, zoomingIn: zoomingIn)
            offset = math.clamp(offset, at: scale)
            effects.append(.animate)
            return effects
        case .closeRequested:
            var effects = stopGlide()
            resetToRest()
            effects.append(.close)
            return effects
        case .geometryChanged:
            let effects = stopGlide()
            mode = .idle
            isPanning = false
            isPinching = false
            fingers = 0
            offset = math.clamp(offset, at: scale)
            return effects
        case let .glideFrame(newOffset):
            guard isGliding else { return [] }
            offset = newOffset
            return []
        case .glideFinished:
            isGliding = false
            return []
        }
    }

    // MARK: Glide

    private mutating func stopGlide() -> [Effect] {
        guard isGliding else { return [] }
        isGliding = false
        return [.stopGlide]
    }

    // MARK: Pan

    private mutating func beginPan(
        location: CGPoint,
        translation: CGSize,
        touchCount: Int,
        math: ImageViewerPanMath
    ) -> [Effect] {
        isPanning = true
        // Already tracking (a pinch began first, or a rebase re-took the start): keep following it.
        guard mode == .idle else { return [] }
        fingers = touchCount
        if touchCount == 1, !isZoomed {
            mode = .dismiss
        } else {
            // One finger: start from where it touched down, so the image follows the whole movement.
            // Two fingers: their midpoint has moved on already, start from where it is.
            let start = touchCount == 1
                ? CGPoint(x: location.x - translation.width, y: location.y - translation.height)
                : location
            startTransform(anchor: start)
        }
        return changePan(location: location, translation: translation, math: math)
    }

    private mutating func changePan(location: CGPoint, translation: CGSize, math: ImageViewerPanMath) -> [Effect] {
        switch mode {
        case .idle:
            break
        case .dismiss:
            // Only down: a sideways or upward drag does nothing.
            dismissDrag = max(0, translation.height)
        case .transform:
            apply(at: location, math: math)
        }
        return []
    }

    private mutating func endPan(velocity: CGSize, isCancelled: Bool, reduceMotion: Bool) -> [Effect] {
        guard isPanning else { return [] }
        isPanning = false
        switch mode {
        case .idle:
            return []
        case .dismiss:
            mode = .idle
            fingers = 0
            let shouldClose = !isCancelled && AnswerImageViewerDismissal.shouldDismiss(
                translation: dismissDrag,
                predictedEndTranslation: ImageViewerPanMath.projectedEnd(
                    translation: dismissDrag,
                    velocity: velocity.height
                )
            )
            if shouldClose { return [.dismiss] }
            dismissDrag = 0
            return [.animate]
        case .transform:
            // A pinch still runs: its end finishes the interaction.
            guard !isPinching else { return [] }
            let fingersAtRelease = fingers
            var effects = finishIfIdle()
            if effects.isEmpty, !isCancelled, !reduceMotion, fingersAtRelease == 1, isZoomed {
                isGliding = true
                effects.append(.startGlide(velocity: velocity))
            }
            return effects
        }
    }

    // MARK: Pinch

    private mutating func beginPinch(at location: CGPoint) -> [Effect] {
        var effects = stopGlide()
        isPinching = true
        fingers = 2
        switch mode {
        case .idle:
            startTransform(anchor: location)
        case .dismiss:
            // A drag that was pulling the image down gives way to the pinch.
            startTransform(anchor: location)
            if dismissDrag != 0 {
                dismissDrag = 0
                effects.append(.animate)
            }
        case .transform:
            break
        }
        return effects
    }

    /// The pan and pinch are both over: back to rest, and a zoom below the tolerance snaps to 1x.
    private mutating func finishIfIdle() -> [Effect] {
        guard !isPanning, !isPinching else { return [] }
        mode = .idle
        fingers = 0
        guard scale < ImageViewerPanMath.restScaleTolerance, scale != 1 || offset != .zero else { return [] }
        scale = 1
        offset = .zero
        return [.animate]
    }

    // MARK: Rebase

    private mutating func rebase(at location: CGPoint, touchCount: Int) -> [Effect] {
        guard touchCount > 0, mode != .idle else { return [] }
        fingers = touchCount
        var effects: [Effect] = []
        if mode == .dismiss {
            // A second finger turns the drag into a pinch and pan: the image goes back up.
            if dismissDrag != 0 {
                dismissDrag = 0
                effects.append(.animate)
            }
        }
        startTransform(anchor: location)
        return effects
    }

    private mutating func startTransform(anchor: CGPoint) {
        mode = .transform
        startScale = scale
        startOffset = offset
        self.anchor = anchor
        pinchFactor = 1
    }

    private mutating func apply(at location: CGPoint, math: ImageViewerPanMath) {
        let result = math.transform(
            startScale: startScale,
            startOffset: startOffset,
            anchor: anchor,
            pinchFactor: pinchFactor,
            location: location
        )
        scale = result.scale
        offset = result.offset
    }

    // MARK: Taps and programmatic changes

    private mutating func tap(at location: CGPoint, math: ImageViewerPanMath) -> [Effect] {
        // A tap outside the image closes the viewer. Zoomed, it does nothing: it would throw the
        // zoom away.
        guard !isZoomed, !math.visibleImageRect(at: 1, offset: .zero).contains(location) else { return [] }
        var effects = stopGlide()
        resetToRest()
        effects.append(.close)
        return effects
    }

    private mutating func toggleZoom(around point: CGPoint, math: ImageViewerPanMath) -> [Effect] {
        var effects = stopGlide()
        if isZoomed {
            scale = 1
            offset = .zero
        } else {
            let zoomed = math.transform(
                startScale: scale,
                startOffset: offset,
                anchor: point,
                pinchFactor: ImageViewerPanMath.doubleTapScale,
                location: point
            )
            scale = zoomed.scale
            offset = zoomed.offset
        }
        effects.append(.animate)
        return effects
    }

    private mutating func resetToRest() {
        scale = 1
        offset = .zero
        mode = .idle
        isPanning = false
        isPinching = false
        fingers = 0
    }
}
