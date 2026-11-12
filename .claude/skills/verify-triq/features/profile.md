# Profile and guest upgrade

The Home toolbar button "Profile" opens the profile as a full-screen cover. A guest sees an
upgrade card; an account sees its username, email, badges and statistics. The upgrade links the
guest to an email account. Proved on 2026-10-21 (run `2026-10-21-140704-1396`, iOS 27.0, English).
Re-driven 2026-11-12 (run `2026-11-12-180550-18bb`, iOS 27.0, English): guest and account profile, the
upgrade by the favorites strip, Edit Profile, both deletes.

**Live-data class:** opening = reads live. **The upgrade = writes live**: the guest's Auth user gets
an email and password, the callable `claimUsername` claims `usernames/<username>`, and `users/<uid>`
gets the username. It makes a permanent account, so it needs the owner's yes for that one account.

## Sub-features

- `profile-guest` `Heading` "Profile"; "Guest User / Not signed in"; `profile-guest-upgrade-button`
  ("Save your progress", with "3 of 10 favorites saved on this device…"); a note "You can keep exploring
  in guest mode."; rows "My Favorites" (`profile-content-favorites`), "My Answers", "Question Lists"
  (a guest sees "Account Required" there); a "Content updates" toggle (`CheckBox`, value 0; its caption
  "Enable this to get notified when new categories or curated questions are released."; the recipe
  does not toggle it, the first switch asks for the notification permission); "Sign Out"; "Delete
  Account".
- `profile-close` the Close button is a Button "Close" with identifier `xmark.circle.fill` (there is no
  `profile-close` identifier).
- `guest-upgrade` `profile-guest-upgrade-button` (or the Home card list button, the Trio "+", the
  favorites strip "Keep them") opens the sheet `guest-upgrade-sheet` ("Upgrade Account", "Save Your
  Progress"): "Cancel", fields Username, Email, Password, Confirm password, two "Show password"
  buttons, and "Create Account" (`[disabled]` until all fields are valid). There is no
  `profile-guest-upgrade-sheet` identifier.
- `post-upgrade` after "Create Account" the sheet and Profile close and Home shows the toast
  `guest-favorite-migration-toast` ("Your favorites have been saved.") when the guest had favorites. No
  other notice showed on 2026-11-12.
- `profile-account` after the upgrade: `profile-photo-button` ("Profile photo", opens the photo
  sheet; the picker runs out of process), the username and email, "My Content" rows (`profile-content-favorites`,
  "My Answers", "Question Lists"), the "Content updates" toggle, "Badges" ("0 of 30 badges unlocked",
  six `profile-badge-<id>-button` buttons such as `profile-badge-career_focused-button`, label "Career
  Oriented badge, locked", "+24 more" and "View All"), `profile-statistics-section` ("Statistics, 0,
  Today, 0, This Week, 0, Total"), `profile-edit-button` ("Edit Profile"), "Sign Out"; no upgrade card, no
  favorites strip and no "Delete Account" row. Sheet identifiers in the source: `profile-photo-sheet`,
  `profile-edit-sheet` (seen), `profile-statistics-sheet`, `profile-delete-password-sheet` (seen),
  `profile-badge-detail-sheet`, `profile-badge-unlock-sheet`. A tap on a locked badge opened nothing on
  2026-11-12.

## How to get to it (user POV)

- Home → the "Profile" toolbar button.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done; Home on screen.

- `vt tap --label Profile`. Expect `Heading` "Profile" and `profile-guest-upgrade-button`.
  `vt shot profile-guest`, `vt tree profile-guest`.
- Upgrade (standing yes for one new account; write the run's credentials file first, see
  `../SKILL.md`, "A run's own account"): `vt tap --id profile-guest-upgrade-button`. Tap both "Show password" buttons
  first, then fill Username, Email, Password, Confirm password from the file. Take no shot or tree
  while the sheet shows the password. `vt tap --once --label 'Create Account' --element-type Button`.
  Expect the sheet and Profile to close and Home to show: the jump to Home is intended (owner,
  2026-11-12, #136).
- Second view: open Profile again. Expect the username and email and no guest card.
  `vt shot profile-account`, `vt tree profile-account`.
- Close with `vt tap --id xmark.circle.fill`.
- Record: `feature=profile entry=home-profile-toolbar result=pass`; for the upgrade, a `live=` line with
  the username, the uid and `claimUsername`.

## Delete account (proved 2026-11-11, run `2026-11-11-035301-3e84`; re-proved 2026-11-12, run `2026-11-12-180550-18bb`, iOS 27.0, English)

**Writes live** (covered by the standing yes until release): `deleteOwnAccountData` removes the Auth user,
`users/<uid>` and the claimed username.

Guest:
- Home → Profile. Scroll until "Delete Account" sits above y=735, then `vt tap --once --label 'Delete Account'`.
  A popover opens: `vt tap --once --label 'Delete Guest Account'`.
- Expect the Welcome/sign-in screen, no alert. `vt revive` (a real kill and relaunch) → still sign-in.

Permanent account (the signed-in profile has no "Delete Account" row; it lives in Edit Profile):
- Profile, then swipe up twice (`axe swipe --start-x 195 --start-y 650 --end-x 195 --end-y 150`) until
  `profile-edit-button` is on screen → `vt tap --id profile-edit-button` (sheet `profile-edit-sheet`:
  "Cancel editing profile", "Save profile changes", Username field, "Delete Account") →
  `vt tap --once --label 'Delete Account' --element-type Button` → a sheet: "Delete My Account
  Permanently" → the sheet `profile-delete-password-sheet`: "Enter your password again" field, eye
  `eye` → tap the eye **first** (same popup trap as the upgrade), tap the field (coordinate, x 190, y
  422), type the password from the run's credentials file, then read `vt ui` and check the value
  equals the file's (`eye.slash` = shown) → tap "Delete My Account Permanently" (`--once`; with the
  keyboard up its top part is under the keys: tap by coordinate at y ≈ 495, x 195).
- A wrong password does not delete: a red line under the field reads "The supplied auth credential is
  malformed or has expired." (2026-11-12; no alert, no server call). The failed-delete alert with
  "Try again" (a server failure) was not reproduced.
- Expect sign-in, no alert. Signing in with the same email and password shows "The supplied auth credential
  is malformed or has expired." That alert is the proof the account is gone. Take no shot while the
  password is shown.
- Server check (read-only): `gcloud logging read` for the service `deleteownaccountdata` in europe-west1
  shows `200` and "Callable request verification passed {app: VALID, auth: VALID}"; Auth
  `accounts:lookup` for the email returns no user; Firestore `usernames/<name>` returns 404.
- Record: `feature=profile entry=delete-account result=pass` and update the `live=` lines (deleted).

## Gotchas

- **Dead taps after a hidden-eye password (2026-11-12).** Typing in the delete sheet's field with the
  eye closed showed a "Passwords" bar on the keyboard and every later tap did nothing (Cancel included),
  while `vt doctor` was clean. Fix: `xcrun simctl shutdown <UDID>`, `xcrun simctl boot <UDID>`,
  `vt launch`; the session survives (still signed in). Keep the eye open for every password.
- A shot taken with the eye open shows the password in plain text: delete it at once.
- The red error line stays on screen after a wrong password, also once the field holds the right one
  (2026-11-12). It is not a result: only `Welcome` or a new error is. With the keyboard up the red
  button's lower part is under the keys, so a tap at y ≈ 545 hit the keyboard and did nothing (no
  `deleteownaccountdata` call in the log); tap at y ≈ 495.
- "Sign Out" loses a guest for good; tap it only with the owner's yes. "Delete Account" writes live
  and is covered by the standing yes until release (see above).
- The upgrade sheet's "Create Account" sits under the keyboard: swipe the sheet up ~250 px first, or a
  tap lands on a key. Both "Show password" buttons share one label: tap the eyes by coordinate.
- After Sign In, a system "Save Password?" popup appears that axe cannot see: dismiss "Not Now" by
  coordinate. `vt launch` on a running app only foregrounds it; use `vt revive` to prove a relaunch.
- The statistics count only an account's own saves: a guest's earlier save shows as 0 after the
  upgrade (by design: `saveQuestionAnswers` skips `users/<uid>` for a guest).
- The upgrade links the guest (`AuthModel.linkAnonymousAccount`), so by source the uid stays the
  same. The log does not prove it: on 2026-10-21 it named `users/<uid>` only at the guest sign-in,
  and no second uid showed in the run.
