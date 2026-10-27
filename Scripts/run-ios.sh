#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="TTB.xcodeproj"
SCHEME="TTB"
CONFIGURATION="Debug"
DEVICE_NAME="iPhone 12 slim test (TriQ)"
RUNTIME_MAJOR="27"
PRODUCT_BUNDLE_IDENTIFIER="app.berke.can.kizildemir.ttb"
DERIVED_DATA_PATH="${TMPDIR:-/tmp}/ttb-codex-derived-data"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

clear_corrupt_package_cache() {
  local source_packages_dir="$DERIVED_DATA_PATH/SourcePackages"
  local artifacts_dir="$DERIVED_DATA_PATH/SourcePackages/artifacts"
  [[ -d "$source_packages_dir" ]] || return 0

  if [[ ! -d "$artifacts_dir" ]]; then
    printf 'Incomplete Swift Package cache detected. Clearing %s...\n' "$source_packages_dir"
    rm -rf "$source_packages_dir"
    return 0
  fi

  local artifact_count=0
  while IFS= read -r -d '' xcframework_path; do
    artifact_count=$((artifact_count + 1))
    if [[ ! -f "$xcframework_path/Info.plist" ]]; then
      printf 'Incomplete Swift Package artifact cache detected. Clearing %s...\n' "$source_packages_dir"
      rm -rf "$source_packages_dir"
      return 0
    fi
  done < <(find "$artifacts_dir" -type d -name '*.xcframework' -print0)

  if [[ "$artifact_count" -eq 0 ]]; then
    printf 'Empty Swift Package artifact cache detected. Clearing %s...\n' "$source_packages_dir"
    rm -rf "$source_packages_dir"
  fi
}

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild bulunamadi. Xcode kurulu ve xcode-select ayarli olmali."
command -v xcrun >/dev/null 2>&1 || fail "xcrun bulunamadi. Xcode command line tools kurulu olmali."

[[ -d "$PROJECT_PATH" ]] || fail "$PROJECT_PATH bulunamadi. Script repo kokunden calistirilmali."

# The project's slim test device (iPhone 12, iOS 27.0), made from the SimSlim template on first
# use. The same device Scripts/xcb.sh tests on; never the verify template itself.
SIMULATOR_ID="$(Scripts/slim-sim.sh test-sim)" || fail "Scripts/slim-sim.sh test-sim basarisiz."

DESTINATION="platform=iOS Simulator,id=${SIMULATOR_ID}"

clear_corrupt_package_cache

printf 'Building %s (%s) for %s / iOS %s...\n' "$SCHEME" "$CONFIGURATION" "$DEVICE_NAME" "$RUNTIME_MAJOR"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || fail "Build basarili gorunuyor ama .app bulunamadi: $DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator"

BUILT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" 2>/dev/null || true)"
[[ "$BUILT_BUNDLE_ID" == "$PRODUCT_BUNDLE_IDENTIFIER" ]] || fail "Bundle identifier beklenenden farkli. Beklenen: $PRODUCT_BUNDLE_IDENTIFIER, bulunan: ${BUILT_BUNDLE_ID:-bos}"

printf 'Booting simulator %s...\n' "$SIMULATOR_ID"
xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_ID" >/dev/null 2>&1 || true

printf 'Installing %s...\n' "$APP_PATH"
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

cleanup() {
  if [[ -n "${LOG_STREAM_PID:-}" ]]; then
    kill "$LOG_STREAM_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

printf 'Starting live logs for %s. Press Ctrl+C to stop.\n' "$SCHEME"
xcrun simctl spawn "$SIMULATOR_ID" log stream \
  --level debug \
  --style compact \
  --predicate "(process == \"${SCHEME}\" AND NOT subsystem BEGINSWITH \"com.apple\") OR subsystem == \"${PRODUCT_BUNDLE_IDENTIFIER}\"" &
LOG_STREAM_PID="$!"

printf 'Launching %s...\n' "$PRODUCT_BUNDLE_IDENTIFIER"
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" "$PRODUCT_BUNDLE_IDENTIFIER"

printf 'App launched. Streaming logs; press Ctrl+C to stop.\n'
wait "$LOG_STREAM_PID"
