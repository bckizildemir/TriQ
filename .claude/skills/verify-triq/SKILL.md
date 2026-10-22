---
name: verify-triq
description: Drive the real TriQ (TTB) iOS app on a fresh, private simulator and capture proof of what a user sees — screenshots and accessibility trees of the sign-in, guest onboarding, Home feed and other mapped journeys, in English or Turkish. The app always talks to the live Firebase project, so each feature file names what it writes. Use when a PR needs a verify-triq proof, when asked to check a change in the running app, or when CLAUDE.md's "Verify trial" asks for a simulator check.
---

# verify-triq

Prove a user-visible change in the real app: a Debug build, launched with no arguments, on a
simulator this run creates and deletes, with data entered only through screens a user has. The
evidence survives the run in `~/verify-evidence/triq/`.

Everything goes through one helper, `.claude/skills/verify-triq/scripts/vt.sh`. Below, `$V` is
short for that path. Type the full relative path from the repo root in each command: the permission
allow rule matches that path, and a worktree session refuses a command name held in a variable
(2026-10-21). Write the UDID out in full for the same reason.

`$V` with no argument lists the subcommands. The run state lives in `/tmp/verify-triq.lock/`
(`udid`, `evidence`, `owner`, …), so each new shell finds the same run:
`cat /tmp/verify-triq.lock/udid`.

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
- Device: **iPhone 12, iOS 27.0** (owner, 2026-10-15; `--os 26.5` for an older runtime).

## Live Firebase (read before you drive)

`TTB/GoogleService-Info.plist` is tracked in git (project `ttbp-9d652`), so **every** build talks
to the real backend. There is no offline mode. Every feature file carries one live-data class:

| Class | Meaning | Before the drive |
| --- | --- | --- |
| local only | no Firestore, Storage, Auth or function call | nothing |
| reads live | reads Firestore/Storage only | nothing |
| writes live | writes Firestore/Storage/Auth or calls a non-AI callable | the owner's yes for this action |
| AI call | calls an AI callable (`aiCallable` in `functions/index.js`) | the owner's yes for this action |

**AI calls** go through `functions/aiProviderProxy.js`: Groq (`openai/gpt-oss-120b`) by default,
free for now (owner, 2026-10-21). The tracked `functions/.env.ttbp-9d652` sets `AI_PROVIDER=groq`;
nobody has checked the deployed functions' values. With `AI_PROVIDER=openrouter` the default model
(`x-ai/grok-4.1-fast`) is not a `:free` model and bills, so treat every AI call as one that can bill. Each also counts against a daily quota per uid
(`DAILY_LIMITS` in `functions/aiUsageLimit.js`) and a daily quota for the whole project
(`PROJECT_DAILY_LIMITS`, one pool for guests and accounts with no verified email, one for verified
accounts; quick answers: 50 a day in the guest pool). A full pool refuses the call, so a card open
can show no AI quick answers. **Opening a question card is an AI call**: it calls
`suggestQuickAnswers` by itself when the question has fewer than 5 stored quick answers
(`QuestionCardExpandedView.loadQuickAnswerSuggestions`).

Owner rule (2026-10-15): a run may read; each write or AI call needs a yes, and a yes covers one
action, not the next one (`~/.claude/CLAUDE.md`, "Cloud spend needs the user's yes"). Ask in plain
words: what the run taps, what it leaves on the server, what it may cost. The QA account
(TriQ memory `triq-qa-test-account.md`) needs a yes before a run signs in with it, and a run's own
account (below) needs a yes before the upgrade that makes it.

A fresh device can only reach Home through a sign-in, and the cheapest one is **Continue as
Guest**: it creates one anonymous Firebase Auth user and one `users/<uid>` document (free tier,
no cost). **Standing yes (owner, 2026-10-15): every verify run and every maintenance pass may
create one guest this way.** The app is not published; the owner removes these test guests before
the release. So write the guest's uid (from the device log, `users/<uid>` paths) in a `live=` line in
`run.txt`, so that the clean-up can find each one.

### A run's own account (a permanent account)

The Trio composer and the signed-in profile open only for a permanent account. **Owner decision
(2026-10-21): each run that needs one makes its own account** by an upgrade of the run's guest
([Profile and guest upgrade](features/profile.md)). Reuse of an earlier run's account is not the
recipe. Before the upgrade, write the run's credentials file (mode 600) and type the values from it:

```bash
umask 077; mkdir -p ~/.config/verify-triq/accounts
# file ~/.config/verify-triq/accounts/<run-id>, three lines:
#   username=verifytriq-<run-id>            (Latin letters, digits, . _ - ; at most 64)
#   email=verifytriq-<run-id>@example.com
#   password=<16 random letters and digits>Aa1
```

`<run-id>` is the evidence folder's name (for example `2026-10-21-140704-1396`). The password stays
out of every shot, tree, `run.txt`, PR and report. Record the username and the uid in a `live=` line.

- **Password fields (iOS 27, #99):** first tap each "Show password" eye button, then tap the field. A
  focused secure field opens the system "Use Strong Password?" popup: it runs out of process, axe
  cannot see it, it drops the typed text and it can leave every later tap dead until the device
  reboots (2026-10-21). With an eye open the field shows the password in plain text: take no
  `shot` or `tree` until the sheet is closed. Users hit the same popup: #99 tracks the app fix.
- The owner removes these accounts and their data with the other test data before the release.

### App Check (a registered debug token)

Firestore and the AI callables enforce App Check. Debug builds use the App Check **debug** provider
(`TTB/App/AppCheckPolicy.swift`), which makes a random token per install. Firebase rejects a token
nobody registered, so on 2026-10-15 a fresh device got "Missing or insufficient permissions" on every
read and write. The owner registered one fixed debug token (`verify-triq`) in the Firebase console on
2026-10-15. It lives only on this Mac at `~/.config/verify-triq/appcheck-debug-token` (mode 600).
`$V install` stores it in the app's defaults (`GACAppCheckDebugToken`) before the first launch, and
`$V doctor` fails when the app does not hold it.

- **AI calls now succeed.** With the registered token, the AI callables (Trio "generate ideas",
  AI answers, quick answers on card open) pass App Check. Drive them only with the owner's yes.
- **The token is a key to the live project, and it does not expire.** Never print it, commit it,
  paste it in a PR, or copy it off this Mac. If it leaks, the owner deletes it in the Firebase console
  (App Check → Apps → the iOS app → Manage debug tokens) and a new one is registered.
- If the token file is missing, `$V install` stops. Ask the owner to register a new token; do not
  drive without it (every Firestore read fails).

## Launch

```bash
.claude/skills/verify-triq/scripts/vt.sh start                       # verify lock, fresh device, English; add --lang tr for Turkish
.claude/skills/verify-triq/scripts/vt.sh build                       # Scripts/xcb.sh build against this device; copies TTB.app
.claude/skills/verify-triq/scripts/vt.sh hold                        # take the xcb lock for the drive (see "Why hold")
.claude/skills/verify-triq/scripts/vt.sh install
.claude/skills/verify-triq/scripts/vt.sh launch                      # prints "app.berke.can.kizildemir.ttb: <pid>"
.claude/skills/verify-triq/scripts/vt.sh doctor                      # must exit 0
```

- `start` creates `verify-triq-<run-id>` (iPhone 12, iOS 27.0; `VT_DEVICE`/`--device` and
  `VT_OS`/`--os` to override), boots it, writes its system language, reboots it, and makes the evidence folder
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
- `FAIL the app is hung` → the app shows fewer than 3 labelled elements and runs at 90 % CPU or more
  in 3 samples 1 s apart (a SwiftUI layout loop, 2026-10-21). `$V revive` ends the app and launches
  it again in about 5 s. Doctor reads the tree for 15 s at most (then TERM, then KILL after 2 s),
  because axe waits on a hung app for over a minute.
- `FAIL the app … exited during doctor` → `$V launch`, then doctor again.
- Every tap is dead but swipes work, after a system popup → shut down and boot **this run's**
  device only (`xcrun simctl shutdown <UDID>`, `xcrun simctl boot <UDID>`), then `$V launch`.
- `WARN app is not running` → `$V launch`.
- `WARN another simulator is booted` → owner decision: warn and continue. The run never shuts down a
  device it did not create.
- `WARN the hold watcher … is not running` → `$V hold` again (the 30 minutes ran out or it died).
- `WARN empty accessibility tree` → call xcodebuildmcp `open_sim`, then retry.
- `WARN the copied app has no GoogleService-Info.plist` → not the real app; rebuild.

## Drive

`axe` is on `PATH` (`/opt/homebrew/bin/axe`, 1.8.0). Read before every action, act, read again:

```bash
.claude/skills/verify-triq/scripts/vt.sh ui                                             # Type | Label | Id | Value | frame [disabled]
.claude/skills/verify-triq/scripts/vt.sh tap --once --label 'Continue as Guest' --element-type Button   # writes live: no retap
.claude/skills/verify-triq/scripts/vt.sh tap --id onboarding-continue-button
axe type 'coffee' --udid <UDID>                   # after a tap on the field
axe tap -x 195 -y 420 --tap-style physical --udid <UDID>   # only when an element has no id or label
axe swipe --start-x 195 --start-y 600 --end-x 195 --end-y 250 --udid <UDID>   # scroll down
```

`<UDID>` is the literal value from `/tmp/verify-triq.lock/udid`.

- Prefer `--id` (identifiers do not change with the language), then `--label` with
  `--element-type`. The sign-in screen and the tab bar have no identifiers; use labels.
- Use `$V tap`, not a bare `axe tap`. `axe tap` exits 0 even when nothing happened. `$V tap` taps
  with `--tap-style physical --wait-timeout 10`, waits up to 8 s for the tree to change, and taps
  once more only when it did not; it exits 1 when the screen still did not change. Never retap blindly.
  "screen changed" means only that the tree changed (a toast or an animation can do that): read
  `$V ui` for the element you expect.
- **A tap that writes live uses `$V tap --once`** (no second tap): "Continue as Guest", Save, Publish,
  a signed-in favorite. A slow server call can take longer than 8 s, and a second tap would write
  twice (a second guest user) or undo the first. After a `--once` warning, read `$V ui`; do not tap again.
- System alerts show in `$V ui` as SpringBoard elements (the notification and photo permission
  prompts appear only on the last onboarding step, and only when the user taps Allow on that card).
- xcodebuildmcp works too: pass `simulatorId=<UDID>` to `snapshot_ui`, `tap` (element refs from
  `snapshot_ui` only), `type_text` and `screenshot`. Never call its `boot_sim`, `build_run_sim` or
  `session_set_defaults` with another device.

The recipes are in `features/` — read `features/README.md`, then the feature's file.
[Guest onboarding](features/guest-onboarding.md) comes first: every other feature starts on Home.

## Evidence

```bash
.claude/skills/verify-triq/scripts/vt.sh shot login                   # PNG  -> <evidence>/NN-login.png
.claude/skills/verify-triq/scripts/vt.sh tree login                   # JSON -> <evidence>/NN-login.json
echo "feature=guest-onboarding entry=first-launch result=pass" >> <evidence>/run.txt   # the literal path in /tmp/verify-triq.lock/evidence
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
.claude/skills/verify-triq/scripts/vt.sh cleanup
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
  saved as `Tar in`), and axe cannot type `ç` or `ı`. Type real English dictionary words. The
  answer fields capitalise the first letter (`coffee` saves as `Coffee`), and on 2026-10-21
  `axe type 'tea'` was dropped again and again while `milk`, `coffee` and `water` worked: read the
  field's value after each `axe type`.
- **The floating tab bar covers the bottom of the screen** (y ≥ 761 on iPhone 12). A tap there hits
  a tab. Scroll until the element you want has a frame above y = 735.
- **Tabs keep their stack.** A tab reopens on its last pushed screen. Read `$V ui` and tap
  `BackButton` before you use a tab's root.
- **Live data changes.** Question text, categories and counts come from the live database and change
  from day to day. Assert on identifiers and structure, not on a question's text.
- **App Check.** See "Live Firebase": without the registered token nothing loads; with it, AI
  calls succeed. A Firestore "Missing or insufficient permissions" in the device log
  (`xcrun simctl spawn <UDID> log show --last 5m --predicate 'process == "TTB"'`) means first check
  `$V doctor`'s `appcheck` line.
- **Labels collide.** The category chip `Home` and the tab `Home` share a label. Tap tabs with
  `--element-type RadioButton`.
- **The hold blocks every build on the Mac.** Keep a drive short.
- **iOS 27.0 boot.** On 2026-10-13 a shared iOS 27.0 device's SpringBoard crashed about 11 times in
  2 minutes at boot, then ran stable (Purrtine). If `start` or `launch` hangs or `doctor` shows an
  empty tree, run `$V cleanup` and start again; if it repeats, use `$V start --os 26.5` and say so.
- **`build` passes the run's OS to xcb** (`XCB_OS`). xcb finds `XCB_SIMULATOR` by name only on that
  runtime; without it an iOS 27 device is not found.

## Helpers

- `scripts/vt.sh` — the run: `start [--device NAME] [--lang en|tr]`, `build`, `hold`, `install`,
  `launch`, `doctor`, `ui`, `tap [--once] AXE-TAP-ARGS…`, `shot NAME`, `tree NAME`, `revive` (boot
  the device if needed, end the app, launch it again), `cleanup`, `status`. `$V` alone prints this list.

## Maintenance pass (`/maintain-verification-skill`)

The owner starts it by typing it; an agent cannot. A pass drives **every** feature on **one**
device, in one language, in one run: `start`, `build` (background), `hold`, `install`, `launch`,
`doctor`, then guest onboarding first and the other features in the order of `features/README.md`.
Each feature marked writes live or AI call needs the owner's yes before that drive. When the watcher
is gone, run `$V hold` again. Teardown (`$V cleanup`) happens once, after the last drive. A full pass
took about 45 minutes on 2026-10-21 (the favorites cap alone about 10).

Keep the map honest as the app changes with `/maintain-verification-skill`.
