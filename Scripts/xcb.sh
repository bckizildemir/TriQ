#!/usr/bin/env bash
# xcb.sh - build and test on this Mac without starving it.
#
# The same file ships in TTB and CatCareCalendar. Keep both copies identical.
#
# Why it exists (16GB machine, several agents working in parallel):
#   - One machine-wide lock. Builds from every repo and worktree run one at a time;
#     the rest wait. Writing code stays parallel; only xcodebuild queues.
#   - One DerivedData and one package checkout per project, outside iCloud and shared
#     by every worktree, so Firebase compiles once instead of once per worktree.
#   - Capped compile jobs, no parallel test clones, no indexing, lowered priority.
#   - Its own simulator: by default this project's slim test device, "iPhone 12 slim test
#     (<name>)", which Scripts/slim-sim.sh makes from the project's SimSlim template. xcb never
#     shuts down a simulator it did not boot; a test that booted the test device shuts it down
#     again at the end.
#   - The full log goes to a file; the terminal gets errors, failures, and the tail.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Scripts/xcb.sh build [options] [-- extra xcodebuild args]
  Scripts/xcb.sh test  [options] [-- extra xcodebuild args]

Options:
  --os VERSION        Simulator iOS version (default: $XCB_OS or 27.0)
  --only IDENTIFIER   Passed as -only-testing:IDENTIFIER (repeatable),
                      e.g. --only TTBTests/FavoriteStoreTests
  --scheme NAME       Scheme (default: $XCB_SCHEME or the project name)
  -h, --help          Show this help

Environment:
  XCB_JOBS            Parallel compile jobs (default 4)
  XCB_SIMULATOR       Simulator name. Default: the project's slim test device from
                      Scripts/slim-sim.sh test-sim (made on first use) when --os is
                      $SLIM_SIM_OS (default 27.0; SLIM_SIM_DEVICE picks its device type),
                      else a stock "iPhone 12" with a loud warning ("iPhone 12 (iOS VERSION)"
                      also matches); it fails when that does not exist
  XCB_CACHE_ROOT      Shared cache root (default ~/Library/Caches/xcb)
  XCB_LOCK_TIMEOUT    Seconds to wait for the build lock (default 3600)
  XCB_DRY_RUN=1       Print the xcodebuild command; take no lock, build nothing

The build lock is machine-wide. A run can wait minutes behind another agent's build,
so start it with a long timeout or in the background.
EOF
}

fail() {
  printf 'xcb: error: %s\n' "$*" >&2
  exit 1
}

ACTION="${1:-}"
case "$ACTION" in
  build|test) shift ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

OS_VERSION="${XCB_OS:-27.0}"
SCHEME="${XCB_SCHEME:-}"
ONLY_TESTING=()
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --os) OS_VERSION="${2:?--os needs a version}"; shift 2 ;;
    --only) ONLY_TESTING+=("-only-testing:${2:?--only needs an identifier}"); shift 2 ;;
    --scheme) SCHEME="${2:?--scheme needs a name}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) fail "unknown option: $1 (see --help)" ;;
  esac
done

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
PROJECT_PATH="$(find "$REPO_ROOT" -maxdepth 1 -name '*.xcodeproj' -print -quit)"
[[ -n "$PROJECT_PATH" ]] || fail "no .xcodeproj in $REPO_ROOT"
PROJECT_NAME="$(basename "$PROJECT_PATH" .xcodeproj)"
SCHEME="${SCHEME:-$PROJECT_NAME}"

JOBS="${XCB_JOBS:-4}"
SLIM_SIM="$REPO_ROOT/Scripts/slim-sim.sh"
# The slim test device exists for the template's iOS version only (slim-sim.sh, SLIM_SIM_OS).
USE_SLIM_TEST_SIM=0
if [[ -z "${XCB_SIMULATOR:-}" && "$OS_VERSION" == "${SLIM_SIM_OS:-27.0}" && -x "$SLIM_SIM" ]]; then
  USE_SLIM_TEST_SIM=1
fi
SIMULATOR_NAME="${XCB_SIMULATOR:-iPhone 12}"
# Another --os has no slim test device: say so loudly instead of falling back in silence.
if [[ "$USE_SLIM_TEST_SIM" == 0 && -z "${XCB_SIMULATOR:-}" ]]; then
  printf 'xcb: WARNING ---------------------------------------------------------------
' >&2
  printf 'xcb: WARNING iOS %s is not the slim test device'"'"'s iOS (SLIM_SIM_OS=%s).
' "$OS_VERSION" "${SLIM_SIM_OS:-27.0}" >&2
  printf 'xcb: WARNING Using a stock, unslimmed "%s" on iOS %s instead. Set XCB_SIMULATOR to
' "$SIMULATOR_NAME" "$OS_VERSION" >&2
  printf 'xcb: WARNING pick a device, or SLIM_SIM_OS=%s to make a slim test device for it.
' "$OS_VERSION" >&2
  printf 'xcb: WARNING ---------------------------------------------------------------
' >&2
fi
CACHE_ROOT="${XCB_CACHE_ROOT:-$HOME/Library/Caches/xcb}"
PROJECT_CACHE="$CACHE_ROOT/$PROJECT_NAME"
DERIVED_DATA_PATH="$PROJECT_CACHE/DerivedData"
PACKAGES_PATH="$PROJECT_CACHE/SourcePackages"
LOG_DIR="$PROJECT_CACHE/logs"
LOCK_DIR="$CACHE_ROOT/build.lock"
LOCK_TIMEOUT="${XCB_LOCK_TIMEOUT:-3600}"

simulator_udid() {
  /usr/bin/python3 - "$SIMULATOR_NAME" "$OS_VERSION" <<'PY'
import json, subprocess, sys
name, version = sys.argv[1], sys.argv[2]
runtime_suffix = "iOS-" + version.replace(".", "-")
devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))["devices"]
# An exact name wins; a simulator renamed to "<name> (iOS <version>)" also matches.
for wanted in (name, f"{name} (iOS {version})"):
    for runtime, entries in devices.items():
        if runtime.endswith(runtime_suffix):
            for device in entries:
                if device["name"] == wanted:
                    print(device["udid"])
                    sys.exit(0)
sys.exit(1)
PY
}

simulator_state() {
  xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
for entries in json.load(sys.stdin)["devices"].values():
    for d in entries:
        if d["udid"] == sys.argv[1]:
            print(d["state"]); sys.exit(0)
print("missing")' "$1"
}

# Picks the device. The slim test device is made (from the template) on first use, which can
# take a minute; slim-sim.sh serialises that per project.
resolve_simulator() {
  if [[ "$USE_SLIM_TEST_SIM" == 1 ]]; then
    SIMULATOR_ID="$("$SLIM_SIM" test-sim)" || fail "Scripts/slim-sim.sh test-sim failed"
    SIMULATOR_NAME="$("$SLIM_SIM" names | sed -n 's/^test *//p')"
  else
    SIMULATOR_ID="$(simulator_udid)" \
      || fail "no available \"$SIMULATOR_NAME\" simulator on iOS $OS_VERSION (xcrun simctl list devices). The slim test device exists only for iOS ${SLIM_SIM_OS:-27.0}; set XCB_SIMULATOR, or SLIM_SIM_OS=$OS_VERSION to make one"
  fi
}

# A test boots its device. Shut down only the slim test device, and only when this run booted it.
shut_down_if_we_booted() {
  if [[ "$USE_SLIM_TEST_SIM" == 1 && "$ACTION" == test && "${SIM_STATE_BEFORE:-}" == Shutdown ]]; then
    xcrun simctl shutdown "$SIMULATOR_ID" 2>/dev/null || true
  fi
}

release_lock() {
  if [[ "$(cat "$LOCK_DIR/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "$LOCK_DIR"
  fi
}

acquire_lock() {
  mkdir -p "$CACHE_ROOT"
  local waited=0 holder
  until mkdir "$LOCK_DIR" 2>/dev/null; do
    holder="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
      printf 'xcb: removing stale lock from dead PID %s\n' "$holder"
      rm -rf "$LOCK_DIR"
      continue
    fi
    # A holder that died between mkdir and writing its PID leaves no PID file.
    if [[ -z "$holder" && -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +2 2>/dev/null)" ]]; then
      printf 'xcb: removing stale lock with no PID\n'
      rm -rf "$LOCK_DIR"
      continue
    fi
    if (( waited % 60 == 0 )); then
      printf 'xcb: waiting for the build lock (%ss) - held by: %s\n' \
        "$waited" "$(cat "$LOCK_DIR/owner" 2>/dev/null || echo unknown)"
    fi
    (( waited < LOCK_TIMEOUT )) || fail "gave up on the build lock after ${LOCK_TIMEOUT}s"
    sleep 5
    waited=$((waited + 5))
  done
  echo "$$" > "$LOCK_DIR/pid"
  printf '%s %s in %s (PID %s, since %s)\n' "$PROJECT_NAME" "$ACTION" "$REPO_ROOT" "$$" \
    "$(date '+%H:%M:%S')" > "$LOCK_DIR/owner"
  trap release_lock EXIT
  # An interrupted test still shuts down the slim test device it booted.
  trap 'shut_down_if_we_booted; release_lock; exit 130' INT
  trap 'shut_down_if_we_booted; release_lock; exit 143' TERM
}

if [[ "${XCB_DRY_RUN:-0}" == 1 ]]; then
  # A dry run makes no device: name the slim test device without creating it.
  if [[ "$USE_SLIM_TEST_SIM" == 1 ]]; then
    SIMULATOR_ID="<$("$SLIM_SIM" names | sed -n 's/^test *//p')>"
  else
    resolve_simulator
  fi
else
  acquire_lock
  resolve_simulator
fi

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration Debug
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -clonedSourcePackagesDirPath "$PACKAGES_PATH"
  -jobs "$JOBS"
  -hideShellScriptEnvironment
)
if [[ "$ACTION" == test ]]; then
  XCODEBUILD_ARGS+=(-parallel-testing-enabled NO)
  if [[ ${#ONLY_TESTING[@]} -gt 0 ]]; then
    XCODEBUILD_ARGS+=("${ONLY_TESTING[@]}")
  fi
fi
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  XCODEBUILD_ARGS+=("${EXTRA_ARGS[@]}")
fi
XCODEBUILD_ARGS+=(COMPILER_INDEX_STORE_ENABLE=NO "$ACTION")

if [[ "${XCB_DRY_RUN:-0}" == 1 ]]; then
  printf 'xcodebuild'
  printf ' %q' "${XCODEBUILD_ARGS[@]}"
  printf '\n'
  exit 0
fi

SIM_STATE_BEFORE="$(simulator_state "$SIMULATOR_ID")"

mkdir -p "$LOG_DIR"
# Keep the 20 newest logs.
find "$LOG_DIR" -name '*.log' -print0 | xargs -0 ls -1t 2>/dev/null | tail -n +20 \
  | while IFS= read -r old; do rm -f "$old"; done || true
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d-%H%M%S')-$ACTION-$(basename "$REPO_ROOT").log"

printf 'xcb: %s %s on %s iOS %s, %s jobs\nxcb: log %s\n' \
  "$ACTION" "$SCHEME" "$SIMULATOR_NAME" "$OS_VERSION" "$JOBS" "$LOG_FILE"
started=$SECONDS
status=0
nice -n 10 xcodebuild "${XCODEBUILD_ARGS[@]}" > "$LOG_FILE" 2>&1 || status=$?
elapsed=$((SECONDS - started))
shut_down_if_we_booted

grep -E 'error:|: failed|failed \(|✘|\*\* (BUILD|TEST) ' "$LOG_FILE" | sort -u | head -60 || true
if [[ $status -ne 0 ]]; then
  printf -- '--- last 25 log lines ---\n'
  tail -25 "$LOG_FILE"
fi
if [[ "$ACTION" == build && $status -eq 0 ]]; then
  app_path="$(find "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
  printf 'xcb: app %s\nxcb: simulator %s\n' "$app_path" "$SIMULATOR_ID"
fi
printf 'xcb: %s exit %s after %ss\n' "$ACTION" "$status" "$elapsed"
exit "$status"
