import CoreGraphics
import Testing
@testable import TTB

struct ImageViewerPanMathTests {
    /// A 400x800 screen with a square 400x400 image fitted to the width.
    private let math = ImageViewerPanMath(
        containerSize: CGSize(width: 400, height: 800),
        fittedSize: CGSize(width: 400, height: 400)
    )

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

    @Test func pinchOutScalesTheOffsetWithTheZoom() {
        let result = math.rescaledOffset(CGSize(width: 100, height: 0), from: 2, to: 3)
        #expect(result == CGSize(width: 150, height: 0))
    }

    @Test func pinchOutReclampsTheOffset() {
        // 3x allows 400; zooming back to 2x allows 200, so 400 -> 266 clamps to 200.
        let result = math.rescaledOffset(CGSize(width: 400, height: 0), from: 3, to: 2)
        #expect(result.width == 200)
    }

    @Test func offsetResetsWhenZoomReturnsToOneTimes() {
        let result = math.rescaledOffset(CGSize(width: 150, height: 100), from: 3, to: 1)
        #expect(result == .zero)
    }

    @Test func momentumCarriesAShareOfThePredictedTravel() {
        let result = math.settledOffset(
            offset: .zero,
            translation: CGSize(width: 40, height: 0),
            predictedEndTranslation: CGSize(width: 140, height: 0),
            at: 3,
            withMomentum: true
        )
        // 40 + (140 - 40) * 0.35
        #expect(abs(result.width - 75) < 0.0001)
    }

    @Test func tapInsideTheFittedImageHitsIt() {
        // 400x400 image centred in 400x800: y 200...600.
        #expect(math.imageContains(CGPoint(x: 200, y: 400), at: 1, offset: .zero))
        #expect(math.imageContains(CGPoint(x: 10, y: 210), at: 1, offset: .zero))
    }

    @Test func tapOnTheBlackBandsMissesTheImage() {
        #expect(!math.imageContains(CGPoint(x: 200, y: 100), at: 1, offset: .zero))
        #expect(!math.imageContains(CGPoint(x: 200, y: 700), at: 1, offset: .zero))
    }

    @Test func visibleImageFollowsZoomAndPan() {
        // 2x: 800x800 around the centre (200, 400) is x -200...600, y 0...800.
        #expect(math.imageContains(CGPoint(x: 5, y: 790), at: 2, offset: .zero))
        // Panned 200 left: x -400...400; the right edge of the screen is now black.
        let panned = CGSize(width: -200, height: 0)
        #expect(!math.imageContains(CGPoint(x: 400.5, y: 400), at: 2, offset: panned))
        #expect(math.imageContains(CGPoint(x: 399, y: 400), at: 2, offset: panned))
    }

    @Test func unmeasuredImageIsNeverHit() {
        let unmeasured = ImageViewerPanMath(containerSize: .zero, fittedSize: .zero)
        #expect(!unmeasured.imageContains(.zero, at: 1, offset: .zero))
    }

    @Test func glideStartsWithTheReleaseSpeedAsAShareOfItsDistance() {
        // 100 points to go at 300 points per second: 3 distances per second.
        let velocity = ImageViewerPanMath.initialVelocity(
            from: .zero,
            to: CGSize(width: 100, height: 0),
            releaseVelocity: CGSize(width: 300, height: 0)
        )
        #expect(abs(velocity - 3) < 0.0001)
    }

    @Test func glideAgainstTheFingerOrWithNoDistanceStartsAtRest() {
        let against = ImageViewerPanMath.initialVelocity(
            from: .zero,
            to: CGSize(width: -100, height: 0),
            releaseVelocity: CGSize(width: 300, height: 0)
        )
        #expect(against == 0)
        let none = ImageViewerPanMath.initialVelocity(
            from: CGSize(width: 50, height: 0),
            to: CGSize(width: 50, height: 0),
            releaseVelocity: CGSize(width: 300, height: 0)
        )
        #expect(none == 0)
    }

    @Test func glideStartSpeedIsCapped() {
        let velocity = ImageViewerPanMath.initialVelocity(
            from: .zero,
            to: CGSize(width: 2, height: 0),
            releaseVelocity: CGSize(width: 5000, height: 0)
        )
        #expect(velocity == 20)
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

    @Test func shiftMovesTheTapTestWithTheImage() {
        // At 1x the image spans y 206.5...606.5.
        #expect(shifted.imageContains(CGPoint(x: 200, y: 606), at: 1, offset: .zero))
        #expect(!shifted.imageContains(CGPoint(x: 200, y: 607), at: 1, offset: .zero))
        #expect(!shifted.imageContains(CGPoint(x: 200, y: 206), at: 1, offset: .zero))
    }

    // MARK: Drag mode and zoom steps

    @Test func dragThatBeginsZoomedPans() {
        #expect(ImageViewerPanMath.dragMode(isZoomed: true, isPinching: false) == .pan)
        #expect(ImageViewerPanMath.dragMode(isZoomed: true, isPinching: true) == .pan)
    }

    @Test func dragAtOneTimesDismissesUnlessAPinchRuns() {
        #expect(ImageViewerPanMath.dragMode(isZoomed: false, isPinching: false) == .dismiss)
        #expect(ImageViewerPanMath.dragMode(isZoomed: false, isPinching: true) == .ignored)
    }

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

    @Test func momentumTargetIsClamped() {
        let result = math.settledOffset(
            offset: CGSize(width: 190, height: 0),
            translation: CGSize(width: 5, height: 0),
            predictedEndTranslation: CGSize(width: 900, height: 0),
            at: 2,
            withMomentum: true
        )
        #expect(result.width == 200)
    }

    @Test func noMomentumSettlesAtTheReleasePointInsideTheClamp() {
        let inside = math.settledOffset(
            offset: .zero,
            translation: CGSize(width: 60, height: 0),
            predictedEndTranslation: CGSize(width: 900, height: 0),
            at: 3,
            withMomentum: false
        )
        #expect(inside.width == 60)
        let outside = math.settledOffset(
            offset: .zero,
            translation: CGSize(width: 900, height: 0),
            predictedEndTranslation: CGSize(width: 900, height: 0),
            at: 2,
            withMomentum: false
        )
        #expect(outside.width == 200)
    }
}
