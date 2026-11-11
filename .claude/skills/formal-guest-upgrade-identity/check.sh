#!/bin/sh
# One command for the guest-upgrade-identity check.
#
#   STATECHART=<the /statechart skill's script> .claude/skills/formal-guest-upgrade-identity/check.sh [--save]
#
# 1. Model-checks GuestUpgradeIdentity.tla with the /statechart skill (TLC), view.mjs for the words.
# 2. Replays each known finding's server half against functions/usernameRegistry.js (replay-server.mjs).
# 3. Compares the rules that break with KNOWN_FINDINGS below.
#
# Exit 0: exactly the known findings break and all still reproduce on the server.
# Exit 1: a new rule breaks, or a known finding stopped breaking: read the report, then SKILL.md.
# Exit 2: the tools did not run.
# --save writes chart.mmd, report.md and tlc.out to charts/ (commit them); otherwise a temp folder.

set -eu
here=$(cd "$(dirname "$0")" && pwd)

# Rules the code at the sync commit breaks (SKILL.md "Findings"). Edit only with a matching SKILL.md change.
KNOWN_FINDINGS="FailedUpgradeLeavesNoName NoOrphanAfterSignUp NoOrphanAfterUpgrade ShownNameIsHeld UpgradedAccountKeepsItsName"

if [ -z "${STATECHART:-}" ] || [ ! -x "$STATECHART" ]; then
  echo "Set STATECHART to the script of the /statechart skill (load /statechart; it names its script)." >&2
  exit 2
fi

# statechart writes only to a new or empty folder, so it always gets a fresh one.
out=$(mktemp -d "${TMPDIR:-/tmp}/formal-guest-upgrade-identity.XXXXXX")
work=$(mktemp -d "${TMPDIR:-/tmp}/formal-guest-upgrade-identity-work.XXXXXX")
cp "$here/GuestUpgradeIdentity.tla" "$here/GuestUpgradeIdentity.cfg" "$here/view.mjs" "$work/"
# statechart exits non-zero when a rule breaks, which is expected here; a missing report is not.
(cd "$work" && "$STATECHART" GuestUpgradeIdentity.tla --config GuestUpgradeIdentity.cfg --view view.mjs --out "$out") || true
if [ ! -s "$out/report.md" ] || grep -q "Rules not checked" "$out/report.md"; then
  echo "statechart did not finish every rule; see above and $out/tlc.out." >&2
  exit 2
fi

if [ "${1:-}" = "--save" ]; then
  mkdir -p "$here/charts"
  cp "$out/report.md" "$out/tlc.out" "$here/charts/"
  if [ -f "$out/chart.mmd" ]; then cp "$out/chart.mmd" "$here/charts/"; fi
fi

broken=$(sed -n 's/^## \([A-Za-z0-9]*\) breaks$/\1/p' "$out/report.md" | sort | tr '\n' ' ' | sed 's/ $//')
known=$(echo "$KNOWN_FINDINGS" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')

echo
echo "Report: $out/report.md"
echo "Rules that break:  ${broken:-none}"
echo "Known findings:    $known"

status=0
if [ "$broken" != "$known" ]; then
  echo "MISMATCH: the model's result changed. A new rule in the first list is a new bug or a model error;" >&2
  echo "a known finding missing from it was fixed in the code or hidden by a model change. See SKILL.md." >&2
  status=1
fi

echo
node "$here/replay-server.mjs" || status=1
exit $status
