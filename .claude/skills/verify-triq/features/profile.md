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
  Expect the sheet to close.
- Second view: open Profile again. Expect the username and email and no guest card.
  `vt shot profile-account`, `vt tree profile-account`.
- Close with `vt tap --id xmark.circle.fill`.
- Record: `feature=profile entry=home-profile-toolbar result=pass`; for the upgrade, a `live=` line with
  the username, the uid and `claimUsername`.

## Gotchas

- Tap "Sign Out" and "Delete Account" only with the owner's yes: a sign-out loses a guest for good,
  and a delete writes live.
- The statistics count only an account's own saves: a guest's earlier save shows as 0 after the
  upgrade (by design: `saveQuestionAnswers` skips `users/<uid>` for a guest).
- The upgrade links the guest (`AuthModel.linkAnonymousAccount`), so by source the uid stays the
  same. The log does not prove it: on 2026-10-21 it named `users/<uid>` only at the guest sign-in,
  and no second uid showed in the run.
