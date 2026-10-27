#!/usr/bin/env bash
# slim-sim.sh - this project's SimSlim simulators (iPhone 12, iOS 27.0 by default).
#
# SLIM_SIM_VERSION=2
#
# TWO COPIES: the same file ships in TTB and CatCareCalendar (Scripts/slim-sim.sh). Change both
# copies together, keep them byte-identical (cmp), and raise SLIM_SIM_VERSION below on any change
# to the slot format or the stale rules: each slot records the version that made it, and a copy
# never reaps a slot made by a newer version. The project-specific part is Scripts/simslim-profile.json: its "name" names the devices, and its
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
# mkdir in $SLIM_SIM_ROOT/slots; it records the clone's name and UDID, the run's lock directory,
# the PID of the `clone` process and the script version. While the clone is being made (no UDID
# yet), the slot is live as long as that PID is alive. After that, a slot whose device is gone,
# or whose run lock directory is gone or has a heartbeat file older than 45 minutes, is stale:
# the next `clone` deletes that verify-* device (by UDID, or by name when no UDID was recorded)
# and reuses the slot. `clone` also deletes orphan verify-* devices that no slot and no
# /tmp/verify-*.lock names, once they are shut down and over 10 minutes old.
# SLIM_SIM_DEVICE and SLIM_SIM_OS pick another template (made on first use, about a minute).
#
# This script only creates, slims, clones and deletes devices it names itself. It never shuts
# down or deletes any other simulator.

set -euo pipefail

SLIM_SIM_VERSION=2

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
  Scripts/slim-sim.sh sweep                    free stale slots, delete orphan verify-* devices
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

# One `simctl list` per poll: SNAP holds a line per device, "udid<TAB>state<TAB>runtime<TAB>name".
# Call refresh in the shell that reads SNAP, after anything that creates or deletes a device.
SNAP=""
refresh() {
  SNAP="$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
for runtime, entries in json.load(sys.stdin)["devices"].items():
    for d in entries:
        print("\t".join((d["udid"], d["state"], runtime, d["name"])))')" \
    || { say "WARN xcrun simctl list devices failed"; return 1; }
}

# UDID of the device with this exact name on the template's runtime; empty when none.
find_udid() {
  awk -F'\t' -v n="$1" -v r="$RUNTIME_ID" '$3 == r && $4 == n { print $1; exit }' <<<"$SNAP"
}

# UDIDs of every device with this exact name, on any runtime.
udids_named() {
  awk -F'\t' -v n="$1" '$4 == n { print $1 }' <<<"$SNAP"
}

# Name of the device with this UDID on any runtime; empty when it does not exist.
device_name() {
  awk -F'\t' -v u="$1" '$1 == u { print $4; exit }' <<<"$SNAP"
}

device_state() {
  awk -F'\t' -v u="$1" '$1 == u { print $2; f = 1; exit } END { if (!f) print "missing" }' <<<"$SNAP"
}

# PID of the calling shell, also in a subshell: call it as "$(my_pid)". Bash 3.2 has no BASHPID,
# and $$ is always the top shell. The $(...) subshell execs sh, so sh's parent is the caller.
my_pid() { exec /bin/sh -c 'echo "$PPID"'; }

# Serialises template setup, test-device setup and verify clones per project: two runs may both
# find a device missing, and a clone must not read the template while it is being re-slimmed.
# The body runs in a subshell whose EXIT trap removes the lock, so a `fail` inside it (also
# inside $(...)) never leaves the lock behind; the lock records that subshell's own PID.
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
  (
    # Expanded now: at exit, `lock` (a local) is out of scope.
    trap "rm -rf $(printf %q "$lock")" EXIT
    echo "$(my_pid)" > "$lock/pid"
    "$@"
  )
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
  refresh
  udid="$(find_udid "$TEMPLATE_NAME")"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "$TEMPLATE_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")" || fail "simctl create failed"
    say "created the template $TEMPLATE_NAME ($udid)"
    refresh
    slim_device "$udid"
  elif [[ "$(recorded_sha "$udid")" != "$PROFILE_SHA" ]]; then
    say "the profile changed since the template was slimmed"
    slim_device "$udid"
  fi
  # A pristine template is shut down; a booted one was used by hand.
  refresh
  [[ "$(device_state "$udid")" == Shutdown ]] || say "WARN the template $udid is not shut down; do not boot it"
  echo "$udid"
}

ensure_test_locked() {
  local template udid
  template="$(ensure_template_locked)"
  refresh
  udid="$(find_udid "$TEST_NAME")"
  if [[ -z "$udid" ]]; then
    clone_device "$template" "$TEST_NAME" >/dev/null
    refresh
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

# Version of the copy that made a slot; 1 for a slot from before versions.
slot_version() {
  local v; v="$(cat "$1/version" 2>/dev/null || true)"
  [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo 1
}

# A slot made by a newer copy of this script follows rules this copy may not know: never reap it.
newer_slot_exists() {
  local slot
  for slot in "$SLOTS"/*; do
    [[ -d "$slot" ]] || continue
    (( $(slot_version "$slot") > SLIM_SIM_VERSION )) && return 0
  done
  return 1
}

# Uses SNAP; refresh first. A slot is stale when:
#   - it holds no UDID yet (the clone is being made) and the `clone` process that took it is
#     dead; with no PID recorded (older copies), when it is over 10 minutes old;
#   - or its clone is gone, or its run's lock directory is gone, or that directory's heartbeat
#     file is older than SLIM_SIM_STALE_MINUTES.
slot_is_stale() {
  local slot="$1" udid owner pid
  (( $(slot_version "$slot") <= SLIM_SIM_VERSION )) || return 1
  udid="$(cat "$slot/udid" 2>/dev/null || true)"
  owner="$(cat "$slot/owner" 2>/dev/null || true)"
  if [[ -z "$udid" ]]; then
    pid="$(cat "$slot/pid" 2>/dev/null || true)"
    if [[ -n "$pid" ]]; then
      ! kill -0 "$pid" 2>/dev/null; return
    fi
    [[ -n "$(find "$slot" -maxdepth 0 -mmin +10 2>/dev/null)" ]]; return
  fi
  [[ "$(device_state "$udid")" == missing ]] && return 0
  [[ -n "$owner" && ! -d "$owner" ]] && return 0
  # A run that crashed keeps its lock directory; its heartbeat file stops changing.
  [[ -n "$owner" && -n "$(find "$owner/heartbeat" -mmin +"$STALE_MINUTES" 2>/dev/null)" ]] && return 0
  return 1
}

delete_verify_device() {
  local udid="$1" name="$2"
  [[ "$name" == verify-* ]] || return 0
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  if xcrun simctl delete "$udid"; then say "deleted $name ($udid)"; else say "WARN could not delete $name ($udid)"; fi
}

# Deletes the slot's clone, by UDID, or by its recorded name when the clone never got as far
# as a UDID (a failed `simslim clone` or lookup), then frees the slot.
free_slot() {
  local slot="$1" udid name u
  udid="$(cat "$slot/udid" 2>/dev/null || true)"
  name="$(cat "$slot/name" 2>/dev/null || true)"
  refresh || true
  if [[ -n "$udid" ]]; then
    delete_verify_device "$udid" "$(device_name "$udid")"
  elif [[ "$name" == verify-* ]]; then
    for u in $(udids_named "$name"); do delete_verify_device "$u" "$name"; done
  fi
  rm -rf "$slot"
}

# Uses SNAP; refresh first. Deletes verify-* devices that no slot and no verify run lock
# (/tmp/verify-*.lock/udid, also from older checkouts that make devices without a slot) names,
# and that are shut down and were made over 10 minutes ago. A half-made clone from a failed run
# ends up here. Skipped while a newer copy of this script holds a slot.
sweep_orphans() {
  newer_slot_exists && return 0
  local known udid state name born now
  known="$(cat "$SLOTS"/*/udid "$SLOTS"/*/name /tmp/verify-*.lock/udid /tmp/verify-*.lock/device_name 2>/dev/null || true)"
  now="$(date +%s)"
  while IFS=$'\t' read -r udid state _ name; do
    [[ "$name" == verify-* && "$state" == Shutdown ]] || continue
    grep -qxF -e "$udid" -e "$name" <<<"$known" && continue
    born="$(stat -f %B "$HOME/Library/Developer/CoreSimulator/Devices/$udid" 2>/dev/null || echo "$now")"
    (( now - born > 600 )) || continue
    say "deleting orphan $name ($udid): no slot or verify run owns it"
    delete_verify_device "$udid" "$name"
  done <<<"$SNAP"
}

take_slot() {
  local owner="$1" waited=0 i slot
  mkdir -p "$SLOTS"
  while :; do
    for i in $(seq 1 "$MAX"); do
      slot="$SLOTS/$i"
      if mkdir "$slot" 2>/dev/null; then
        echo "$$" > "$slot/pid"
        echo "$SLIM_SIM_VERSION" > "$slot/version"
        echo "$owner" > "$slot/owner"
        echo "$slot"; return 0
      fi
    done
    local freed=0
    refresh
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

# Runs under the setup lock, so the template cannot be re-slimmed while it is cloned.
clone_locked() {
  local name="$1" template udid
  template="$(ensure_template_locked)"
  clone_device "$template" "$name"
  refresh
  udid="$(find_udid "$name")"
  [[ -n "$udid" ]] || fail "simslim clone made no $name"
  echo "$udid"
}

cmd_clone() {
  local name="${1:?clone needs a NAME}" owner="${2:?clone needs the run lock directory}" slot udid
  [[ "$name" == verify-* ]] || fail "a verify clone's name starts with verify- (got $name)"
  refresh
  [[ -z "$(udids_named "$name")" ]] || fail "a device named $name exists already"
  sweep_orphans
  slot="$(take_slot "$owner")"
  # The name goes in first, so a failure below can still find and delete a half-made device.
  echo "$name" > "$slot/name"
  # Any failure below deletes the half-made device and frees the slot again.
  trap 'rc=$?; if [[ $rc -ne 0 ]]; then free_slot "'"$slot"'"; fi' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  udid="$(with_setup_lock clone_locked "$name")"
  echo "$udid" > "$slot/udid"
  trap - EXIT INT TERM
  say "slot $(basename "$slot"): $name ($udid), cloned from $TEMPLATE_NAME"
  echo "$udid"
}

cmd_release() {
  local udid="${1:?release needs a UDID}" slot name found=0
  refresh
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

cmd_sweep() {
  local slot
  mkdir -p "$SLOTS"
  refresh
  for slot in "$SLOTS"/*; do
    [[ -d "$slot" ]] || continue
    if slot_is_stale "$slot"; then
      say "freeing stale slot $(basename "$slot") ($(cat "$slot/name" 2>/dev/null || echo half-made))"
      free_slot "$slot"
    fi
  done
  refresh
  sweep_orphans
}

cmd_slots() {
  local slot n=0
  refresh
  printf 'max %s (SLIM_SIM_MAX), slots in %s\n' "$MAX" "$SLOTS"
  for slot in "$SLOTS"/*; do
    [[ -d "$slot" ]] || continue
    n=$((n + 1))
    printf '  slot %s: %s %s state=%s owner=%s v%s\n' "$(basename "$slot")" "$(cat "$slot/name" 2>/dev/null || echo '?')" \
      "$(cat "$slot/udid" 2>/dev/null || echo '-')" \
      "$([[ -f "$slot/udid" ]] && device_state "$(cat "$slot/udid")" || echo cloning)" \
      "$(cat "$slot/owner" 2>/dev/null || echo '?')" "$(slot_version "$slot")"
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
  sweep) cmd_sweep ;;
  names) printf 'template %s\ntest     %s\n' "$TEMPLATE_NAME" "$TEST_NAME" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
