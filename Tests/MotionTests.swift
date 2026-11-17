import SwiftUI
import Testing
@testable import TTB

/// Pins each token to the literal its call sites used before `Motion` existed. A refactor that
/// retunes a value fails here and has to say so on purpose.
struct MotionTests {
    @Test func feedbackTokensKeepTheirCurves() {
        #expect(Motion.quickFade == .easeOut(duration: 0.2))
        #expect(Motion.press == .easeOut(duration: 0.16))
    }

    @Test func contentChangeTokensKeepTheirCurves() {
        #expect(Motion.contentChange == .easeInOut(duration: 0.2))
        #expect(Motion.scrollToFocusedField == .easeInOut(duration: 0.25))
    }

    @Test func settleTokensKeepTheirSprings() {
        #expect(Motion.pageSwitch == .snappy(duration: 0.25))
        #expect(Motion.cardHeightSettle == .spring(response: 0.35, dampingFraction: 0.85))
        #expect(Motion.listSettle == .spring(duration: 0.35, bounce: 0))
        #expect(Motion.stepChange == .spring(response: 0.32, dampingFraction: 0.88))
    }

    @Test func gestureResetKeepsItsSpring() {
        #expect(Motion.gestureReset == .spring(duration: 0.3, bounce: 0))
    }

    @Test func toastTokensKeepTheirValues() {
        #expect(Motion.toastIn == .spring(response: 0.36, dampingFraction: 0.82))
        #expect(Motion.toastOut == .easeOut(duration: 0.18))
        #expect(Motion.toastSnapBack == .spring(response: 0.28, dampingFraction: 0.86))
    }

    @Test func revealTokensKeepTheirValues() {
        #expect(Motion.reveal == .spring(response: 0.56, dampingFraction: 0.86))
        #expect(Motion.badgeEnter == .spring(duration: 0.5, bounce: 0.3))
        #expect(Motion.badgeTextEnter == .easeOut(duration: 0.3).delay(0.12))
    }

    @Test(arguments: [0, 1, 4])
    func chipStaggerDelaysByFiftyMillisecondsPerIndex(index: Int) {
        #expect(Motion.chipStagger(index: index) == .easeOut.delay(Double(index) * 0.05))
    }

    @Test func launchTokensKeepTheirValues() {
        #expect(Motion.launchCoverFade == .easeOut(duration: 0.25))
        #expect(Motion.launchPulse == .easeInOut(duration: 0.9).repeatForever(autoreverses: true))
    }
}
