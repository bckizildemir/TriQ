import CoreGraphics
import Testing
@testable import TTB

struct ImageViewerInteractionTests {
    /// A 400x800 screen with a square 400x400 image fitted to the width: it rests at y 200...600.
    private let math = ImageViewerPanMath(
        containerSize: CGSize(width: 400, height: 800),
        fittedSize: CGSize(width: 400, height: 400)
    )

    private let centre = CGPoint(x: 200, y: 400)

    /// A viewer zoomed to 3x by a double tap on the centre.
    private func zoomed() -> ImageViewerInteraction {
        var viewer = ImageViewerInteraction()
        _ = viewer.handle(.doubleTap(location: centre), math: math)
        _ = viewer.handle(.zoomStep(zoomingIn: true), math: math)  // 2.5x -> 5x
        _ = viewer.handle(.zoomStep(zoomingIn: false), math: math)  // back to 2.5x
        return viewer
    }

    @discardableResult
    private func send(
        _ event: ImageViewerInteraction.Event,
        to viewer: inout ImageViewerInteraction,
        reduceMotion: Bool = false
    ) -> [ImageViewerInteraction.Effect] {
        viewer.handle(event, math: math, reduceMotion: reduceMotion)
    }

    // MARK: Dismiss at 1x

    @Test func downwardDragAtOneTimesPullsTheImageAndLongDragCloses() {
        var viewer = ImageViewerInteraction()
        send(.panBegan(location: CGPoint(x: 200, y: 410), translation: CGSize(width: 0, height: 10), touchCount: 1), to: &viewer)
        send(.panChanged(location: CGPoint(x: 200, y: 560), translation: CGSize(width: 0, height: 160)), to: &viewer)
        #expect(viewer.dismissDrag == 160)
        let effects = send(.panEnded(velocity: CGSize(width: 0, height: 100), isCancelled: false), to: &viewer)
        #expect(effects == [.dismiss])
        #expect(viewer.dismissDrag == 160)
    }

    @Test func sidewaysAndUpwardDragsAtOneTimesDoNothing() {
        var viewer = ImageViewerInteraction()
        send(.panBegan(location: CGPoint(x: 100, y: 400), translation: CGSize(width: -60, height: 0), touchCount: 1), to: &viewer)
        send(.panChanged(location: CGPoint(x: -100, y: 200), translation: CGSize(width: -260, height: -200)), to: &viewer)
        #expect(viewer.dismissDrag == 0)
        #expect(viewer.offset == .zero)
        let effects = send(.panEnded(velocity: CGSize(width: -2000, height: -2000), isCancelled: false), to: &viewer)
        #expect(!effects.contains(.dismiss))
        #expect(!effects.contains(where: { if case .startGlide = $0 { true } else { false } }))
    }

    @Test func shortSlowDownwardDragSnapsBack() {
        var viewer = ImageViewerInteraction()
        send(.panBegan(location: CGPoint(x: 200, y: 440), translation: CGSize(width: 0, height: 40), touchCount: 1), to: &viewer)
        let effects = send(.panEnded(velocity: .zero, isCancelled: false), to: &viewer)
        #expect(effects == [.animate])
        #expect(viewer.dismissDrag == 0)
    }

    @Test func cancelledPanInDismissModeDoesNotClose() {
        var viewer = ImageViewerInteraction()
        send(.panBegan(location: CGPoint(x: 200, y: 600), translation: CGSize(width: 0, height: 200), touchCount: 1), to: &viewer)
        let effects = send(.panEnded(velocity: CGSize(width: 0, height: 4000), isCancelled: true), to: &viewer)
        #expect(!effects.contains(.dismiss))
        #expect(viewer.dismissDrag == 0)
    }

    @Test func twoFingerStartAtOneTimesNeverPullsOrCloses() {
        var viewer = ImageViewerInteraction()
        send(.panBegan(location: CGPoint(x: 200, y: 500), translation: CGSize(width: 0, height: 60), touchCount: 2), to: &viewer)
        send(.panChanged(location: CGPoint(x: 200, y: 700), translation: CGSize(width: 0, height: 260)), to: &viewer)
        #expect(viewer.dismissDrag == 0)
        let effects = send(.panEnded(velocity: CGSize(width: 0, height: 3000), isCancelled: false), to: &viewer)
        #expect(!effects.contains(.dismiss))
    }

    @Test func secondFingerDuringADismissDragReturnsTheImage() {
        var viewer = ImageViewerInteraction()
        send(.panBegan(location: CGPoint(x: 200, y: 500), translation: CGSize(width: 0, height: 60), touchCount: 1), to: &viewer)
        #expect(viewer.dismissDrag == 60)
        let effects = send(.rebase(location: CGPoint(x: 200, y: 520), touchCount: 2), to: &viewer)
        #expect(effects == [.animate])
        #expect(viewer.dismissDrag == 0)
    }

    // MARK: Pan

    @Test func zoomedPanFollowsTheFingerOneToOne() {
        var viewer = zoomed()
        let before = viewer.offset
        send(.panBegan(location: CGPoint(x: 110, y: 400), translation: CGSize(width: 10, height: 0), touchCount: 1), to: &viewer)
        send(.panChanged(location: CGPoint(x: 150, y: 420), translation: CGSize(width: 50, height: 20)), to: &viewer)
        #expect(viewer.offset.width == before.width + 50)
    }

    @Test func secondFingerLandingMidPanDoesNotMoveTheImage() {
        var viewer = zoomed()
        send(.panBegan(location: CGPoint(x: 100, y: 400), translation: .zero, touchCount: 1), to: &viewer)
        send(.panChanged(location: CGPoint(x: 140, y: 400), translation: CGSize(width: 40, height: 0)), to: &viewer)
        let before = viewer.offset
        // The midpoint jumps to the middle of the two fingers.
        send(.rebase(location: CGPoint(x: 220, y: 400), touchCount: 2), to: &viewer)
        #expect(viewer.offset == before)
        send(.pinchBegan(location: CGPoint(x: 220, y: 400)), to: &viewer)
        send(.pinchChanged(scale: 1, location: CGPoint(x: 220, y: 400)), to: &viewer)
        #expect(viewer.offset == before)
        send(.panChanged(location: CGPoint(x: 230, y: 400), translation: CGSize(width: 130, height: 0)), to: &viewer)
        #expect(viewer.offset.width == before.width + 10)
    }

    // MARK: Pinch

    @Test func pinchZoomsAroundTheFingersAndFollowsThem() {
        var viewer = ImageViewerInteraction()
        let start = CGPoint(x: 300, y: 400)
        send(.pinchBegan(location: start), to: &viewer)
        send(.pinchChanged(scale: 2, location: start), to: &viewer)
        #expect(viewer.scale == 2)
        #expect(viewer.offset == CGSize(width: -100, height: 0))
        send(.pinchChanged(scale: 2, location: CGPoint(x: 280, y: 400)), to: &viewer)
        #expect(viewer.offset == CGSize(width: -120, height: 0))
    }

    @Test func oneFingerLiftingMidPinchDoesNotMoveTheImage() {
        var viewer = ImageViewerInteraction()
        let start = CGPoint(x: 300, y: 400)
        send(.pinchBegan(location: start), to: &viewer)
        send(.pinchChanged(scale: 2, location: start), to: &viewer)
        let before = viewer.offset
        // One finger lifts: the midpoint jumps to the finger that stays, and the pinch scale restarts.
        send(.rebase(location: CGPoint(x: 360, y: 400), touchCount: 1), to: &viewer)
        #expect(viewer.offset == before)
        send(.pinchChanged(scale: 1, location: CGPoint(x: 360, y: 400)), to: &viewer)
        #expect(viewer.offset == before)
        #expect(viewer.scale == 2)
        send(.panChanged(location: CGPoint(x: 350, y: 400), translation: CGSize(width: -10, height: 0)), to: &viewer)
        #expect(viewer.offset.width == before.width - 10)
    }

    @Test func pinchReleasedNearOneTimesSnapsToRest() {
        var viewer = ImageViewerInteraction()
        send(.pinchBegan(location: centre), to: &viewer)
        send(.pinchChanged(scale: 1.02, location: centre), to: &viewer)
        let effects = send(.pinchEnded, to: &viewer)
        #expect(effects == [.animate])
        #expect(viewer.scale == 1)
        #expect(viewer.offset == .zero)
    }

    @Test func pinchReleasedWithBothFingersNeverGlides() {
        for panEndsFirst in [true, false] {
            var viewer = ImageViewerInteraction()
            send(.pinchBegan(location: CGPoint(x: 300, y: 400)), to: &viewer)
            send(.panBegan(location: CGPoint(x: 300, y: 400), translation: .zero, touchCount: 2), to: &viewer)
            send(.pinchChanged(scale: 3, location: CGPoint(x: 280, y: 400)), to: &viewer)
            var effects: [ImageViewerInteraction.Effect] = []
            let panEnd = ImageViewerInteraction.Event.panEnded(velocity: CGSize(width: -1500, height: 0), isCancelled: false)
            if panEndsFirst {
                effects += send(panEnd, to: &viewer)
                effects += send(.pinchEnded, to: &viewer)
            } else {
                effects += send(.pinchEnded, to: &viewer)
                effects += send(panEnd, to: &viewer)
            }
            #expect(!viewer.isGliding)
            #expect(!effects.contains(where: { if case .startGlide = $0 { true } else { false } }))
            #expect(viewer.scale == 3)
        }
    }

    // MARK: Glide

    @Test func oneFingerPanReleaseGlides() {
        var viewer = zoomed()
        send(.panBegan(location: CGPoint(x: 200, y: 400), translation: .zero, touchCount: 1), to: &viewer)
        send(.panChanged(location: CGPoint(x: 240, y: 400), translation: CGSize(width: 40, height: 0)), to: &viewer)
        let velocity = CGSize(width: 900, height: 0)
        let effects = send(.panEnded(velocity: velocity, isCancelled: false), to: &viewer)
        #expect(effects == [.startGlide(velocity: velocity)])
        #expect(viewer.isGliding)
    }

    @Test func reduceMotionReleaseDoesNotGlide() {
        var viewer = zoomed()
        send(.panBegan(location: CGPoint(x: 200, y: 400), translation: .zero, touchCount: 1), to: &viewer)
        let effects = send(.panEnded(velocity: CGSize(width: 900, height: 0), isCancelled: false), to: &viewer, reduceMotion: true)
        #expect(effects.isEmpty)
    }

    @Test func touchDuringAGlideStopsItWhereItIs() {
        var viewer = zoomed()
        send(.panBegan(location: CGPoint(x: 200, y: 400), translation: .zero, touchCount: 1), to: &viewer)
        send(.panEnded(velocity: CGSize(width: 900, height: 0), isCancelled: false), to: &viewer)
        send(.glideFrame(offset: CGSize(width: 61, height: 0)), to: &viewer)
        let effects = send(.touchDown, to: &viewer)
        #expect(effects == [.stopGlide])
        #expect(viewer.offset == CGSize(width: 61, height: 0))
        // A frame that was already on its way is ignored.
        send(.glideFrame(offset: CGSize(width: 70, height: 0)), to: &viewer)
        #expect(viewer.offset == CGSize(width: 61, height: 0))
    }

    @Test func closeRequestDuringAGlideStopsItAndClosesFromRest() {
        var viewer = zoomed()
        send(.panBegan(location: CGPoint(x: 200, y: 400), translation: .zero, touchCount: 1), to: &viewer)
        send(.panEnded(velocity: CGSize(width: 900, height: 0), isCancelled: false), to: &viewer)
        let effects = send(.closeRequested, to: &viewer)
        #expect(effects == [.stopGlide, .close])
        #expect(viewer.scale == 1)
        #expect(viewer.offset == .zero)
        send(.glideFrame(offset: CGSize(width: 90, height: 0)), to: &viewer)
        #expect(viewer.offset == .zero)
    }

    @Test func zoomActionsAndGeometryChangesStopTheGlide() {
        for event in [
            ImageViewerInteraction.Event.toggleZoom,
            .doubleTap(location: CGPoint(x: 200, y: 400)),
            .zoomStep(zoomingIn: true),
            .geometryChanged
        ] {
            var viewer = zoomed()
            send(.panBegan(location: CGPoint(x: 200, y: 400), translation: .zero, touchCount: 1), to: &viewer)
            send(.panEnded(velocity: CGSize(width: 900, height: 0), isCancelled: false), to: &viewer)
            let effects = send(event, to: &viewer)
            #expect(effects.first == .stopGlide)
            #expect(!viewer.isGliding)
        }
    }

    @Test func newGeometryClampsTheOffset() {
        var viewer = zoomed()
        send(.panBegan(location: CGPoint(x: 200, y: 400), translation: .zero, touchCount: 1), to: &viewer)
        send(.panChanged(location: CGPoint(x: 600, y: 400), translation: CGSize(width: 400, height: 0)), to: &viewer)
        let narrower = ImageViewerPanMath(
            containerSize: CGSize(width: 400, height: 800),
            fittedSize: CGSize(width: 200, height: 200)
        )
        _ = viewer.handle(.geometryChanged, math: narrower)
        #expect(viewer.offset == narrower.clamp(viewer.offset, at: viewer.scale))
    }

    // MARK: Taps and double tap

    @Test func tapOutsideTheImageAtOneTimesCloses() {
        var viewer = ImageViewerInteraction()
        #expect(send(.tap(location: CGPoint(x: 200, y: 100)), to: &viewer) == [.close])
        #expect(send(.tap(location: CGPoint(x: 200, y: 400)), to: &viewer).isEmpty)
    }

    @Test func tapWhileZoomedDoesNothing() {
        var viewer = zoomed()
        #expect(send(.tap(location: CGPoint(x: 5, y: 5)), to: &viewer).isEmpty)
        #expect(viewer.scale == ImageViewerPanMath.doubleTapScale)
    }

    @Test func doubleTapZoomsAroundTheTapPointThenResets() {
        var viewer = ImageViewerInteraction()
        let point = CGPoint(x: 300, y: 400)
        let effects = send(.doubleTap(location: point), to: &viewer)
        #expect(effects == [.animate])
        #expect(viewer.scale == ImageViewerPanMath.doubleTapScale)
        let before = math.visibleImageRect(at: 1, offset: .zero)
        let after = math.visibleImageRect(at: viewer.scale, offset: viewer.offset)
        let fractionBefore = (point.x - before.minX) / before.width
        let fractionAfter = (point.x - after.minX) / after.width
        #expect(abs(fractionBefore - fractionAfter) < 0.0001)
        send(.doubleTap(location: point), to: &viewer)
        #expect(viewer.scale == 1)
        #expect(viewer.offset == .zero)
    }

    @Test func voiceOverZoomStepsAndToggleKeepTheImageCentred() {
        var viewer = ImageViewerInteraction()
        send(.toggleZoom, to: &viewer)
        #expect(viewer.scale == ImageViewerPanMath.doubleTapScale)
        #expect(viewer.offset == .zero)
        send(.zoomStep(zoomingIn: true), to: &viewer)
        #expect(viewer.scale == ImageViewerPanMath.maximumScale)
    }
}
