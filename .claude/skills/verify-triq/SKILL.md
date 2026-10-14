---
name: verify-triq
description: Drive the real TriQ (TTB) iOS app on a fresh, private simulator and capture proof of what a user sees — screenshots and accessibility trees of the sign-in, guest onboarding, Home feed and other mapped journeys, in English or Turkish. The app always talks to the live Firebase project, so each feature file names what it writes. Use when a PR needs a verify-triq proof, when asked to check a change in the running app, or when CLAUDE.md's "Verify trial" asks for a simulator check.
---

# verify-triq

Prove a user-visible change in the real app: a Debug build, launched with no arguments, on a
simulator this run creates and deletes, with data entered only through screens a user has. The
evidence survives the run in `~/verify-evidence/triq/`.

Everything goes through one helper. From the repo root:

```bash
V=.claude/skills/verify-triq/scripts/vt.sh
```

`$V` with no argument lists the subcommands. The run state lives in `/tmp/verify-triq.lock/`
(`udid`, `evidence`, `owner`, …), so each new shell finds the same run:
`UDID=$(cat /tmp/verify-triq.lock/udid)`.

## Rules (owner decisions, 2026-10-13 to 2026-10-15)

- Build only with `Scripts/xcb.sh` (`$V build` calls it). No bare `xcodebuild`, no xcodebuildmcp
  `build_*`/`build_run_sim`, no `Scripts/run-ios.sh`: they skip the machine-wide build lock.
- Launch with **no launch arguments**: never a `-ui-test-*` flag from `TTB/App/UITestLaunchOptions.swift`.
  Those harnesses skip Firebase and run on fixtures, so they prove nothing about the real app. A
  feature that only a harness can reach is not verifiable here: say so.
- Data only through user screens. Not a harness: the XCUITest suite `TTBUITests`.
- Drive with `axe` (or xcodebuildmcp `snapshot_ui`/`tap`/`type_text`/`screenshot` with this run's
  `simulatorId`) and `xcrun simctl`. Never osascript, never scripted mouse clicks: the owner works on
  the same Mac.
- One fresh simulator per run, one driver. Touch no other simulator — not the shared `iPhone 12`
  devices that TriQ, Purrtine and other sessions use. Never `xcrun simctl shutdown all`. One verify
  run at a time across both apps: `$V start` waits for `/tmp/verify-triq.lock` and for any Purrtine
  verify run with a fresh lock (`/tmp/verify-purrtine.lock`, heartbeat under 45 minutes old). The wait
  is one-way: Purrtine's `vp.sh` does not check for a TriQ run.
- Device: **iPhone 12, iOS 26.5** (owner, 2026-10-15).

## Live Firebase (read before you drive)

`TTB/GoogleService-Info.plist` is tracked in git (project `ttbp-9d652`), so **every** build talks
to the real backend. There is no offline mode. Every feature file carries one live-data class:

| Class | Meaning | Before the drive |
| --- | --- | --- |
| local only | no Firestore, Storage, Auth or function call | nothing |
| reads live | reads Firestore/Storage only | nothing |
| writes live | writes Firestore/Storage/Auth or calls a free callable | the owner's yes for this action |
| paid | calls a paid AI callable (Trio, AI answers) | the owner's yes for this action |

Owner rule (2026-10-15): a run may read; each write or paid call needs a yes, and a yes covers one
action, not the next one (`~/.claude/CLAUDE.md`, "Cloud spend needs the user's yes"). Ask in plain
words: what the run taps, what it leaves on the server, what it may cost. The QA account
(TriQ memory `triq-qa-test-account.md`) also needs a yes before a run signs in with it.

A fresh device can only reach Home through a sign-in, and the cheapest one is **Continue as
Guest**: it creates one anonymous Firebase Auth user and one `users/<uid>` document (free tier,
no cost). **Standing yes (owner, 2026-10-15): every verify run and every maintenance pass may
create one guest this way.** The app is not published; the owner removes these test guests before
the release. So write the guest's uid (from the device log, `users/<uid>` paths) in a `live=` line in
`run.txt`, so that the clean-up can find each one.

### App Check (a registered debug token)

Firestore and the AI callables enforce App Check. Debug builds use the App Check **debug** provider
(`TTB/App/AppCheckPolicy.swift`), which makes a random token per install. Firebase rejects a token
nobody registered, so on 2026-10-15 a fresh device got "Missing or insufficient permissions" on every
read and write. The owner registered one fixed debug token (`verify-triq`) in the Firebase console on
2026-10-15. It lives only on this Mac at `~/.config/verify-triq/appcheck-debug-token` (mode 600).
`$V install` stores it in the app's defaults (`GACAppCheckDebugToken`) before the first launch, and
`$V doctor` fails when the app does not hold it.

- **Paid calls now succeed.** With the registered token, the AI callables (Trio "generate ideas",
  AI answers) pass App Check and cost money. Never tap them without the owner's yes for that drive.
- **The token is a key to the live project, and it does not expire.** Never print it, commit it,
  paste it in a PR, or copy it off this Mac. If it leaks, the owner deletes it in the Firebase console
  (App Check → Apps → the iOS app → Manage debug tokens) and a new one is registered.
- If the token file is missing, `$V install` stops. Ask the owner to register a new token; do not
  drive without it (every Firestore read fails).

## Launch

```bash
$V start                       # verify lock, fresh device, English; add --lang tr for Turkish
$V build                       # Scripts/xcb.sh build against this device; copies TTB.app
$V hold                        # take the xcb lock for the drive (see "Why hold")
$V install
$V launch                      # prints "app.berke.can.kizildemir.ttb: <pid>"
$V doctor                      # must exit 0
```

- `start` creates `verify-triq-<run-id>` (iPhone 12, iOS 26.5; `VT_DEVICE` or `--device` to
  override), boots it, writes its system language, reboots it, and makes the evidence folder
  `~/verify-evidence/triq/<YYYY-MM-DD>-<run-id>/` with `run.txt` (device, language, git rev).
- `build` needs `TTB/Secrets.xcconfig`. A new worktree has none: `cp TTB/Secrets.xcconfig.template
  TTB/Secrets.xcconfig` first, never commit it. `build` stops with that message when it is missing.
- `build` can wait up to an hour for the xcb build lock. Run it in the background
  (`run_in_background`) and read its output when it finishes. It keeps the verify lock fresh while
  it waits; SIGINT and SIGTERM stop that heartbeat and exit non-zero. A SIGKILL cannot be trapped:
  run `$V cleanup` afterwards.
- `launch` waits up to 30 s until axe reads a labelled tree.
- Ready means usable: `$V ui` lists the sign-in screen with `Button | Continue as Guest`. A fresh
  device always starts there (no automatic guest sign-in). The Simulator window need not be open:
  on 2026-10-15 axe read the full tree with no Simulator window.
- Teardown is `$V cleanup` (see Cleanup).

### Why hold

`Scripts/xcb.sh test` shuts down other booted simulators before it runs (`shut_down_other_simulators`).
Since 2026-10-15 it skips devices named `verify-*`, but a checkout with an older `xcb.sh` does not, and
other builds still compete for this 16 GB Mac during a drive. `$V hold` takes the same machine-wide lock that xcb uses (`~/Library/Caches/xcb/build.lock`, its
`pid` and `owner` files), owned by a watcher process, so other sessions' builds and tests wait while
you drive. It ends at `$V cleanup`, or after 30 minutes (`VT_HOLD_MAX=<seconds>`). Take it after
`build` — `build` needs that lock itself — and keep the drive short.

**Owner decision (2026-10-14):** a drive may hold the xcb build lock for up to 30 minutes, which
pauses every build and test on the Mac, Purrtine's too. Accepted. A longer pass re-runs `$V hold`.
A change to the lock format in `Scripts/xcb.sh` must update `vt.sh` in the same PR. `$V status` and
`$V doctor` report whether the watcher is alive.

## Doctor

`$V doctor` is read-only. It prints the run owner, the device state, whether the app is installed
and running, the app's command line (and fails on any `-ui-test` argument), the device language, the
number of labelled accessibility elements, the live-Firebase line, the hold state and other booted
simulators. Exit 0 means worth driving. Run it first whenever anything looks off.

- `FAIL device is not booted` → another session shut it down. `$V revive` boots it and relaunches
  the app; the app's data on the device stays. Redo the step that was in flight.
- `WARN app is not running` → `$V launch`.
- `WARN another simulator is booted` → owner decision: warn and continue. The run never shuts down a
  device it did not create.
- `WARN the hold watcher … is not running` → `$V hold` again (the 30 minutes ran out or it died).
- `WARN empty accessibility tree` → call xcodebuildmcp `open_sim`, then retry.
- `WARN the copied app has no GoogleService-Info.plist` → not the real app; rebuild.

## Drive

`axe` is on `PATH` (`/opt/homebrew/bin/axe`, 1.8.0). Read before every action, act, read again:

```bash
UDID=$(cat /tmp/verify-triq.lock/udid)
$V ui                                             # Type | Label | Id | Value | frame [disabled]
$V tap --once --label 'Continue as Guest' --element-type Button   # writes live: no retap
$V tap --id onboarding-continue-button
axe type 'coffee' --udid $UDID                    # after a tap on the field
axe tap -x 195 -y 420 --tap-style physical --udid $UDID   # only when an element has no id or label
```

- Prefer `--id` (identifiers do not change with the language), then `--label` with
  `--element-type`. The sign-in screen and the tab bar have no identifiers; use labels.
- Use `$V tap`, not a bare `axe tap`. `axe tap` exits 0 even when nothing happened. `$V tap` taps
  with `--tap-style physical --wait-timeout 10`, waits up to 8 s for the tree to change, and taps
  once more only when it did not; it exits 1 when the screen still did not change. Never retap blindly.
- **A tap that writes live uses `$V tap --once`** (no second tap): "Continue as Guest", Save, Publish,
  a signed-in favorite. A slow server call can take longer than 8 s, and a second tap would write
  twice (a second guest user) or undo the first. After a `--once` warning, read `$V ui`; do not tap again.
- System alerts show in `$V ui` as SpringBoard elements (the notification and photo permission
  prompts appear only on the last onboarding step, and only when the user taps Allow on that card).
- xcodebuildmcp works too: pass `simulatorId=$UDID` to `snapshot_ui`, `tap` (element refs from
  `snapshot_ui` only), `type_text` and `screenshot`. Never call its `boot_sim`, `build_run_sim` or
  `session_set_defaults` with another device.

The recipes are in `features/` — read `features/README.md`, then the feature's file.
[Guest onboarding](features/guest-onboarding.md) comes first: every other feature starts on Home.

## Evidence

```bash
$V shot login                   # PNG  -> <evidence>/NN-login.png
$V tree login                   # JSON -> <evidence>/NN-login.json
echo "feature=guest-onboarding entry=first-launch result=pass" >> "$(cat /tmp/verify-triq.lock/evidence)/run.txt"
```

Proof standards:

- Real user path only: no launch flags, no harness, no test-only screen.
- Capture the action and the result: a shot before the step that matters and after it, plus a tree
  for every state you assert on.
- Prove a save from a second view (a list, Home, Profile), not from the sheet that closed.
- Side effects on the server: you cannot read live Firestore from the run. Prove a write from a
  second screen that reads it back, and say which server effects you did not see.
- The photo pickers (`ImagePicker.swift` PHPicker, `EditProfileView` PhotosPicker) run out of
  process; axe sees none of their cells. Never claim a photo pick.
- Add a `feature=… entry=… result=…` line to `run.txt` for each feature you drove, and a
  `live=…` line that names what the run wrote to the server.
- In the PR: attach the key screenshots, name the evidence folder and the feature files you followed.

## Cleanup

```bash
$V cleanup
```

It terminates the app, shuts down and deletes **this run's** device (only a device named
`verify-triq-*` that the lock records), releases the xcb hold and the verify lock, keeps the
evidence folder, and prints `du -sh ~/verify-evidence/triq`. Put that line in your report, so the
owner knows when to clean the folder. A failed `simctl delete` prints a warning and cleanup goes on.
Run cleanup after a failed attempt too. Cleanup does not touch the server: a guest user or any data
the run wrote stays there.

A crashed run leaves `/tmp/verify-triq.lock`. The next `$V start` treats it as stale when its device
no longer exists or nobody touched it for 45 minutes (`VT_STALE_MINUTES`), deletes that stale
`verify-triq-*` device, and goes on. The hold watcher ends by itself when the verify lock goes.

## Gotchas

- **`xcb.sh` prints the wrong .app.** Its `xcb: app` line names the first `.app` in the products
  folder, which can be `TTBUITests-Runner.app`. `$V build` takes `TTB.app` by name.
- **Shared DerivedData.** Every worktree builds into one DerivedData. `$V build` copies the app into
  the lock folder at once and fails when a newer TTB build log exists; run it again.
- **A fresh device copies the Mac's languages** (`en-TR`, `tr-TR`). `$V start` writes the device
  language (`en-US` or `tr-TR`) and reboots. The app's source language is Turkish; one language per
  device, a change needs a fresh run.
- **Autocorrect and Turkish letters.** A save takes the keyboard's suggestion (Purrtine saw `Tarcin`
  saved as `Tar in`), and axe cannot type `ç` or `ı`. Type real English dictionary words.
- **Tabs keep their stack.** A tab reopens on its last pushed screen. Read `$V ui` and tap
  `BackButton` before you use a tab's root.
- **Live data changes.** Question text, categories and counts come from the live database and change
  from day to day. Assert on identifiers and structure, not on a question's text.
- **App Check.** See "Live Firebase": without the registered token nothing loads; with it, paid AI
  calls succeed. A Firestore "Missing or insufficient permissions" in the device log
  (`xcrun simctl spawn $UDID log show --last 5m --predicate 'process == "TTB"'`) means first check
  `$V doctor`'s `appcheck` line.
- **Labels collide.** The category chip `Home` and the tab `Home` share a label. Tap tabs with
  `--element-type RadioButton`.
- **The hold blocks every build on the Mac.** Keep a drive short.

## Helpers

- `scripts/vt.sh` — the run: `start [--device NAME] [--lang en|tr]`, `build`, `hold`, `install`,
  `launch`, `doctor`, `ui`, `tap [--once] AXE-TAP-ARGS…`, `shot NAME`, `tree NAME`, `revive`, `cleanup`,
  `status`. `$V` alone prints this list.

## Maintenance pass (`/maintain-verification-skill`)

The owner starts it by typing it; an agent cannot. A pass drives **every** feature on **one**
device, in one language, in one run: `start`, `build` (background), `hold`, `install`, `launch`,
`doctor`, then guest onboarding first and the other features in the order of `features/README.md`.
Each feature marked writes live or paid needs the owner's yes before that drive. When the watcher is
gone, run `$V hold` again. Teardown (`$V cleanup`) happens once, after the last drive.

Keep the map honest as the app changes with `/maintain-verification-skill`.
