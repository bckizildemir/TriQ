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
        #expect(result.width == 40 + 100 * ImageViewerPanMath.momentumFactor)
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
