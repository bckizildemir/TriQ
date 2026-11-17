#!/usr/bin/env bash
# Prints the UDID of the iPhone simulator CI should test on.
#
# Runtimes sort by their numeric version, so iOS 26.10 beats iOS 26.6 (a string sort puts 26-6 first).
# The newest runtime that has an iPhone wins. Inside it, the first model of PREFERRED_MODELS that is
# installed wins, and any other iPhone is the fallback, so the pick never fails just because a model is missing.
#
# Usage:
#   Scripts/ci-pick-simulator.sh              print the UDID (reads `xcrun simctl list devices available -j`)
#   Scripts/ci-pick-simulator.sh --self-test  check the picking rules against fixed JSON; needs no simulator
set -euo pipefail

# Newest regular iPhone models first. A plain "iPhone 17" is a steadier test device than a Pro/Air/e variant.
PREFERRED_MODELS='iPhone 17|iPhone 16|iPhone 15'
export PREFERRED_MODELS

PICKER='
import json, os, re, sys

PREFERRED = os.environ["PREFERRED_MODELS"].split("|")

def runtime_version(key):
    m = re.search(r"\.iOS-(\d+(?:-\d+)*)$", key)
    return tuple(int(p) for p in m.group(1).split("-")) if m else None

def pick(devices_by_runtime):
    runtimes = []
    for key, devices in devices_by_runtime.items():
        version = runtime_version(key)
        if version is None:
            continue
        iphones = [d for d in devices if d.get("name", "").startswith("iPhone") and d.get("isAvailable", True)]
        if iphones:
            runtimes.append((version, iphones))
    if not runtimes:
        raise SystemExit("no available iPhone simulator on an iOS runtime")
    _, iphones = max(runtimes, key=lambda r: r[0])
    for model in PREFERRED:
        for d in iphones:
            if d["name"] == model:
                return d["udid"]
    return sorted(iphones, key=lambda d: d["name"])[0]["udid"]

if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
    def dev(name, udid, available=True):
        return {"name": name, "udid": udid, "isAvailable": available}
    R = "com.apple.CoreSimulator.SimRuntime."
    cases = [
        ("numeric version, not string order",
         {R + "iOS-26-6": [dev("iPhone 17", "OLD")], R + "iOS-26-10": [dev("iPhone 17", "NEW")]}, "NEW"),
        ("26-2 vs 26-10 vs 9-9",
         {R + "iOS-26-2": [dev("iPhone 17", "B")], R + "iOS-26-10": [dev("iPhone 17", "A")], R + "iOS-9-9": [dev("iPhone 17", "C")]}, "A"),
        ("preferred model beats an earlier listed one",
         {R + "iOS-26-6": [dev("iPhone 17 Pro Max", "PM"), dev("iPhone 16", "SIXTEEN"), dev("iPhone 17", "SEVENTEEN")]}, "SEVENTEEN"),
        ("fallback to any iPhone, by name",
         {R + "iOS-26-6": [dev("iPad Pro", "PAD"), dev("iPhone Air", "AIR"), dev("iPhone 17 Pro", "PRO")]}, "PRO"),
        ("skips a newer runtime with no iPhone",
         {R + "iOS-27-0": [dev("iPad Pro", "PAD")], R + "iOS-26-6": [dev("iPhone 17", "PHONE")]}, "PHONE"),
        ("ignores watchOS and unavailable devices",
         {R + "watchOS-11-5": [dev("iPhone fake", "W")], R + "iOS-26-6": [dev("iPhone 17", "GONE", False), dev("iPhone 16", "OK")]}, "OK"),
    ]
    failed = 0
    for label, data, want in cases:
        got = pick(data)
        status = "ok  " if got == want else "FAIL"
        failed += got != want
        print(f"{status} {label}: got {got}, want {want}")
    try:
        pick({R + "iOS-26-6": [dev("iPad Pro", "PAD")]})
        print("FAIL no-iPhone case did not exit"); failed += 1
    except SystemExit:
        print("ok   no iPhone exits with an error")
    sys.exit(1 if failed else 0)

print(pick(json.load(sys.stdin)["devices"]))
'

if [[ "${1:-}" == "--self-test" ]]; then
  exec python3 -c "$PICKER" --self-test
fi

xcrun simctl list devices available -j | python3 -c "$PICKER"
