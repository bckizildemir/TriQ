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
#   - One simulator at a time: other booted simulators are shut down before a test.
#   - The full log goes to a file; the terminal gets errors, failures, and the tail.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Scripts/xcb.sh build [options] [-- extra xcodebuild args]
  Scripts/xcb.sh test  [options] [-- extra xcodebuild args]

Options:
  --os VERSION        Simulator iOS version (default: $XCB_OS or 26.5)
  --only IDENTIFIER   Passed as -only-testing:IDENTIFIER (repeatable),
                      e.g. --only TTBTests/FavoriteStoreTests
  --scheme NAME       Scheme (default: $XCB_SCHEME or the project name)
  -h, --help          Show this help

Environment:
  XCB_JOBS            Parallel compile jobs (default 4)
  XCB_SIMULATOR       Simulator name (default "iPhone 12"; "iPhone 12 (iOS VERSION)"
                      also matches)
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

OS_VERSION="${XCB_OS:-26.5}"
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
SIMULATOR_NAME="${XCB_SIMULATOR:-iPhone 12}"
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

shut_down_other_simulators() {
  local keep="$1" udid
  for udid in $(xcrun simctl list devices booted -j | /usr/bin/python3 -c '
import json, sys
for entries in json.load(sys.stdin)["devices"].values():
    for device in entries:
        print(device["udid"])'); do
    if [[ "$udid" != "$keep" ]]; then
      printf 'xcb: shutting down simulator %s (one simulator at a time)\n' "$udid"
      xcrun simctl shutdown "$udid" || true
    fi
  done
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
  trap 'release_lock; exit 130' INT TERM
}

SIMULATOR_ID="$(simulator_udid)" \
  || fail "no available \"$SIMULATOR_NAME\" simulator on iOS $OS_VERSION (xcrun simctl list devices)"

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

acquire_lock

if [[ "$ACTION" == test ]]; then
  shut_down_other_simulators "$SIMULATOR_ID"
fi

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
