import SwiftUI

/// How `BadgeUnlockView` enters: the badge grows in with a small bounce, then the text fades in.
///
/// With Reduce Motion on, nothing scales: the badge, the text and the button fade in together.
struct BadgeUnlockMotion {
    let reduceMotion: Bool

    /// The badge's scale before it enters. Never 0: nothing in the real world appears from nothing.
    var initialBadgeScale: CGFloat {
        reduceMotion ? 1 : 0.85
    }

    /// Drives the badge's scale and opacity.
    var badgeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.3)
    }

    /// Drives the title, description and button. Ease-out, so the first frames are not slow.
    var textAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3).delay(0.12)
    }
}
