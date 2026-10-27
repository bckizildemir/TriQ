#!/usr/bin/env bash
# slim-sim.sh - this project's SimSlim simulators (iPhone 12, iOS 27.0 by default).
#
# The same file ships in TTB and CatCareCalendar. Keep both copies identical. The
# project-specific part is Scripts/simslim-profile.json: its "name" names the devices, and its
# "except"/"keep" arrays are the SimSlim profile (`simslim on --profile`).
#
# Three kinds of device per project:
#   - TEMPLATE  "iPhone 12 slim tmpl (<name>)": slimmed with the profile, kept shut down, never
#               booted by hand, never given an app. Only `simslim clone` reads it.
#   - TEST      "iPhone 12 slim test (<name>)": a persistent clone of the template that
#               Scripts/xcb.sh builds and tests on. Its app and data change from run to run.
#   - VERIFY    "verify-<app>-<run-id>": a clone per verify run, made by `clone`, deleted by
#               `release`. A brand-new user: no app, no data, the project's slim profile.
#
# Verify clones take a slot first. The slots are machine-wide (both projects share them), so at
# most SLIM_SIM_MAX verify clones exist at once (default 2). A slot is a directory made with
# mkdir in $SLIM_SIM_ROOT/slots; it records the clone's UDID and the run's lock directory. A slot
# whose device is gone, or whose run lock directory is gone or has a heartbeat file older than
# 45 minutes, is stale: the next `clone` deletes that verify-* device and reuses the slot.
# SLIM_SIM_DEVICE and SLIM_SIM_OS pick another template (made on first use, about a minute).
#
# This script only creates, slims, clones and deletes devices it names itself. It never shuts
# down or deletes any other simulator.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage (from any folder of the repo):
  Scripts/slim-sim.sh template                 make or repair the template; print its UDID
  Scripts/slim-sim.sh test-sim                 make or repair the test device; print its UDID
  Scripts/slim-sim.sh clone NAME OWNER-DIR     take a slot, clone the template as NAME, print the
                                               UDID (shut down). NAME must start with verify-.
                                               OWNER-DIR is the run's lock directory: when it is
                                               gone, the slot is stale.
  Scripts/slim-sim.sh release UDID             shut down and delete a verify-* clone, free its slot
  Scripts/slim-sim.sh slots                    show the verify slots
  Scripts/slim-sim.sh names                    print the template and test device names

Environment:
  SLIM_SIM_MAX           Verify clones at once, machine-wide (default 2)
  SLIM_SIM_SLOT_TIMEOUT  Seconds to wait for a slot (default 3600)
  SLIM_SIM_STALE_MINUTES A slot whose run heartbeat is older than this is stale (default 45)
  SLIM_SIM_ROOT          State folder (default ~/Library/Caches/slim-sim)
  SLIM_SIM_DEVICE        Device type of the template (default "iPhone 12")
  SLIM_SIM_OS            iOS version of the template (default 27.0)
EOF
}

fail() { printf 'slim-sim: error: %s\n' "$*" >&2; exit 1; }
say() { printf 'slim-sim: %s\n' "$*" >&2; }

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
PROFILE="$REPO_ROOT/Scripts/simslim-profile.json"
ROOT="${SLIM_SIM_ROOT:-$HOME/Library/Caches/slim-sim}"
SLOTS="$ROOT/slots"
MAX="${SLIM_SIM_MAX:-2}"
SLOT_TIMEOUT="${SLIM_SIM_SLOT_TIMEOUT:-3600}"
STALE_MINUTES="${SLIM_SIM_STALE_MINUTES:-45}"
DEVICE_TYPE="${SLIM_SIM_DEVICE:-iPhone 12}"
OS_VERSION="${SLIM_SIM_OS:-27.0}"
RUNTIME_ID="com.apple.CoreSimulator.SimRuntime.iOS-${OS_VERSION//./-}"

[[ "$MAX" =~ ^[1-9][0-9]*$ ]] || fail "SLIM_SIM_MAX must be a positive number"
[[ -f "$PROFILE" ]] || fail "no $PROFILE"
command -v simslim >/dev/null 2>&1 || fail "simslim is not installed (brew install simslim)"
LABEL="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$PROFILE")" \
  || fail "$PROFILE has no \"name\""
TEMPLATE_NAME="$DEVICE_TYPE slim tmpl ($LABEL)"
TEST_NAME="$DEVICE_TYPE slim test ($LABEL)"
PROFILE_SHA="$(shasum "$PROFILE" | cut -c1-12)"

# UDID of the device with this exact name on the template's runtime; empty when none.
find_udid() {
  xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for d in json.load(sys.stdin)["devices"].get(runtime, []):
    if d["name"] == name:
        print(d["udid"]); break' "$1" "$RUNTIME_ID"
}

# Name of the device with this UDID on any runtime; empty when it does not exist.
device_name() {
  xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
for entries in json.load(sys.stdin)["devices"].values():
    for d in entries:
        if d["udid"] == sys.argv[1]:
            print(d["name"]); sys.exit(0)' "$1"
}

device_state() {
  xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
for entries in json.load(sys.stdin)["devices"].values():
    for d in entries:
        if d["udid"] == sys.argv[1]:
            print(d["state"]); sys.exit(0)
print("missing")' "$1"
}

# Serialises template and test-device setup per project (two runs may both find them missing).
with_setup_lock() {
  local lock="$ROOT/setup-$LABEL.lock" waited=0 holder
  mkdir -p "$ROOT"
  until mkdir "$lock" 2>/dev/null; do
    holder="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$lock"; continue; fi
    if [[ -z "$holder" && -n "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]]; then rm -rf "$lock"; continue; fi
    (( waited < 900 )) || fail "gave up on $lock after 900s"
    sleep 3; waited=$((waited + 3))
  done
  echo "$$" > "$lock/pid"
  local status=0
  "$@" || status=$?
  rm -rf "$lock"
  return "$status"
}

# The profile a device was last slimmed with, so a changed profile re-slims it.
recorded_sha() { cat "$ROOT/profiles/$1" 2>/dev/null || true; }
record_sha() { mkdir -p "$ROOT/profiles"; echo "$PROFILE_SHA" > "$ROOT/profiles/$1"; }

slim_device() {
  local udid="$1"
  say "slimming $(device_name "$udid") ($udid) with $PROFILE (about 30 s)"
  simslim on "$udid" --profile "$PROFILE" --preserve-boot-state >&2 || fail "simslim on failed for $udid"
  record_sha "$udid"
}

ensure_template_locked() {
  local runtimes udid
  runtimes="$(xcrun simctl list runtimes)"
  awk -v id="$RUNTIME_ID" '$NF == id { f = 1 } END { exit !f }' <<<"$runtimes" \
    || fail "no iOS $OS_VERSION simulator runtime on this Mac"
  udid="$(find_udid "$TEMPLATE_NAME")"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "$TEMPLATE_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")" || fail "simctl create failed"
    say "created the template $TEMPLATE_NAME ($udid)"
    slim_device "$udid"
  elif [[ "$(recorded_sha "$udid")" != "$PROFILE_SHA" ]]; then
    say "the profile changed since the template was slimmed"
    slim_device "$udid"
  fi
  # A pristine template is shut down; a booted one was used by hand.
  [[ "$(device_state "$udid")" == Shutdown ]] || say "WARN the template $udid is not shut down; do not boot it"
  echo "$udid"
}

ensure_test_locked() {
  local template udid
  template="$(ensure_template_locked)"
  udid="$(find_udid "$TEST_NAME")"
  if [[ -z "$udid" ]]; then
    clone_device "$template" "$TEST_NAME" >/dev/null
    udid="$(find_udid "$TEST_NAME")"
    [[ -n "$udid" ]] || fail "simslim clone made no $TEST_NAME"
    record_sha "$udid"
    say "created the test device $TEST_NAME ($udid)"
  elif [[ "$(recorded_sha "$udid")" != "$PROFILE_SHA" ]]; then
    say "the profile changed since the test device was slimmed"
    slim_device "$udid"
  fi
  echo "$udid"
}

clone_device() {
  local source="$1" name="$2"
  simslim clone "$source" "$name" >&2 || fail "simslim clone $source \"$name\" failed"
}

# A slot is stale when its clone is gone, or its run's lock directory is gone, or that
# directory's heartbeat file is older than SLIM_SIM_STALE_MINUTES, or it is a half-made slot
# (no UDID) older than 10 minutes.
slot_is_stale() {
  local slot="$1" udid owner
  udid="$(cat "$slot/udid" 2>/dev/null || true)"
  owner="$(cat "$slot/owner" 2>/dev/null || true)"
  if [[ -z "$udid" ]]; then
    [[ -n "$(find "$slot" -maxdepth 0 -mmin +10 2>/dev/null)" ]]; return
  fi
  [[ "$(device_state "$udid")" == missing ]] && return 0
  [[ -n "$owner" && ! -d "$owner" ]] && return 0
  # A run that crashed keeps its lock directory; its heartbeat file stops changing.
  [[ -n "$owner" && -n "$(find "$owner/heartbeat" -mmin +"$STALE_MINUTES" 2>/dev/null)" ]] && return 0
  return 1
}

free_slot() {
  local slot="$1" udid name
  udid="$(cat "$slot/udid" 2>/dev/null || true)"
  if [[ -n "$udid" ]]; then
    name="$(device_name "$udid")"
    if [[ "$name" == verify-* ]]; then
      xcrun simctl shutdown "$udid" 2>/dev/null || true
      xcrun simctl delete "$udid" || say "WARN could not delete $name ($udid)"
      say "deleted $name ($udid)"
    fi
  fi
  rm -rf "$slot"
}

take_slot() {
  local owner="$1" waited=0 i slot
  mkdir -p "$SLOTS"
  while :; do
    for i in $(seq 1 "$MAX"); do
      slot="$SLOTS/$i"
      if mkdir "$slot" 2>/dev/null; then
        echo "$owner" > "$slot/owner"
        echo "$slot"; return 0
      fi
    done
    local freed=0
    for slot in "$SLOTS"/*; do
      [[ -d "$slot" ]] || continue
      if slot_is_stale "$slot"; then
        say "freeing stale slot $(basename "$slot") ($(cat "$slot/name" 2>/dev/null || echo half-made))"
        free_slot "$slot"; freed=1
      fi
    done
    [[ $freed == 1 ]] && continue
    if (( waited % 60 == 0 )); then
      say "all $MAX verify slots are busy (${waited}s); waiting. $(cmd_slots 2>&1 | tr '\n' ';')"
    fi
    (( waited < SLOT_TIMEOUT )) || fail "gave up waiting for a verify slot after ${SLOT_TIMEOUT}s"
    sleep 10; waited=$((waited + 10))
    # Slots above a lowered SLIM_SIM_MAX stay busy until their runs end.
  done
}

cmd_clone() {
  local name="${1:?clone needs a NAME}" owner="${2:?clone needs the run lock directory}" slot template udid
  [[ "$name" == verify-* ]] || fail "a verify clone's name starts with verify- (got $name)"
  [[ -z "$(find_udid "$name")" ]] || fail "a device named $name exists already"
  slot="$(take_slot "$owner")"
  echo "$name" > "$slot/name"
  # Any failure below frees the slot again.
  trap 'rc=$?; if [[ $rc -ne 0 ]]; then free_slot "'"$slot"'"; fi' EXIT
  template="$(with_setup_lock ensure_template_locked)"
  clone_device "$template" "$name"
  udid="$(find_udid "$name")"
  [[ -n "$udid" ]] || fail "simslim clone made no $name"
  echo "$udid" > "$slot/udid"
  trap - EXIT
  say "slot $(basename "$slot"): $name ($udid), cloned from $TEMPLATE_NAME"
  echo "$udid"
}

cmd_release() {
  local udid="${1:?release needs a UDID}" slot name found=0
  for slot in "$SLOTS"/*; do
    [[ -d "$slot" && "$(cat "$slot/udid" 2>/dev/null)" == "$udid" ]] || continue
    free_slot "$slot"; found=1
  done
  if [[ $found == 0 ]]; then
    name="$(device_name "$udid")"
    if [[ "$name" == verify-* ]]; then
      xcrun simctl shutdown "$udid" 2>/dev/null || true
      xcrun simctl delete "$udid" || fail "could not delete $name ($udid)"
      say "deleted $name ($udid) (it held no slot)"
    elif [[ -n "$name" ]]; then
      fail "$name ($udid) is not a verify clone; not touched"
    fi
  fi
}

cmd_slots() {
  local slot n=0
  printf 'max %s (SLIM_SIM_MAX), slots in %s\n' "$MAX" "$SLOTS"
  for slot in "$SLOTS"/*; do
    [[ -d "$slot" ]] || continue
    n=$((n + 1))
    printf '  slot %s: %s %s state=%s owner=%s\n' "$(basename "$slot")" "$(cat "$slot/name" 2>/dev/null || echo '?')" \
      "$(cat "$slot/udid" 2>/dev/null || echo '-')" "$(device_state "$(cat "$slot/udid" 2>/dev/null || echo none)")" \
      "$(cat "$slot/owner" 2>/dev/null || echo '?')"
  done
  (( n > 0 )) || printf '  (none in use)\n'
}

sub="${1:-}"; shift || true
case "$sub" in
  template) with_setup_lock ensure_template_locked ;;
  test-sim) with_setup_lock ensure_test_locked ;;
  clone) cmd_clone "$@" ;;
  release) cmd_release "$@" ;;
  slots) cmd_slots ;;
  names) printf 'template %s\ntest     %s\n' "$TEMPLATE_NAME" "$TEST_NAME" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
