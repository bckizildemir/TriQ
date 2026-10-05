# The Upgrade Prompt presents from the topmost controller, not from the root's SwiftUI tree

Supersedes `0004-per-screen-guest-upgrade-presentation.md` for the two sheets the app root owns.

The Upgrade Prompt (`FavoriteLimitSheet`) and the guest-upgrade sheet it opens are presented by one
owner, the app-root modifier, through a small UIKit bridge that finds the topmost presented view
controller and presents a `UIHostingController` on it. `ToastCenter.isGuestFavoriteLimitPromptPresented`
and `GuestFavoriteModel.shouldShowGuestUpgrade` stay the only triggers; no screen binds a `.sheet` to
them. The reason is issue #15: a SwiftUI `.sheet` presents only from the view it is attached to, so the
root-bound sheet never appeared while `QuestionCardExpandedView` — or any other `fullScreenCover` — was
up, and a guest who hit the cap from inside the expanded card saw nothing.

## Why UIKit

SwiftUI has no API to present above a cover whose depth the presenter does not know. The SwiftUI-only
alternative is to rebind the sheet at the root of every cover (more than ten call sites), which means
two `.sheet`s bound to one flag and a host that must know which cover is on top — the sequencing
machinery ADR 0004 rejected, and the per-screen presentation issue #15 rules out. The codebase already
accepts a UIKit bridge for the same job: `ToastOverlayInstaller` puts toasts in their own `UIWindow` so
they show above covers. The bridge is confined to one file; the prompt's content stays SwiftUI.

## Considered options

- **A second overlay window**, like the toast's. Rejected: the toast window passes touches through, so
  a modal in it needs its own window, key-window handling and hit-test rules — more machinery than
  presenting on the controller that is already on top.
- **Rebind in each cover.** Rejected above.

## Consequences

- The prompt is presented on whatever controller is topmost when the flag rises, so if the cover under
  it is dismissed, the prompt goes with it. The bridge resets the flag whenever its presented controller
  goes away for any reason, or the flag would stay raised and the prompt would never show again.
- "Create Free Account" dismisses the prompt and raises the guest-upgrade flag only after the dismissal
  completes, because UIKit refuses to present from a controller that is mid-dismissal. For the same
  reason `FavoriteLimitSheet` never calls SwiftUI's `dismiss()` itself: a second dismissal racing the
  owner's could swallow the completion that opens the upgrade sheet.
- "Topmost" means anything on top, not only a cover: the prompt now also appears over another sheet,
  such as a deep-link sheet, where the old root `.sheet` could not. That is intended.
- When nothing can present — no foreground key window, or UIKit refuses the presentation — the bridge
  reports the sheet gone at once, so the flag drops and that one cap event shows no prompt. The next
  time the guest reaches the cap it is raised again. A stuck flag would lose every later one.
- The three per-screen `GuestUpgradeView` flags ADR 0004 described (`QuestionCardExpandedView`,
  `FavoritesView`, `ProfileView`) are untouched here. ADR 0004 said they should move behind a host once
  one exists; that is follow-up work, not a regression.
