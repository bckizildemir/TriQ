import SwiftUI

/// Named animation curves, springs and durations shared across the app.
///
/// Every value here is the literal a call site used before the tokens existed. Nothing is tuned:
/// a token that looks like a near duplicate of another one stays its own token until someone
/// decides to merge them on purpose.
///
/// Reduce Motion is not decided here. A call site that must switch the animation off or swap it
/// still does that itself.
enum Motion {
    // MARK: - Feedback

    /// `easeOut` over 0.2 s. A small state flip that needs no travel: the favorite star in the
    /// question card, the expanded card and Most Answered, and the badge-unlock fade under
    /// Reduce Motion. Ease-out so the first frames respond at once.
    static let quickFade = Animation.easeOut(duration: 0.2)

    /// `easeOut` over 0.16 s. The pressed state of a button style (`ProfileView`).
    /// Short, because it follows the finger down and up.
    static let press = Animation.easeOut(duration: 0.16)

    // MARK: - Content change

    /// `easeInOut` over 0.2 s. Swaps content or nudges a scroll position where the change moves
    /// from one resting state to another: the profile image set and removed (`ProfileModel`) and
    /// the registration form scrolling to the password field.
    static let contentChange = Animation.easeInOut(duration: 0.2)

    /// `easeInOut` over 0.25 s. The answer form scrolling the focused slot to the center
    /// (`QuestionCardExpandedView`).
    static let scrollToFocusedField = Animation.easeInOut(duration: 0.25)

    // MARK: - Settle

    /// `snappy` over 0.25 s. The page indicator dots resizing when the current page changes
    /// (`PagedCardView`). The pages themselves do not move with it. Nil under Reduce Motion.
    static let pageSwitch = Animation.snappy(duration: 0.25)

    /// Spring, response 0.35 and damping 0.85. The card pager resizing to the height of the
    /// page it shows (`PagedCardView`).
    static let cardHeightSettle = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Spring over 0.35 s without bounce. A row leaving or joining the favorites list
    /// (`FavoritesView`).
    static let listSettle = Animation.spring(duration: 0.35, bounce: 0)

    /// Spring, response 0.32 and damping 0.88. One onboarding step replacing the next
    /// (`OnboardingFlowView`).
    static let stepChange = Animation.spring(response: 0.32, dampingFraction: 0.88)

    // MARK: - Dismiss and snap-back

    /// Spring over 0.3 s without bounce. A gesture that lifts and returns to rest: the answer
    /// image viewer's zoom reset and the snap-back of a short 1x drag (`AnswerImageFullscreenView`).
    static let gestureReset = Animation.spring(duration: 0.3, bounce: 0)

    // MARK: - Toast

    /// Spring, response 0.36 and damping 0.82. A toast appearing (`ToastCenter.show`).
    static let toastIn = Animation.spring(response: 0.36, dampingFraction: 0.82)

    /// `easeOut` over 0.18 s. A toast leaving (`ToastCenter.dismiss`).
    static let toastOut = Animation.easeOut(duration: 0.18)

    /// Spring, response 0.28 and damping 0.86. A toast dragged up that did not pass the dismiss
    /// threshold, returning to rest (`AppToastView`).
    static let toastSnapBack = Animation.spring(response: 0.28, dampingFraction: 0.86)

    // MARK: - Reveal

    /// Spring, response 0.56 and damping 0.86. The AI tab disclosure sections appearing
    /// (`AITabDisclosureView`). The caller adds `.delay(_:)` per section to stagger them.
    static let reveal = Animation.spring(response: 0.56, dampingFraction: 0.86)

    /// The suggestion chips appearing one after the other (`SuggestionChipsContainer`):
    /// the default `easeOut` duration, started `index * 0.05` s late.
    static func chipStagger(index: Int) -> Animation {
        .easeOut.delay(Double(index) * 0.05)
    }

    /// Spring over 0.5 s with 0.3 bounce. The badge growing in (`BadgeUnlockMotion`).
    static let badgeEnter = Animation.spring(duration: 0.5, bounce: 0.3)

    /// `easeOut` over 0.3 s, started 0.12 s late. The badge-unlock title, description and button
    /// fading in after the badge (`BadgeUnlockMotion`).
    static let badgeTextEnter = Animation.easeOut(duration: 0.3).delay(0.12)

    // MARK: - Launch

    /// `easeOut` over 0.25 s. The launch logo cover fading in and out (`AppRootView`). Opacity
    /// only, so it also runs under Reduce Motion.
    static let launchCoverFade = Animation.easeOut(duration: 0.25)

    /// `easeInOut` over 0.9 s, repeating forever with autoreverse. The launch logo breathing
    /// (`LaunchLoadingView`). The call site turns it off under Reduce Motion.
    static let launchPulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
}
