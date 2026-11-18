import CoreGraphics
import Testing
@testable import TTB

struct ImageViewerPanMathTests {
    /// A 400x800 screen with a square 400x400 image fitted to the width.
    private let math = ImageViewerPanMath(
        containerSize: CGSize(width: 400, height: 800),
        fittedSize: CGSize(width: 400, height: 400)
    )

    private func isClose(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

    // MARK: Clamp

    @Test func offsetIsZeroAtOneTimesZoom() {
        #expect(math.clamp(CGSize(width: 50, height: -30), at: 1) == .zero)
        #expect(math.maxOffset(at: 1) == .zero)
    }

    @Test(arguments: [
        (CGFloat(2), CGFloat(200)),
        (CGFloat(3), CGFloat(400)),
        (CGFloat(5), CGFloat(800))
    ])
    func widthIsClampedToScaledOverhang(scale: CGFloat, limit: CGFloat) {
        let tooFarRight = math.clamp(CGSize(width: 10_000, height: 0), at: scale)
        let tooFarLeft = math.clamp(CGSize(width: -10_000, height: 0), at: scale)
        #expect(tooFarRight.width == limit)
        #expect(tooFarLeft.width == -limit)
    }

    @Test func offsetInsideTheRangeIsUntouched() {
        let offset = CGSize(width: 120, height: 0)
        #expect(math.clamp(offset, at: 2) == offset)
    }

    @Test func imageShorterThanTheScreenStaysCenteredVertically() {
        // At 2x the image is 800 tall: it exactly fills the screen height, so no vertical pan.
        #expect(math.maxOffset(at: 2).height == 0)
        #expect(math.clamp(CGSize(width: 0, height: 500), at: 2).height == 0)
        // At 3x it is 1200 tall: 200 points of overhang each side.
        #expect(math.clamp(CGSize(width: 0, height: 500), at: 3).height == 200)
        #expect(math.clamp(CGSize(width: 0, height: -500), at: 3).height == -200)
    }

    @Test func imageNarrowerThanTheScreenStaysCenteredHorizontally() {
        let tall = ImageViewerPanMath(
            containerSize: CGSize(width: 400, height: 800),
            fittedSize: CGSize(width: 200, height: 800)
        )
        // 2x: 400 wide, equal to the screen, no horizontal pan; 800 -> 1600 tall pans.
        #expect(tall.clamp(CGSize(width: 90, height: 90), at: 2) == CGSize(width: 0, height: 90))
        #expect(tall.maxOffset(at: 2).height == 400)
    }

    @Test func unmeasuredViewerDoesNotPan() {
        let unmeasured = ImageViewerPanMath(containerSize: .zero, fittedSize: .zero)
        #expect(unmeasured.clamp(CGSize(width: 40, height: 40), at: 3) == .zero)
    }

    @Test func scaleIsLimitedToTheSupportedRange() {
        #expect(ImageViewerPanMath.clampedScale(0.4) == 1)
        #expect(ImageViewerPanMath.clampedScale(2.5) == 2.5)
        #expect(ImageViewerPanMath.clampedScale(40) == ImageViewerPanMath.maximumScale)
    }

    // MARK: Visible rect

    @Test func visibleRectAtOneTimesIsTheFittedImageCentered() {
        // 400x400 image centred in 400x800: y 200...600.
        #expect(math.visibleImageRect(at: 1, offset: .zero) == CGRect(x: 0, y: 200, width: 400, height: 400))
    }

    @Test func visibleRectFollowsZoomAndPan() {
        // 2x: 800x800 around the centre (200, 400) is x -200...600, y 0...800.
        #expect(math.visibleImageRect(at: 2, offset: .zero) == CGRect(x: -200, y: 0, width: 800, height: 800))
        // Panned 200 left: x -400...400.
        let panned = math.visibleImageRect(at: 2, offset: CGSize(width: -200, height: 0))
        #expect(panned == CGRect(x: -400, y: 0, width: 800, height: 800))
    }

    // MARK: Safe-area centre shift

    /// Top inset 47, bottom inset 34: the image rests 6.5 points below the screen's centre.
    private let shifted = ImageViewerPanMath(
        containerSize: CGSize(width: 400, height: 800),
        fittedSize: CGSize(width: 400, height: 400),
        restCenterShift: CGSize(width: 0, height: 6.5)
    )

    @Test func shiftedRangeStillCoversBothScreenEdges() {
        // 3x: 1200 tall, 200 overhang each side, then moved by the 6.5 shift.
        #expect(shifted.clamp(CGSize(width: 0, height: 1000), at: 3).height == 193.5)
        #expect(shifted.clamp(CGSize(width: 0, height: -1000), at: 3).height == -206.5)
    }

    @Test func shiftedAxisWithNoOverhangStaysAtRest() {
        // 2x: 800 tall fills the 800 screen exactly: no vertical pan, shift or not.
        #expect(shifted.clamp(CGSize(width: 0, height: 100), at: 2).height == 0)
    }

    @Test func shiftMovesTheVisibleRect() {
        // At 1x the image spans y 206.5...606.5.
        #expect(shifted.visibleImageRect(at: 1, offset: .zero) == CGRect(x: 0, y: 206.5, width: 400, height: 400))
    }

    // MARK: Zoom steps

    @Test func zoomStepsGoThroughOneTwoAndAHalfAndFive() {
        #expect(ImageViewerPanMath.steppedScale(from: 1, zoomingIn: true) == 2.5)
        #expect(ImageViewerPanMath.steppedScale(from: 2.5, zoomingIn: true) == 5)
        #expect(ImageViewerPanMath.steppedScale(from: 5, zoomingIn: true) == 5)
        #expect(ImageViewerPanMath.steppedScale(from: 5, zoomingIn: false) == 2.5)
        #expect(ImageViewerPanMath.steppedScale(from: 2.5, zoomingIn: false) == 1)
        #expect(ImageViewerPanMath.steppedScale(from: 1, zoomingIn: false) == 1)
        #expect(ImageViewerPanMath.steppedScale(from: 1.7, zoomingIn: true) == 2.5)
        #expect(ImageViewerPanMath.steppedScale(from: 1.7, zoomingIn: false) == 1)
    }

    // MARK: Pan and pinch in one transform

    @Test func panMovesTheImageOneToOneWithTheFinger() {
        let result = math.transform(
            startScale: 3,
            startOffset: .zero,
            anchor: CGPoint(x: 200, y: 400),
            pinchFactor: 1,
            location: CGPoint(x: 240, y: 430)
        )
        #expect(result.scale == 3)
        #expect(result.offset == CGSize(width: 40, height: 30))
    }

    @Test func panAddsToTheOffsetTheDragStartedWith() {
        let result = math.transform(
            startScale: 3,
            startOffset: CGSize(width: 100, height: -20),
            anchor: CGPoint(x: 50, y: 60),
            pinchFactor: 1,
            location: CGPoint(x: 10, y: 60)
        )
        #expect(result.offset == CGSize(width: 60, height: -20))
    }

    @Test func panStopsAtTheEdgesOfTheImage() {
        let result = math.transform(
            startScale: 2,
            startOffset: .zero,
            anchor: .zero,
            pinchFactor: 1,
            location: CGPoint(x: 900, y: 900)
        )
        #expect(result.offset == CGSize(width: 200, height: 0))
    }

    @Test func pinchKeepsTheImagePointBetweenTheFingersInPlace() {
        // The fingers sit at (300, 400) on the 1x image: 100 right of its centre.
        let anchor = CGPoint(x: 300, y: 400)
        let result = math.transform(
            startScale: 1,
            startOffset: .zero,
            anchor: anchor,
            pinchFactor: 2,
            location: anchor
        )
        #expect(result.scale == 2)
        // The point under the fingers is the same fraction of the image before and after.
        let before = math.visibleImageRect(at: 1, offset: .zero)
        let after = math.visibleImageRect(at: 2, offset: result.offset)
        #expect(isClose((anchor.x - before.minX) / before.width, (anchor.x - after.minX) / after.width))
        #expect(result.offset == CGSize(width: -100, height: 0))
    }

    @Test func pinchOnAnImageAlreadyZoomedAndPannedKeepsTheFingerPoint() {
        let anchor = CGPoint(x: 150, y: 500)
        let startOffset = CGSize(width: 80, height: 60)
        let result = math.transform(
            startScale: 3,
            startOffset: startOffset,
            anchor: anchor,
            pinchFactor: 1.5,
            location: anchor
        )
        let before = math.visibleImageRect(at: 3, offset: startOffset)
        let after = math.visibleImageRect(at: result.scale, offset: result.offset)
        #expect(isClose((anchor.x - before.minX) / before.width, (anchor.x - after.minX) / after.width))
        #expect(isClose((anchor.y - before.minY) / before.height, (anchor.y - after.minY) / after.height))
    }

    @Test func fingersMovingWhilePinchingMoveTheImage() {
        let anchor = CGPoint(x: 300, y: 400)
        let still = math.transform(startScale: 1, startOffset: .zero, anchor: anchor, pinchFactor: 2, location: anchor)
        let moved = math.transform(
            startScale: 1,
            startOffset: .zero,
            anchor: anchor,
            pinchFactor: 2,
            location: CGPoint(x: 280, y: 400)
        )
        #expect(moved.offset.width == still.offset.width - 20)
    }

    @Test func pinchScaleStaysInsideTheSupportedRange() {
        let anchor = CGPoint(x: 200, y: 400)
        let big = math.transform(startScale: 2, startOffset: .zero, anchor: anchor, pinchFactor: 100, location: anchor)
        #expect(big.scale == ImageViewerPanMath.maximumScale)
        let small = math.transform(startScale: 2, startOffset: .zero, anchor: anchor, pinchFactor: 0.01, location: anchor)
        #expect(small.scale == 1)
        #expect(small.offset == .zero)
    }

    @Test func pinchWithAShiftedRestCentreStillKeepsTheFingerPoint() {
        let anchor = CGPoint(x: 300, y: 420)
        let result = shifted.transform(
            startScale: 1,
            startOffset: .zero,
            anchor: anchor,
            pinchFactor: 3,
            location: anchor
        )
        let before = shifted.visibleImageRect(at: 1, offset: .zero)
        let after = shifted.visibleImageRect(at: 3, offset: result.offset)
        #expect(isClose((anchor.x - before.minX) / before.width, (anchor.x - after.minX) / after.width))
        #expect(isClose((anchor.y - before.minY) / before.height, (anchor.y - after.minY) / after.height))
    }

    // MARK: Glide

    @Test func glideCarriesTheReleaseSpeedAndSlowsDown() {
        let step = math.glideStep(offset: .zero, velocity: CGSize(width: 1000, height: 0), deltaTime: 0.016, at: 3)
        #expect(step.offset.width > 0)
        #expect(step.offset.width < 16)
        #expect(step.velocity.width < 1000)
        #expect(step.velocity.width > 0)
        #expect(!step.isFinished)
    }

    @Test func glideStopsAtTheEdgeAndDropsThatAxisSpeed() {
        let step = math.glideStep(
            offset: CGSize(width: 199, height: 0),
            velocity: CGSize(width: 5000, height: 0),
            deltaTime: 0.016,
            at: 2
        )
        #expect(step.offset.width == 200)
        #expect(step.velocity.width == 0)
        #expect(step.isFinished)
    }

    @Test func glideFinishesWhenTooSlowToSee() {
        let step = math.glideStep(offset: .zero, velocity: CGSize(width: 5, height: 5), deltaTime: 0.016, at: 3)
        #expect(step.isFinished)
    }

    @Test func glideEventuallyEnds() {
        var offset = CGSize.zero
        var velocity = CGSize(width: 1200, height: 0)
        var frames = 0
        while frames < 1000 {
            let step = math.glideStep(offset: offset, velocity: velocity, deltaTime: 1.0 / 60, at: 5)
            offset = step.offset
            velocity = step.velocity
            frames += 1
            if step.isFinished { break }
        }
        #expect(frames < 1000)
        #expect(offset.width > 0)
    }

    @Test func releaseProjectionAddsTheShareOfTheVelocity() {
        let end = ImageViewerPanMath.projectedEnd(translation: 60, velocity: 800)
        #expect(isClose(end, 60 + 800 * ImageViewerPanMath.projectionDuration))
    }
}
