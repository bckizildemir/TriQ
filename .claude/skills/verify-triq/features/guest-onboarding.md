# Guest onboarding

A first launch on a fresh device shows the sign-in screen. "Continue as Guest" signs in
anonymously, then a five-step intro runs: welcome, example, value, sharing, permissions. The last
step needs the legal toggle, and "See Today's Questions" lands on Home. Every other feature starts
here. Proved end to end on 2026-10-15 (run `2026-10-15-005622-39fa`, iPhone 12, iOS 26.5, English).

**Live-data class: writes live (free).** The guest tap creates one anonymous Firebase Auth user and
the finish writes onboarding fields to `users/<uid>`. Standing yes from the owner: one guest per run
(see `../SKILL.md`, Live Firebase). Record the uid in a `live=` line in `run.txt`.

## Sub-features

- `login` the sign-in screen: "Welcome", "Username or email field", "Password field", "Sign In",
  "Don't have an account?", "Continue as Guest". No identifiers on this screen.
- `guest` "Continue as Guest" opens the intro at `Onboarding progress` = `20 percent`.
- `intro` four taps on `onboarding-continue-button` (label "Continue") reach `100 percent`. A "Skip"
  button shows on all steps but the last; a "Back" button (`chevron.left`) from step 2.
- `permissions` the last step has two "Allow" buttons (Notifications, Photos). They are optional;
  a tap opens the system prompt. The recipe does not tap them.
- `legal` `onboarding-continue-button` reads "See Today's Questions" and is `[disabled]` until the
  "Agree to the legal terms" button (`circle` → `checkmark.circle.fill`) is on.
- `finish` "See Today's Questions" lands on Home: a greeting heading, "Today's Questions", the
  chip row `home-category-chip-*` and the tab bar.

## How to get to it (user POV)

- The first launch on a device with no session. There is no other entry point: a signed-in device
  never shows it again, so a new run needs a new device (`vt start`).

## Driving it with axe

Preconditions: a fresh run through `vt doctor` (exit 0, `appcheck:` line present). `vt ui` shows
`Button | Continue as Guest`.

- `vt shot login`, then `vt tap --once --label 'Continue as Guest' --element-type Button`
  (`--once`: a second tap could create a second guest user).
- Expect `GenericElement | Onboarding progress | | 20 percent` and `onboarding-continue-button`.
  `vt shot onboarding-welcome`, `vt tree onboarding-welcome`.
- Four times: `vt tap --id onboarding-continue-button`. Expect `100 percent` and
  `See Today's Questions … [disabled]`.
- `vt tap --label 'Agree to the legal terms' --element-type Button`. The button is now enabled.
  `vt shot onboarding-final-legal-on`.
- `vt tap --id onboarding-continue-button`. Wait about 5 s. Expect `Today's Questions`, at least
  one `question-card-home.today-<id>`, the `home-category-chip-*` buttons, and three `RadioButton`
  tabs. `vt shot home`, `vt tree home`.
- Record: `feature=guest-onboarding entry=first-launch result=pass` and the `live=` line.

## Gotchas

- Without the registered App Check token, the intro shows "Onboarding state could not be loaded."
  and the finish shows "Onboarding could not be completed. Please try again." (run
  `2026-10-15-004022-181b`). Check `vt doctor`'s `appcheck` line first.
- On 2026-10-15, with the token, the device log still showed one refused
  `Write at users/<uid> failed: Missing or insufficient permissions` near the guest sign-in; the
  onboarding completed. Reproduced in a third run; cause and fix are in #94 (two `ensureExists`
  calls race at sign-in). Expected until #94 is fixed; after the fix, its absence is the proof.
- The greeting heading changes with the time of day ("Good night 🌙"); do not assert on it.
