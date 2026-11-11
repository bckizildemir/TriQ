# Profile and guest upgrade

The Home toolbar button "Profile" opens the profile as a full-screen cover. A guest sees an
upgrade card; an account sees its username, email, badges and statistics. The upgrade links the
guest to an email account. Proved on 2026-10-21 (run `2026-10-21-140704-1396`, iOS 27.0, English).

**Live-data class:** opening = reads live. **The upgrade = writes live**: the guest's Auth user gets
an email and password, the callable `claimUsername` claims `usernames/<username>`, and `users/<uid>`
gets the username. It makes a permanent account, so it needs the owner's yes for that one account.

## Sub-features

- `profile-guest` `Heading` "Profile"; "Guest User / Not signed in"; `profile-guest-upgrade-button`
  ("Save your progress", with the favorites count); rows "My Favorites", "My Answers", "Question
  Lists"; a "Content updates" toggle; "Sign Out"; "Delete Account".
- `profile-close` a Button "Close" (identifier `xmark.circle.fill`).
- `guest-upgrade` `profile-guest-upgrade-button` opens `profile-guest-upgrade-sheet`: "Cancel",
  fields Username, Email, Password, Confirm password, two "Show password" buttons, and "Create
  Account" (`[disabled]` until all fields are valid). The Trio "+" opens the same form as
  `guest-upgrade-sheet`.
- `profile-account` after the upgrade: the username and email, a photo button, "Badges 0 of 30",
  statistics, "Sign Out"; no upgrade card and no favorites strip.

## How to get to it (user POV)

- Home → the "Profile" toolbar button.

## Driving it with axe

Preconditions: [Guest onboarding](./guest-onboarding.md) done; Home on screen.

- `vt tap --label Profile`. Expect `Heading` "Profile" and `profile-guest-upgrade-button`.
  `vt shot profile-guest`, `vt tree profile-guest`.
- Upgrade (owner's yes for one new account; write the run's credentials file first, see
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

## Delete account (proved 2026-11-11, run `2026-11-11-035301-3e84`, iOS 27.0, English)

**Writes live** (covered by the standing yes until release): `deleteOwnAccountData` removes the Auth user,
`users/<uid>` and the claimed username.

Guest:
- Home → Profile. Scroll until "Delete Account" sits above y=735, then `vt tap --once --label 'Delete Account'`.
  A popover opens: `vt tap --once --label 'Delete Guest Account'`.
- Expect the Welcome/sign-in screen, no alert. `vt revive` (a real kill and relaunch) → still sign-in.

Permanent account (the signed-in profile has no "Delete Account" row; it lives in Edit Profile):
- Profile → `vt tap --id profile-edit-button` → "Delete Account" → a sheet: "Delete My Account Permanently"
  → a "Delete Account" screen asks "Enter your password again" (type it from the run's credentials file;
  eye button `eye`) → "Delete My Account Permanently" again (`--once`).
- Expect sign-in, no alert. Signing in with the same email and password shows "The supplied auth credential
  is malformed or has expired." That alert is the proof the account is gone.
- Server check (read-only): `gcloud logging read` for the service `deleteownaccountdata` in europe-west1
  shows `200` and "Callable request verification passed {app: VALID, auth: VALID}"; Auth
  `accounts:lookup` for the email returns no user; Firestore `usernames/<name>` returns 404.
- Record: `feature=profile entry=delete-account result=pass` and update the `live=` lines (deleted).

## Gotchas

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
