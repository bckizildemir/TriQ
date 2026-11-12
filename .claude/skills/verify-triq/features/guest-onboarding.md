# Guest onboarding

A first launch on a fresh device shows the sign-in screen. "Continue as Guest" signs in
anonymously, then a five-step intro runs: welcome, example, value, sharing, permissions. The last
step needs the legal toggle, and "See Today's Questions" lands on Home. Every other feature starts
here. Proved end to end on 2026-10-15 (run `2026-10-15-005622-39fa`, iPhone 12, iOS 26.5, English)
and on 2026-10-21 (run `2026-10-21-140704-1396`, iOS 27.0, English, Back included). Re-driven
2026-11-12 (run `2026-11-12-180550-18bb`, iOS 27.0, English), sign-in form and legal links included.

**Live-data class: writes live (free).** The guest tap creates one anonymous Firebase Auth user and
the finish writes onboarding fields to `users/<uid>`. Standing yes from the owner: one guest per run
(see `../SKILL.md`, Live Firebase). Record the uid in a `live=` line in `run.txt`.

## Sub-features

- `login` the sign-in screen: "Welcome", "Username or email field", "Password field", an eye button
  ("Show password" `eye` / "Hide password" `eye.slash`), "Sign In", "Don't have an account?",
  "Continue as Guest". Only the eye has an identifier.
- `login-username` the first field takes an email or a username: a username goes through the callable
  `resolveUsername` first. An unknown name shows an alert (a `Sheet` named "Error") with "User not
  found." and an OK button; the server log shows `resolveusername` 404. An unknown email with a
  password shows "The supplied auth credential is malformed or has expired." instead.
- `login-register` "Don't have an account?" pushes a Sign Up screen: `Heading` "Sign Up", `BackButton`,
  Username / Email / Password / Confirm password fields, two eye buttons, "Sign Up". The recipe does
  not use it (a run's account comes from the guest upgrade, see [Profile](./profile.md)); `BackButton`
  returns to the sign-in screen.
- `guest` "Continue as Guest" opens the intro at `Onboarding progress` = `20 percent`.
- `intro` four taps on `onboarding-continue-button` (label "Continue") reach `100 percent`, 20 percent
  per step. A "Skip" button shows on all steps but the last (Skip jumps to the last step). From step 2
  a Button with label "Back" and identifier `chevron.left` goes one step back.
- `permissions` the last step has two "Allow" buttons (Notifications, Photos). They are optional;
  a tap opens the system prompt. The recipe does not tap them.
- `legal` `onboarding-continue-button` reads "See Today's Questions" and is `[disabled]` until the
  "Agree to the legal terms" button (`circle` → `checkmark.circle.fill`) is on. Next to it the text
  "By continuing, you agree to" with two `Link`s, "Terms of Service" and "Privacy Policy" (they open
  Safari; the recipe only reads them from the tree).
- `finish` "See Today's Questions" lands on Home: a greeting heading, "Today's Questions", the
  chip row `home-category-chip-*` and the tab bar.

## How to get to it (user POV)

- The first launch on a device with no session. There is no other entry point: a signed-in device
  never shows it again, so a new run needs a new device (`vt start`).

## Driving it with axe

Preconditions: a fresh run through `vt doctor` (exit 0, `appcheck:` line present). `vt ui` shows
`Button | Continue as Guest`.

- `vt shot login`. Sign-in form (optional, reads live): `vt tap --label 'Username or email field'`,
  `axe type 'nobodyxyzq'`, `vt tap --label 'Show password'`, `vt tap --label 'Password field'`,
  `axe type 'milk1234'`, `vt tap --once --label 'Sign In' --element-type Button`. Expect the "Error" /
  "User not found." sheet in `vt ui`; `vt tap --label OK --element-type Button`. Then `vt tap
  --label "Don't have an account?"` shows Sign Up, `vt tap --id BackButton` returns.
- `vt tap --once --label 'Continue as Guest' --element-type Button`
  (`--once`: a second tap could create a second guest user).
- Expect `GenericElement | Onboarding progress | | 20 percent` and `onboarding-continue-button`.
  `vt shot onboarding-welcome`, `vt tree onboarding-welcome`.
- `vt tap --id onboarding-continue-button`: expect `40 percent` and the Back button. `vt tap --id
  chevron.left`: expect `20 percent`. This checks Back.
- Four times: `vt tap --id onboarding-continue-button`. Expect `100 percent`, two "Allow" buttons
  (do not tap), no "Skip", and `See Today's Questions … [disabled]`.
- `vt tap --label 'Agree to the legal terms' --element-type Button`. The button is now enabled.
  `vt shot onboarding-final-legal-on`.
- `vt tap --id onboarding-continue-button`. Wait about 5 s. Expect `Today's Questions`, at least
  one `question-card-home.today-<id>`, the `home-category-chip-*` buttons, and three `RadioButton`
  tabs. `vt shot home`, `vt tree home`.
- The guest uid: `xcrun simctl spawn <UDID> log show --last 15m --predicate 'process == "TTB"' | grep -oE 'users/[A-Za-z0-9]{20,}' | sort -u`.
  On 2026-11-12 this printed nothing (no `users/<uid>` line in the log): write `uid not in log` in the
  `live=` line and name the account by its username once it has one.
- Record: `feature=guest-onboarding entry=first-launch result=pass` and the `live=` line with the uid.
- On the last step, read the legal links from `vt ui` (`Link | Terms of Service`, `Link | Privacy Policy`):
  do not tap them.

## Gotchas

- Without the registered App Check token, the intro shows "Onboarding state could not be loaded. The
  intro flow will be shown again." (an alert with OK; the intro still runs) and the finish shows "Onboarding could not be completed. Please try again." (run
  `2026-10-15-004022-181b`). Check `vt doctor`'s `appcheck` line first.
- On 2026-10-15, with the token, the device log still showed one refused
  `Write at users/<uid> failed: Missing or insufficient permissions` near the guest sign-in; the
  onboarding completed. Reproduced in a third run; cause and fix are in #94 (two `ensureExists`
  calls race at sign-in). Seen again on 2026-10-21 (iOS 27.0). Expected until #94 is fixed; after
  the fix, its absence is the proof.
- `vt ui` also lists the elements of the screens a sheet or cover hides (2026-11-12: under the Trio
  disclosure cover, the New List sheet and the card cover it still printed the Home tree). Trust `vt shot` for what is on top.
- The greeting heading changes with the time of day ("Good night 🌙"); do not assert on it.
