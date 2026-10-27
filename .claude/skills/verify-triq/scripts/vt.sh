#!/usr/bin/env bash
# vt.sh - one verify-triq run: a fresh simulator, the real TriQ app, evidence that survives.
#
# Subcommands (run from the repo root, in this order):
#   start [--device NAME] [--os X.Y] [--lang en|tr]
#                                         take the verify lock and a slot, clone the slim template
#                                         (Scripts/slim-sim.sh), boot the clone (default iOS 27.0)
#   build                                 Scripts/xcb.sh build against that device, copy TTB.app
#   hold                                  take the machine-wide xcb lock for the drive (see below)
#   install                               install the copied .app on the device
#   launch                                launch the app with NO launch arguments
#   doctor                                read-only: is this run worth driving?
#   ui                                    compact tree: type | label | id | value | frame
#   tap [--once] AXE-TAP-ARGS...          axe tap (physical style); waits up to 8 s for a change, then taps
#                                         once more unless --once (use --once on taps that write live)
#   shot NAME                             screenshot -> evidence/NN-NAME.png
#   tree NAME                             accessibility tree -> evidence/NN-NAME.json
#   revive                                boot the device if needed, end the app, launch it again
#   cleanup                               delete the device, drop the locks, keep the evidence
#   status                                print the run state
#
# State lives in the lock directory, so every Bash call (a new shell) finds the same run.
#
# The device: a SimSlim clone of the project's pristine slim template, "iPhone 12 slim tmpl
# (TriQ)" (profile in Scripts/simslim-profile.json), so every run starts as a brand-new user on a
# slim simulator. Clones take a machine-wide slot first (SLIM_SIM_MAX, default 2, shared with
# Purrtine's verify-purrtine), so a Purrtine run and this one can drive at the same time.
#
# Why hold: an older checkout of Scripts/xcb.sh shut down other booted simulators before each
# `test` (today's xcb never shuts down a simulator it did not boot). The hold also keeps other
# builds off this 16 GB Mac during the drive. While `hold` is in force, xcb
# runs from other sessions wait for the lock, exactly as they wait for a build. A watcher
# process owns the lock; it lets go when cleanup removes the verify lock, or after
# VT_HOLD_MAX seconds (default 1800), whichever comes first. The hold depends on xcb's lock
# format (pid + owner files in $XCB_LOCK_DIR): change Scripts/xcb.sh's lock and this file together.
#
# Purrtine runs the same kind of skill (verify-purrtine, /tmp/verify-purrtine.lock). Its runs
# and ours share the xcb lock and the verify slots; neither waits for the other's verify lock.

set -euo pipefail

LOCK_DIR="${VT_LOCK_DIR:-/tmp/verify-triq.lock}"
REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SLIM_SIM="$REPO_ROOT/Scripts/slim-sim.sh"
SLIM_PROFILE="$REPO_ROOT/Scripts/simslim-profile.json"
LOCK_TIMEOUT="${VT_LOCK_TIMEOUT:-3600}"
STALE_MINUTES="${VT_STALE_MINUTES:-45}"
# Owner decision 2026-10-15: verify runs default to the newest iOS on this Mac (27.0).
DEFAULT_OS="${VT_OS:-27.0}"
DEFAULT_DEVICE="${VT_DEVICE:-iPhone 12}"
BUNDLE_ID="app.berke.can.kizildemir.ttb"
APP_NAME="TTB.app"
EVIDENCE_ROOT="$HOME/verify-evidence/triq"
DEVICE_PREFIX="verify-triq-"
XCB_LOCK_DIR="${XCB_CACHE_ROOT:-$HOME/Library/Caches/xcb}/build.lock"
HOLD_MAX="${VT_HOLD_MAX:-1800}"
APP_CHECK_TOKEN_FILE="${VT_APP_CHECK_TOKEN_FILE:-$HOME/.config/verify-triq/appcheck-debug-token}"

fail() { printf 'vt: error: %s\n' "$*" >&2; exit 1; }
say() { printf 'vt: %s\n' "$*"; }

state() { cat "$LOCK_DIR/$1" 2>/dev/null || true; }
need_run() {
  [[ -d "$LOCK_DIR" ]] || fail "no run in progress (run: vt.sh start)"
  [[ -n "$(state udid)" ]] || fail "lock exists but holds no device; run vt.sh cleanup"
  touch "$LOCK_DIR/heartbeat"
}

device_state() {
  xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
udid = sys.argv[1]
for entries in json.load(sys.stdin)["devices"].values():
    for d in entries:
        if d["udid"] == udid:
            print(d["state"]); sys.exit(0)
print("missing")' "$1"
}

device_exists() { [[ "$(device_state "$1")" != missing ]]; }

# A lock is stale when its device is gone, or nobody touched it for STALE_MINUTES.
lock_is_stale() {
  local udid; udid="$(state udid)"
  if [[ -n "$udid" ]] && ! device_exists "$udid"; then return 0; fi
  if [[ -n "$(find "$LOCK_DIR/heartbeat" -mmin +"$STALE_MINUTES" 2>/dev/null)" ]]; then return 0; fi
  if [[ ! -f "$LOCK_DIR/heartbeat" && -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +2 2>/dev/null)" ]]; then
    return 0
  fi
  return 1
}

remove_stale_lock() {
  local udid name; udid="$(state udid)"; name="$(state device_name)"
  say "removing stale lock: $(state owner)"
  release_hold
  if [[ -n "$udid" && "$name" == "$DEVICE_PREFIX"* ]]; then
    "$SLIM_SIM" release "$udid" || true
  fi
  rm -rf "$LOCK_DIR"
}

acquire_lock() {
  local waited=0
  until mkdir "$LOCK_DIR" 2>/dev/null; do
    if lock_is_stale; then remove_stale_lock; continue; fi
    if (( waited % 60 == 0 )); then
      say "waiting for the verify lock (${waited}s) - held by: $(state owner)"
    fi
    (( waited < LOCK_TIMEOUT )) || fail "gave up on the verify lock after ${LOCK_TIMEOUT}s"
    sleep 15
    waited=$((waited + 15))
  done
  touch "$LOCK_DIR/heartbeat"
}

# Other booted simulators (not this run's device): warn only. The run never shuts down a
# device it did not create (owner decision 2026-10-14).
warn_other_booted() {
  local mine="${1:-}" others
  others="$(xcrun simctl list devices booted 2>/dev/null | grep -E '\(Booted\)' | grep -v -F "${mine:-@@none@@}" || true)"
  if [[ -n "$others" ]]; then
    say "WARN another simulator is booted (this run does not touch it):"
    printf '%s\n' "$others" | sed 's/^ */vt:   /'
  fi
}

hold_alive() {
  local w; w="$(state hold_pid)"
  [[ -n "$w" ]] && kill -0 "$w" 2>/dev/null
}

next_evidence_name() {
  local dir="$1" name="$2" n
  # Every evidence file counts (png, json), run.txt does not, so numbers never repeat.
  n=$(find "$dir" -maxdepth 1 -type f ! -name run.txt | wc -l | tr -d ' ')
  printf '%s/%02d-%s' "$dir" $((n + 1)) "$name"
}

cmd_start() {
  local device="$DEFAULT_DEVICE" lang="en" os="$DEFAULT_OS"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device) device="${2:?}"; shift 2 ;;
      --os) os="${2:?}"; shift 2 ;;
      --lang) lang="${2:?}"; shift 2 ;;
      *) fail "unknown option: $1" ;;
    esac
  done
  [[ "$lang" == en || "$lang" == tr ]] || fail "--lang takes en or tr"
  [[ "$os" =~ ^[0-9]+\.[0-9]+$ ]] || fail "--os takes a version like 27.0 or 26.5"
  local runtime_id="com.apple.CoreSimulator.SimRuntime.iOS-${os/./-}" runtimes
  # Read into a variable first: `simctl | grep -q` under pipefail can fail when grep exits early.
  runtimes="$(xcrun simctl list runtimes)" || fail "simctl list runtimes failed"
  # Match the whole last field: a substring test would accept 8.5 (iOS-8-5 is inside iOS-18-5).
  awk -v id="$runtime_id" '$NF == id { found = 1 } END { exit !found }' <<<"$runtimes" || fail "no iOS $os runtime on this Mac (xcrun simctl list runtimes)"
  acquire_lock
  # Any failure from here on would leave a fresh lock that blocks the next start for
  # STALE_MINUTES; undo the half-made run instead.
  trap 'rc=$?; if [[ $rc -ne 0 ]]; then echo "vt: start failed (exit $rc); cleaning up" >&2; cmd_cleanup >&2; fi' EXIT

  local run_id evidence name udid
  run_id="$(date '+%H%M%S')-$(printf '%04x' $((RANDOM)))"
  evidence="$EVIDENCE_ROOT/$(date '+%Y-%m-%d')-$run_id"
  name="$DEVICE_PREFIX$run_id"
  mkdir -p "$evidence"
  echo "$run_id" > "$LOCK_DIR/run_id"
  echo "$evidence" > "$LOCK_DIR/evidence"
  echo "$name" > "$LOCK_DIR/device_name"
  echo "$lang" > "$LOCK_DIR/lang"
  echo "$os" > "$LOCK_DIR/os"
  printf 'run %s, device %s (%s, iOS %s), lang %s, repo %s, since %s\n' "$run_id" "$name" "$device" "$os" "$lang" \
    "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" "$(date '+%Y-%m-%d %H:%M:%S')" > "$LOCK_DIR/owner"

  warn_other_booted
  # A clone of the pristine slim template: no app, no data, the project's SimSlim profile.
  # It waits for a free verify slot (SLIM_SIM_MAX, default 2, shared with Purrtine).
  # The wait can last up to SLIM_SIM_SLOT_TIMEOUT (3600 s), longer than the stale threshold, so
  # keep this run's heartbeat fresh meanwhile. The loop ends with this shell or the lock.
  touch "$LOCK_DIR/heartbeat"
  ( while kill -0 $$ 2>/dev/null && [[ -d "$LOCK_DIR" ]]; do touch "$LOCK_DIR/heartbeat" 2>/dev/null; sleep 60; done ) \
    </dev/null >/dev/null 2>&1 &
  local clone_beat=$!
  udid="$(SLIM_SIM_DEVICE="$device" SLIM_SIM_OS="$os" "$SLIM_SIM" clone "$name" "$LOCK_DIR")" \
    || { kill "$clone_beat" 2>/dev/null; fail "Scripts/slim-sim.sh clone failed"; }
  kill "$clone_beat" 2>/dev/null || true
  echo "$udid" > "$LOCK_DIR/udid"
  say "cloned $name ($device, iOS $os, slim) $udid"
  xcrun simctl boot "$udid" || fail "simctl boot failed; run vt.sh cleanup"
  xcrun simctl bootstatus "$udid" >/dev/null || fail "device did not finish booting; run vt.sh cleanup"
  # A fresh device copies the Mac's languages (seen 2026-10-14: en-TR, tr-TR), so set the
  # system language of this device explicitly. The app gets no test flag.
  local languages=en-US locale=en_US
  [[ "$lang" == tr ]] && { languages=tr-TR; locale=tr_TR; }
  xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$languages" || fail "could not set the device language"
  xcrun simctl spawn "$udid" defaults write -g AppleLocale -string "$locale" || fail "could not set the device locale"
  xcrun simctl shutdown "$udid" || fail "could not shut down the device for the language reboot"
  xcrun simctl boot "$udid" || fail "simctl boot failed after the language change; run vt.sh cleanup"
  xcrun simctl bootstatus "$udid" >/dev/null || fail "device did not finish booting; run vt.sh cleanup"
  say "device language $languages, locale $locale (rebooted)"
  local slim=ok
  simslim verify "$udid" --profile "$SLIM_PROFILE" >/dev/null 2>&1 || { slim=drift; say "WARN the clone does not match $SLIM_PROFILE (simslim verify $udid)"; }
  {
    echo "run_id=$run_id"; echo "udid=$udid"; echo "device=$device"; echo "os=$os"; echo "lang=$lang"
    echo "slim=$slim profile=$(tr -d ' \n' < "$SLIM_PROFILE")"
    echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "started=$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$evidence/run.txt"
  touch "$LOCK_DIR/heartbeat"
  trap - EXIT
  say "booted. UDID=$udid"
  say "evidence $evidence"
}

cmd_build() {
  need_run
  [[ -f TTB/Secrets.xcconfig ]] \
    || fail "no TTB/Secrets.xcconfig in this checkout: cp TTB/Secrets.xcconfig.template TTB/Secrets.xcconfig (never commit it)"
  local name log out app
  name="$(state device_name)"
  out="$LOCK_DIR/build.out"
  # The build can wait up to an hour for the machine-wide build lock; keep our verify
  # lock fresh meanwhile so no other run declares it stale.
  ( while [[ -d "$LOCK_DIR" ]]; do touch "$LOCK_DIR/heartbeat" 2>/dev/null; sleep 60; done ) &
  local beat=$! status=0
  # A killed parent must not leave the heartbeat loop running.
  trap 'kill "$beat" 2>/dev/null' EXIT
  trap 'kill "$beat" 2>/dev/null; echo "vt: build interrupted" >&2; exit 130' INT
  trap 'kill "$beat" 2>/dev/null; echo "vt: build terminated" >&2; exit 143' TERM
  # Build against this run's own device, so the build never names a shared simulator.
  set +e
  # xcb finds XCB_SIMULATOR by name only on the XCB_OS runtime, so pass the run's OS.
  XCB_SIMULATOR="$name" XCB_OS="$(state os)" Scripts/xcb.sh build 2>&1 | tee "$out"
  status="${PIPESTATUS[0]}"
  set -e
  { kill "$beat"; wait "$beat"; } 2>/dev/null || true
  trap - EXIT INT TERM
  [[ "$status" -eq 0 ]] || fail "build failed (see $out)"
  # xcb prints the first .app it finds, which can be TTBUITests-Runner.app;
  # take the app itself from the same products folder.
  app="$(dirname "$(sed -n 's/^xcb: app //p' "$out")")/$APP_NAME"
  log="$(sed -n 's/^xcb: log //p' "$out")"
  [[ -d "$app" ]] || fail "no $APP_NAME next to the path xcb printed"
  rm -rf "$LOCK_DIR/app"; mkdir -p "$LOCK_DIR/app"
  cp -R "$app" "$LOCK_DIR/app/"
  # DerivedData is shared by every worktree. A build that started after ours could have
  # replaced the .app before the copy; its log would be newer than ours.
  if [[ -n "$(find "$(dirname "$log")" -name '*.log' -newer "$log" 2>/dev/null)" ]]; then
    fail "another TTB build ran after ours; run vt.sh build again"
  fi
  touch "$LOCK_DIR/heartbeat"
  say "app copied to $LOCK_DIR/app/$APP_NAME"
}

cmd_hold() {
  need_run
  if hold_alive; then
    say "already holding the xcb lock (watcher PID $(state hold_pid))"; return 0
  fi
  local waited=0 holder
  until mkdir "$XCB_LOCK_DIR" 2>/dev/null; do
    holder="$(cat "$XCB_LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$XCB_LOCK_DIR"; continue; fi
    if (( waited % 60 == 0 )); then
      say "waiting for the xcb lock (${waited}s) - held by: $(cat "$XCB_LOCK_DIR/owner" 2>/dev/null || echo unknown)"
    fi
    (( waited < LOCK_TIMEOUT )) || fail "gave up on the xcb lock after ${LOCK_TIMEOUT}s"
    touch "$LOCK_DIR/heartbeat"
    sleep 5; waited=$((waited + 5))
  done
  # The watcher outlives this shell; xcb treats a live PID as a live holder.
  nohup /bin/bash -c '
    lock="$1"; xcb="$2"; max="$3"; start=$SECONDS
    while [[ -d "$lock" ]] && (( SECONDS - start < max )); do touch "$lock/heartbeat" 2>/dev/null; sleep 5; done
    [[ "$(cat "$xcb/pid" 2>/dev/null)" == "$$" ]] && rm -rf "$xcb"
  ' vt-hold "$LOCK_DIR" "$XCB_LOCK_DIR" "$HOLD_MAX" >/dev/null 2>&1 &
  local watcher=$!
  echo "$watcher" > "$XCB_LOCK_DIR/pid"
  printf 'TTB verify-triq drive, run %s (PID %s, since %s, max %ss)\n' \
    "$(state run_id)" "$watcher" "$(date '+%H:%M:%S')" "$HOLD_MAX" > "$XCB_LOCK_DIR/owner"
  echo "$watcher" > "$LOCK_DIR/hold_pid"
  say "holding the xcb lock (watcher PID $watcher, max ${HOLD_MAX}s)"
}

release_hold() {
  local watcher; watcher="$(cat "$LOCK_DIR/hold_pid" 2>/dev/null || true)"
  [[ -n "$watcher" ]] || return 0
  if [[ "$(cat "$XCB_LOCK_DIR/pid" 2>/dev/null)" == "$watcher" ]]; then rm -rf "$XCB_LOCK_DIR"; fi
  kill "$watcher" 2>/dev/null || true
  say "xcb lock released"
}

boot_if_needed() {
  local udid; udid="$(state udid)"
  if [[ "$(device_state "$udid")" != Booted ]]; then
    say "device was shut down (another session's xcb.sh test?); booting it again"
    xcrun simctl boot "$udid" || fail "simctl boot failed for $udid"
    xcrun simctl bootstatus "$udid" >/dev/null || fail "device $udid did not finish booting"
    echo "revived=$(date '+%H:%M:%S')" >> "$(state evidence)/run.txt"
  fi
}

cmd_install() {
  need_run
  local app="$LOCK_DIR/app/$APP_NAME"
  [[ -d "$app" ]] || fail "no copied app (run vt.sh build)"
  # Check first: an app launched without the token stores a random one in its place.
  [[ -s "$APP_CHECK_TOKEN_FILE" ]] \
    || fail "no App Check debug token at $APP_CHECK_TOKEN_FILE (see SKILL.md, Live Firebase)"
  boot_if_needed
  xcrun simctl install "$(state udid)" "$app" || fail "simctl install failed"
  say "installed $APP_NAME"
  set_app_check_token
}

# Firestore enforces App Check. A Debug build uses the App Check debug provider, which makes a
# random token per install unless one is stored; Firebase rejects a token nobody registered, so
# every read and write fails with "Missing or insufficient permissions" (seen 2026-10-15).
# The owner registered one fixed debug token in the Firebase console (2026-10-15). It lives
# outside the repo; never commit it or print it. AppCheckCore reads it from the app's
# standard defaults under GACAppCheckDebugToken, so it must be there before the first launch.
set_app_check_token() {
  [[ -s "$APP_CHECK_TOKEN_FILE" ]] \
    || fail "no App Check debug token at $APP_CHECK_TOKEN_FILE (see SKILL.md, Live Firebase)"
  local udid container; udid="$(state udid)"
  container="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)" || fail "no data container for $BUNDLE_ID"
  xcrun simctl spawn "$udid" defaults write "$container/Library/Preferences/$BUNDLE_ID" \
    GACAppCheckDebugToken "$(cat "$APP_CHECK_TOKEN_FILE")" || fail "could not store the App Check debug token"
  say "App Check debug token stored in the app's defaults"
}

app_check_token_ok() {
  local udid container stored; udid="$(state udid)"
  container="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data 2>/dev/null)" || return 1
  stored="$(xcrun simctl spawn "$udid" defaults read "$container/Library/Preferences/$BUNDLE_ID" \
    GACAppCheckDebugToken 2>/dev/null || true)"
  [[ -n "$stored" && "$stored" == "$(cat "$APP_CHECK_TOKEN_FILE" 2>/dev/null)" ]]
}

cmd_launch() {
  need_run
  # No launch arguments, ever: no -ui-test-* harness flag (TTB/App/UITestLaunchOptions.swift).
  xcrun simctl launch "$(state udid)" "$BUNDLE_ID" || fail "simctl launch failed (installed? run vt.sh doctor)"
  wait_for_tree
}

# Ready means usable: axe returns a tree with the app's labelled elements.
wait_for_tree() {
  local i
  for i in $(seq 1 30); do
    if axe describe-ui --udid "$(state udid)" 2>/dev/null | grep -q '"AXLabel" : "[^"]'; then
      say "app is on screen"; return 0
    fi
    sleep 1
  done
  say "WARN no accessibility tree after 30s; run vt.sh doctor"
}

# True when the process uses 90 % CPU or more in 3 samples 1 s apart. One sample is a decayed
# average and can read high just after launch. Never fails under set -e: a dead PID reads as 0.
app_cpu_stays_high() {
  local cpu i
  for i in 1 2 3; do
    cpu="$(ps -o %cpu= -p "$1" 2>/dev/null | tr -d ' ' | cut -d. -f1 || true)"
    [[ "${cpu:-0}" -ge 90 ]] || return 1
    [[ $i == 3 ]] || sleep 1
  done
  return 0
}

cmd_doctor() {
  [[ -d "$LOCK_DIR" ]] || fail "no run in progress"
  local udid ok=0 dstate; udid="$(state udid)"; dstate="$(device_state "$udid")"
  printf 'owner:   %s\n' "$(state owner)"
  printf 'device:  %s %s state=%s\n' "$(state device_name)" "$udid" "$dstate"
  printf 'os:      iOS %s\n' "$(state os)"
  if [[ "$dstate" != Booted ]]; then
    echo "FAIL device is not booted (another session shut it down?): run vt.sh revive"
    ok=1
  fi
  if xcrun simctl get_app_container "$udid" "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "app:     installed"
  else
    echo "FAIL app is not installed"; ok=1
  fi
  local pid
  pid="$(xcrun simctl spawn "$udid" launchctl list 2>/dev/null \
    | awk -v b="UIKitApplication:$BUNDLE_ID" 'index($3, b) == 1 && $1 != "-" {print $1}' | head -1)" || true
  if [[ -n "$pid" ]]; then
    printf 'app pid: %s\n' "$pid"
    ps -o args= -p "$pid" 2>/dev/null | sed 's/^/app cmd: /' || true
    if ps -o args= -p "$pid" 2>/dev/null | grep -qE ' -ui-test'; then
      echo "FAIL the app runs with a -ui-test launch argument"; ok=1
    fi
  else
    echo "WARN app is not running: run vt.sh launch"
  fi
  if simslim verify "$udid" --profile "$SLIM_PROFILE" >/dev/null 2>&1; then
    echo "slim:    matches Scripts/simslim-profile.json"
  else
    echo "WARN slim: the device does not match Scripts/simslim-profile.json (simslim verify $udid)"
  fi
  printf 'lang:    %s (AppleLanguages: %s)\n' "$(state lang)" \
    "$(xcrun simctl spawn "$udid" defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n' || true)"
  # axe waits on a hung app for over a minute (2026-10-21): read the tree for 15 s at most.
  local axout="$LOCK_DIR/doctor-ax.json" axpid i count
  axe describe-ui --udid "$udid" >"$axout" 2>/dev/null &
  axpid=$!
  for i in $(seq 1 30); do kill -0 "$axpid" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "$axpid" 2>/dev/null; then
    kill "$axpid" 2>/dev/null || true
    for i in 1 2 3 4; do kill -0 "$axpid" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$axpid" 2>/dev/null || true
  fi
  wait "$axpid" 2>/dev/null || true
  count="$(grep -c '"AXLabel"' "$axout" 2>/dev/null || true)"
  rm -f "$axout"
  printf 'ax tree: %s labelled elements\n' "${count:-0}"
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
    echo "FAIL the app (PID $pid) exited during doctor: run vt.sh launch, then doctor again"
    ok=1
  elif [[ -n "$pid" && "${count:-0}" -lt 3 ]] && app_cpu_stays_high "$pid"; then
    # A hung app (main thread in a SwiftUI layout loop, 2026-10-21) shows 0-1 elements at 100% CPU.
    echo "FAIL the app is hung (90% CPU or more in 3 samples, ${count:-0} labelled elements): run vt.sh revive"
    ok=1
  elif [[ "${count:-0}" -eq 0 ]]; then
    echo "WARN empty accessibility tree: call xcodebuildmcp open_sim, then retry"
  fi
  local copied="$LOCK_DIR/app/$APP_NAME"
  if [[ -f "$copied/GoogleService-Info.plist" ]]; then
    echo "live:    the app talks to live Firebase (ttbp-9d652); drive only what the feature file's live-data class allows"
  elif [[ -d "$copied" ]]; then
    echo "WARN the copied app has no GoogleService-Info.plist: Firebase cannot start; this is not the real app"
  fi
  if app_check_token_ok; then
    echo "appcheck: the app holds the registered debug token"
  else
    echo "FAIL the app does not hold the registered App Check debug token: Firestore will refuse every read; run vt.sh install again"
    ok=1
  fi
  if [[ -f "$LOCK_DIR/hold_pid" ]]; then
    if hold_alive; then echo "hold:    xcb lock watcher alive (PID $(state hold_pid))"
    else echo "WARN the hold watcher (PID $(state hold_pid)) is not running: other sessions' builds and tests are no longer paused; run vt.sh hold"; fi
  else
    echo "hold:    not taken (run vt.sh hold after build)"
  fi
  warn_other_booted "$udid"
  printf 'evidence: %s\n' "$(state evidence)"
  touch "$LOCK_DIR/heartbeat"
  return "$ok"
}

cmd_revive() {
  need_run
  boot_if_needed
  if xcrun simctl get_app_container "$(state udid)" "$BUNDLE_ID" >/dev/null 2>&1; then
    # A hung app (main thread in a layout loop, seen 2026-10-21) makes simctl launch wait forever.
    xcrun simctl terminate "$(state udid)" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$(state udid)" "$BUNDLE_ID" || fail "simctl launch failed"
    wait_for_tree
    say "app relaunched; its data on the device is kept"
  else
    say "app not installed yet: run vt.sh install, then vt.sh launch"
  fi
}

cmd_shot() {
  need_run
  local path; path="$(next_evidence_name "$(state evidence)" "${1:?shot needs a name}").png"
  xcrun simctl io "$(state udid)" screenshot "$path" >/dev/null 2>&1 || fail "screenshot failed (device booted? run vt.sh doctor)"
  say "screenshot $path"
}

cmd_tree() {
  need_run
  local path; path="$(next_evidence_name "$(state evidence)" "${1:?tree needs a name}").json"
  axe describe-ui --udid "$(state udid)" > "$path" || { rm -f "$path"; fail "axe describe-ui failed"; }
  say "tree $path ($(grep -c '"AXLabel"' "$path" || true) labelled elements)"
}

cmd_ui() {
  need_run
  local json
  json="$(axe describe-ui --udid "$(state udid)" 2>&1)" || fail "axe describe-ui failed: ${json:0:200}"
  printf '%s' "$json" | /usr/bin/python3 -c '
import json, sys
def walk(nodes):
    for n in nodes:
        label, uid, value = n.get("AXLabel"), n.get("AXUniqueId"), n.get("AXValue")
        if label or uid or value:
            f = n.get("frame") or {}
            box = "%d,%d %dx%d" % (f.get("x", 0), f.get("y", 0), f.get("width", 0), f.get("height", 0))
            flag = "" if n.get("enabled", True) else " [disabled]"
            print("%s | %s | %s | %s | %s%s" % (n.get("type"), label or "", uid or "", value or "", box, flag))
        walk(n.get("children") or [])
walk(json.load(sys.stdin))' || fail "could not parse the accessibility tree"
}

# Never fails: under set -e and pipefail a failed axe call here used to end `tap` with no message.
tree_hash() { { axe describe-ui --udid "$(state udid)" 2>/dev/null || echo none; } | shasum | cut -c1-12; }

# Wait up to 8 s for the tree to differ from $1; a slow live call can take longer than one frame.
wait_for_change() {
  local before="$1" i
  for i in 1 2 3 4; do
    sleep 2
    [[ "$(tree_hash)" != "$before" ]] && return 0
  done
  return 1
}

cmd_tap() {
  need_run
  local once=0
  if [[ "${1:-}" == --once ]]; then once=1; shift; fi
  [[ $# -gt 0 ]] || fail "tap needs axe selector args, e.g. --id onboarding-continue-button"
  local udid before
  udid="$(state udid)"
  before="$(tree_hash)"
  axe tap "$@" --tap-style physical --wait-timeout 10 --udid "$udid" >/dev/null || fail "axe tap $* found no element"
  if wait_for_change "$before"; then say "tap $* -> screen changed"; return 0; fi
  if [[ $once == 1 ]]; then
    say "WARN screen unchanged 8 s after tap $* (--once: no second tap); read vt.sh ui"
    return 1
  fi
  # A tap during a transition animation can be lost (seen 2026-10-14 in Purrtine).
  say "screen unchanged 8 s after tap $*; tapping once more"
  axe tap "$@" --tap-style physical --wait-timeout 10 --udid "$udid" >/dev/null || fail "axe tap $* found no element"
  if wait_for_change "$before"; then say "tap $* -> screen changed"; return 0; fi
  say "WARN screen unchanged after two taps on $*; read vt.sh ui"
  return 1
}

cmd_cleanup() {
  [[ -d "$LOCK_DIR" ]] || { say "no run in progress"; return 0; }
  local udid name evidence; udid="$(state udid)"; name="$(state device_name)"; evidence="$(state evidence)"
  if [[ -n "$udid" && "$name" == "$DEVICE_PREFIX"* ]]; then
    device_exists "$udid" && { xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true; }
    # Deletes the clone and frees its verify slot (a slot whose device is gone is freed too).
    "$SLIM_SIM" release "$udid" || say "WARN Scripts/slim-sim.sh release $udid failed; delete it by hand: xcrun simctl delete $udid"
  fi
  release_hold
  [[ -n "$evidence" && -d "$evidence" ]] && echo "finished=$(date '+%Y-%m-%d %H:%M:%S')" >> "$evidence/run.txt"
  rm -rf "$LOCK_DIR"
  say "verify lock released"
  if [[ -n "$evidence" && -d "$evidence" ]]; then
    say "evidence kept: $evidence ($(find "$evidence" -type f | wc -l | tr -d ' ') files)"
  fi
  [[ -d "$EVIDENCE_ROOT" ]] && du -sh "$EVIDENCE_ROOT"
  return 0
}

cmd_status() {
  [[ -d "$LOCK_DIR" ]] || { say "no run in progress"; return 0; }
  local f
  for f in owner run_id udid device_name os lang evidence; do printf '%-12s %s\n' "$f" "$(state "$f")"; done
  if [[ -f "$LOCK_DIR/hold_pid" ]]; then
    printf '%-12s %s (PID %s)\n' hold "$(hold_alive && echo alive || echo NOT-RUNNING)" "$(state hold_pid)"
  else
    printf '%-12s %s\n' hold "not taken"
  fi
}

sub="${1:-}"; shift || true
case "$sub" in
  start) cmd_start "$@" ;;
  build) cmd_build ;;
  hold) cmd_hold ;;
  install) cmd_install ;;
  launch) cmd_launch ;;
  doctor) cmd_doctor ;;
  ui) cmd_ui ;;
  tap) cmd_tap "$@" ;;
  shot) cmd_shot "$@" ;;
  tree) cmd_tree "$@" ;;
  revive) cmd_revive ;;
  cleanup) cmd_cleanup ;;
  status) cmd_status ;;
  *) sed -n '2,/^$/p' "$0"; exit 2 ;;
esac
