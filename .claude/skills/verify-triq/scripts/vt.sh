#!/usr/bin/env bash
# vt.sh - one verify-triq run: a fresh simulator, the real TriQ app, evidence that survives.
#
# Subcommands (run from the repo root, in this order):
#   start [--device NAME] [--lang en|tr]  take the verify lock, create + boot a fresh device
#   build                                 Scripts/xcb.sh build against that device, copy TTB.app
#   hold                                  take the machine-wide xcb lock for the drive (see below)
#   install                               install the copied .app on the device
#   launch                                launch the app with NO launch arguments
#   doctor                                read-only: is this run worth driving?
#   ui                                    compact tree: type | label | id | value | frame
#   tap AXE-TAP-ARGS...                   axe tap (physical style), retried once if the screen did not change
#   shot NAME                             screenshot -> evidence/NN-NAME.png
#   tree NAME                             accessibility tree -> evidence/NN-NAME.json
#   revive                                boot the device again after another session shut it down
#   cleanup                               delete the device, drop the locks, keep the evidence
#   status                                print the run state
#
# State lives in the lock directory, so every Bash call (a new shell) finds the same run.
#
# Why hold: Scripts/xcb.sh shuts down other booted simulators before each `test`, so
# another session's test can kill this run's device mid-drive. While `hold` is in force, xcb
# runs from other sessions wait for the lock, exactly as they wait for a build. A watcher
# process owns the lock; it lets go when cleanup removes the verify lock, or after
# VT_HOLD_MAX seconds (default 1800), whichever comes first. The hold depends on xcb's lock
# format (pid + owner files in $XCB_LOCK_DIR): change Scripts/xcb.sh's lock and this file together.
#
# Purrtine runs the same kind of skill (verify-purrtine, /tmp/verify-purrtine.lock). Its runs
# and ours share the xcb lock and this Mac's memory, so `start` waits while one is in progress.

set -euo pipefail

LOCK_DIR="${VT_LOCK_DIR:-/tmp/verify-triq.lock}"
PURRTINE_LOCK_DIR="/tmp/verify-purrtine.lock"
LOCK_TIMEOUT="${VT_LOCK_TIMEOUT:-3600}"
STALE_MINUTES="${VT_STALE_MINUTES:-45}"
RUNTIME_ID="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
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
  if [[ -n "$udid" && "$name" == "$DEVICE_PREFIX"* ]] && device_exists "$udid"; then
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    xcrun simctl delete "$udid" || true
  fi
  rm -rf "$LOCK_DIR"
}

# A Purrtine verify run is in progress: its lock exists or one of its devices is booted.
purrtine_busy() {
  [[ -d "$PURRTINE_LOCK_DIR" ]] && return 0
  xcrun simctl list devices booted 2>/dev/null | grep -q 'verify-purrtine-'
}

acquire_lock() {
  local waited=0
  while purrtine_busy; do
    if (( waited % 60 == 0 )); then
      say "waiting for the Purrtine verify run to end (${waited}s) - $(cat "$PURRTINE_LOCK_DIR/owner" 2>/dev/null || echo 'a verify-purrtine device is booted')"
    fi
    (( waited < LOCK_TIMEOUT )) || fail "gave up waiting for the Purrtine verify run after ${LOCK_TIMEOUT}s"
    sleep 15
    waited=$((waited + 15))
  done
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
  local device="$DEFAULT_DEVICE" lang="en"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device) device="${2:?}"; shift 2 ;;
      --lang) lang="${2:?}"; shift 2 ;;
      *) fail "unknown option: $1" ;;
    esac
  done
  [[ "$lang" == en || "$lang" == tr ]] || fail "--lang takes en or tr"
  acquire_lock

  local run_id evidence name udid
  run_id="$(date '+%H%M%S')-$(printf '%04x' $((RANDOM)))"
  evidence="$EVIDENCE_ROOT/$(date '+%Y-%m-%d')-$run_id"
  name="$DEVICE_PREFIX$run_id"
  mkdir -p "$evidence"
  echo "$run_id" > "$LOCK_DIR/run_id"
  echo "$evidence" > "$LOCK_DIR/evidence"
  echo "$name" > "$LOCK_DIR/device_name"
  echo "$lang" > "$LOCK_DIR/lang"
  printf 'run %s, device %s (%s), lang %s, repo %s, since %s\n' "$run_id" "$name" "$device" "$lang" \
    "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" "$(date '+%Y-%m-%d %H:%M:%S')" > "$LOCK_DIR/owner"

  warn_other_booted
  udid="$(xcrun simctl create "$name" "$device" "$RUNTIME_ID")" || fail "simctl create failed"
  echo "$udid" > "$LOCK_DIR/udid"
  say "created $name ($device, iOS 26.5) $udid"
  xcrun simctl boot "$udid" || fail "simctl boot failed; run vt.sh cleanup"
  xcrun simctl bootstatus "$udid" >/dev/null || fail "device did not finish booting; run vt.sh cleanup"
  # A fresh device copies the Mac's languages (seen 2026-10-14: en-TR, tr-TR), so set the
  # system language of this device explicitly. The app gets no test flag.
  local languages=en-US locale=en_US
  [[ "$lang" == tr ]] && { languages=tr-TR; locale=tr_TR; }
  xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$languages"
  xcrun simctl spawn "$udid" defaults write -g AppleLocale -string "$locale"
  xcrun simctl shutdown "$udid"
  xcrun simctl boot "$udid" || fail "simctl boot failed after the language change; run vt.sh cleanup"
  xcrun simctl bootstatus "$udid" >/dev/null || fail "device did not finish booting; run vt.sh cleanup"
  say "device language $languages, locale $locale (rebooted)"
  {
    echo "run_id=$run_id"; echo "udid=$udid"; echo "device=$device"; echo "lang=$lang"
    echo "git_rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "started=$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$evidence/run.txt"
  touch "$LOCK_DIR/heartbeat"
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
  XCB_SIMULATOR="$name" Scripts/xcb.sh build 2>&1 | tee "$out"
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

cmd_doctor() {
  [[ -d "$LOCK_DIR" ]] || fail "no run in progress"
  local udid ok=0 dstate; udid="$(state udid)"; dstate="$(device_state "$udid")"
  printf 'owner:   %s\n' "$(state owner)"
  printf 'device:  %s %s state=%s\n' "$(state device_name)" "$udid" "$dstate"
  if [[ "$dstate" != Booted ]]; then
    echo "FAIL device is not booted (an xcb.sh test in another session shuts down other simulators): run vt.sh revive"
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
  printf 'lang:    %s (AppleLanguages: %s)\n' "$(state lang)" \
    "$(xcrun simctl spawn "$udid" defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n' || true)"
  local count; count="$(axe describe-ui --udid "$udid" 2>/dev/null | grep -c '"AXLabel"' || true)"
  printf 'ax tree: %s labelled elements\n' "${count:-0}"
  [[ "${count:-0}" -gt 0 ]] || echo "WARN empty accessibility tree: call xcodebuildmcp open_sim, then retry"
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

tree_hash() { axe describe-ui --udid "$(state udid)" 2>/dev/null | shasum | cut -c1-12; }

cmd_tap() {
  need_run
  [[ $# -gt 0 ]] || fail "tap needs axe selector args, e.g. --id mainTab.home"
  local udid before after try
  udid="$(state udid)"
  before="$(tree_hash)"
  for try in 1 2; do
    axe tap "$@" --tap-style physical --wait-timeout 10 --udid "$udid" >/dev/null || fail "axe tap $* found no element"
    sleep 2
    after="$(tree_hash)"
    if [[ "$after" != "$before" ]]; then say "tap $* -> screen changed"; return 0; fi
    # A tap during a transition animation can be lost (seen 2026-10-14 in Purrtine).
    [[ $try == 1 ]] && say "screen unchanged after tap $*; tapping once more"
  done
  say "WARN screen unchanged after two taps on $*; read vt.sh ui"
  return 1
}

cmd_cleanup() {
  [[ -d "$LOCK_DIR" ]] || { say "no run in progress"; return 0; }
  local udid name evidence; udid="$(state udid)"; name="$(state device_name)"; evidence="$(state evidence)"
  if [[ -n "$udid" && "$name" == "$DEVICE_PREFIX"* ]] && device_exists "$udid"; then
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    if xcrun simctl delete "$udid"; then say "deleted $name ($udid)"
    else say "WARN simctl delete failed for $udid; delete it by hand: xcrun simctl delete $udid"; fi
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
  for f in owner run_id udid device_name lang evidence; do printf '%-12s %s\n' "$f" "$(state "$f")"; done
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
  *) sed -n '2,30p' "$0"; exit 2 ;;
esac
