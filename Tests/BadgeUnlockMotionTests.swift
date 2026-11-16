import SwiftUI
import Testing
@testable import TTB

struct BadgeUnlockMotionTests {
    @Test func reduceMotionFadesEverythingInTogetherWithoutScaling() {
        let motion = BadgeUnlockMotion(reduceMotion: true)

        #expect(motion.initialBadgeScale == 1)
        #expect(motion.badgeAnimation == motion.textAnimation)
    }

    @Test func fullMotionGrowsTheBadgeInFromSlightlySmallThenFadesTheText() {
        let motion = BadgeUnlockMotion(reduceMotion: false)

        #expect(motion.initialBadgeScale > 0.5)
        #expect(motion.initialBadgeScale < 1)
        #expect(motion.badgeAnimation == .spring(duration: 0.5, bounce: 0.3))
        #expect(motion.textAnimation != motion.badgeAnimation)
    }
}
