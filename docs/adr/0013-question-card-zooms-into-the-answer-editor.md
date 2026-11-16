# A tapped question card zooms into the answer editor, and a swipe may close it

Status: accepted, 2026-11-16 (owner). Overturns the "closed only by the Close button" part of decision #58
for an editor opened from a question card.

Tapping a question card opens the answer editor (`QuestionCardExpandedView`) in a `fullScreenCover` that grows
out of the card and shrinks back into it on close: the App Store "Today" card motion. The system zoom
transition does it (`matchedTransitionSource(id:in:)` on the card, `navigationTransition(.zoom(sourceID:in:))`
on the cover, iOS 18). A screen opts in with `questionCardZoomCover(item:cardSourceID:)`
(`TTB/Views/Components/QuestionCardZoomCover.swift`) in place of `fullScreenCover(item:)`.

## What changed from #58

Issue #58 (2026-10-14) decided that the editor is a full-screen cover, closed only by the Close button,
never by a swipe. The audit of 2026-11-16 (`animation-audits/TriQ-2026-11-16/AUDIT.md`) left the zoom open
because the zoom brings a swipe-down to close. On 2026-11-16 the owner allowed the swipe: the zoom is worth
more than the rule, and the Close button stays.

- **Opened from a card** (Home, category screen, Favorites, Answers, Best Of, Trio, a question list): zoom,
  and a swipe down closes the editor when nothing is unsaved.
- **Unsaved answer**: the swipe is refused (the editor springs back) and nothing is lost; Close still asks to
  save or drop. `DraftDismissalStyle.resolve` picks this; `DraftDismissalGuard` applies
  `interactiveDismissDisabled`, which UIKit maps to `isModalInPresentation` ("prevents the interactive
  dismissal of the view controller while it is onscreen"). The iOS 27 `dismissalConfirmationDialog` is not
  used here: no documentation says it hooks the zoom's swipe on a cover, and a dialog that never fires would
  drop the text.
- **No card to zoom from** (the shared-question deep link, a shared list's comparison rows, the What's New
  release screen): unchanged. #58 still holds there: a plain cover, closed only by the Close button.
- **Reduce Motion**: a cross-fade on iOS 27 (`Backport+CrossFadeNavigationTransition.swift`); before iOS 27
  the standard cover. The cover keeps the style it opened with, so turning Reduce Motion on mid-edit does not
  rebuild the editor and drop the draft.

## Considered options

- **A hand-built `matchedGeometryEffect` overlay.** Rejected. The cards sit in a page-style `TabView` in a
  `LazyVStack` in a `ScrollView`, and in a `List`; an overlay there is clipped by its container, sits under
  the navigation and tab bars, and fights the keyboard and safe areas. `matchedGeometryEffect` cannot reach
  across a `fullScreenCover`, so the editor would have to live in the feed's hierarchy and lose the cover's
  presentation of its sheets. The code still carries traces of such an attempt: `QuestionCard.isSelected`
  (hides the card while "expanded"), `PagedCardView.selectedQuestionID` (never set), the `expansionSourceID`
  names, `ExpandedQuestionHeaderStyle.showsMatchedMeta`.
- **Zoom with no swipe** (`interactiveDismissDisabled(true)` always). Rejected by the owner: the swipe back
  into the card is half of the motion.

## Consequences

- The transition ID is `<card sourceID>-<question id>`, the same shape as the card's accessibility
  identifier `question-card-<sourceID>-<question id>`. `QuestionCardZoom.transitionID` builds it on both
  sides; `QuestionCardZoomTests` covers the mapping.
- A screen with more than one card list (Home: today, each category) names the tapped list in
  `ExpandedQuestionState.cardSourceID`; a screen with one list passes it to `questionCardZoomCover`.
