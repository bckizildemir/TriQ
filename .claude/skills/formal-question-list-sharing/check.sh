#!/bin/sh
# One-command check for the question-list-sharing TLA+ model.
#
#   STATECHART=<the /statechart skill's script> .claude/skills/formal-question-list-sharing/check.sh [--charts] [--replay]
#
# Load the /statechart skill first; it says where its script lives on this machine.
#   --charts  also redraw charts/chart.mmd and charts/report.md (the owner's flow chart)
#   --replay  also replay the known findings on the real callables (needs functions/node_modules)
#
# Exit: 0 = every rule holds except the known findings below
#       1 = a rule broke that is not a known finding (read the report it prints)
#       3 = the code no longer has a line the model relies on (re-read the code, update the model)
#       4 = a known finding no longer breaks (fixed? confirm, then update SKILL.md and KNOWN)
#       2 = the tool could not run
set -u

KNOWN="NoReplyAfterLeavingOrRevocation ReplacedLinkAdmitsNoOne"

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
spec="$here/QuestionListSharing.tla"
charts=0; replay=0
for a in "$@"; do
  case $a in
    --charts) charts=1 ;;
    --replay) replay=1 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done

if [ -z "${STATECHART:-}" ] || [ ! -x "$STATECHART" ]; then
  echo "Set STATECHART to the /statechart skill's script (load /statechart to find it)." >&2
  exit 2
fi

# 1. Anchors: lines of code that each modelled step stands on. A missing line means
#    the model may no longer describe the code.
missing=0
anchor() { # file, model step, exact text
  if ! grep -qF -- "$3" "$repo/$1"; then
    echo "ANCHOR MISSING  $1  (model: $2)" >&2
    echo "    expected: $3" >&2
    missing=1
  fi
}
F=functions/questionListShares.js
R=firestore.rules
anchor $F "Claimable"                       'return share.status === "active" && share.isLinkEnabled === true;'
anchor $F "RecipientTapsAccept (lookup outside the transaction)" 'const shareRef = shareSnapshot.ref;'
anchor $F "AcceptTransaction (no-op for accepted)" 'if (recipientSnapshot.exists && existing.status === "accepted" && share.status === "active") {'
anchor $F "AcceptTransaction (claimable re-check)" 'if (!shareIsClaimable(share)) {'
anchor $F "AcceptTransaction (cap)"          'if (acceptedRecipientCount >= numericOrDefault(share.recipientCap, DEFAULT_RECIPIENT_CAP)) {'
anchor $F "RecipientOpensLink"               'if (!isAccepted && !shareIsClaimable(share)) {'
anchor $F "OwnerRegeneratesLink"             'shareCodePrefix: shareCode.slice(0, 6),'
anchor $F "OwnerRevokesShare (part 1)"       'status: "revoked",'
anchor $F "RevokeReadsRecipients (part 2)"   'const recipientsSnapshot = await shareRef.collection("recipients").get();'
anchor $F "RevokeCommitsBatch (part 3)"      'await batch.commit();'
anchor $F "RecipientTapsSendAnswers (part 1)" 'if (!shareSnapshot.exists || share.status !== "active") {'
anchor $F "ReplyChecksRecipient (part 2)"    'const recipientSnapshot = await recipientRef.get();'
anchor $F "ReplyWritten (part 3)"            'unreadByOwner: true,'
anchor $F "RecipientLeaves"                  'status: "left",'
anchor $R "CanReadShare"                     "&& resource.data.status == 'active'"
anchor $R "CanReadShare"                     "&& get(acceptedRecipientPath()).data.status == 'accepted'"
[ $missing -eq 0 ] || { echo "Re-read the code, update QuestionListSharing.tla and these anchors, then rerun." >&2; exit 3; }

# 2. Has the covered code changed since the sync commit in SKILL.md?
sync=$(sed -n 's/^Sync commit: `\([0-9a-f]*\)`.*/\1/p' "$here/SKILL.md")
if [ -n "$sync" ] && ! git -C "$repo" diff --quiet "$sync" -- $F $R TTB/Services/QuestionListShareService.swift TTB/Views/Main/SharedQuestionListViews.swift 2>/dev/null; then
  echo "NOTE  covered files changed since sync commit $sync: confirm the model still matches (SKILL.md, 'Keep it in step')." >&2
fi

work=$(mktemp -d)
run() { # cfg, out, [view]
  if [ $# -eq 3 ]; then "$STATECHART" "$spec" --config "$1" --view "$3" --out "$2" >/dev/null 2>"$2.err"
  else "$STATECHART" "$spec" --config "$1" --out "$2" >/dev/null 2>"$2.err"; fi
  rc=$?
  if [ $rc -ge 2 ]; then cat "$2.err" >&2; echo "statechart failed (exit $rc)" >&2; exit 2; fi
}
broken() { sed -n 's/^## \(.*\) breaks$/\1/p' "$1/report.md" | sort; }

# 3. The check: owner + 2 recipients.
run "$here/QuestionListSharing.cfg" "$work/check"
found=$(broken "$work/check")
# statechart caps reruns after a break; check the remaining rules without the broken ones.
if grep -q '^## Rules not checked' "$work/check/report.md"; then
  cfg="$work/rest.cfg"
  cp "$here/QuestionListSharing.cfg" "$cfg"
  for r in $found; do sed -i.bak "/^  $r\$/d" "$cfg"; done
  run "$cfg" "$work/rest"
  found=$(printf '%s\n%s\n' "$found" "$(broken "$work/rest")" | sed '/^$/d' | sort -u)
  if grep -q '^## Rules not checked' "$work/rest/report.md"; then
    echo "Some rules were not checked; see $work/rest/report.md" >&2; exit 2
  fi
fi

cat "$work/check/report.md"
[ -f "$work/rest/report.md" ] && { echo; echo "---- remaining rules, broken ones removed ----"; cat "$work/rest/report.md"; }

# 4. The owner's flow chart (one recipient).
if [ $charts -eq 1 ]; then
  run "$here/Chart.cfg" "$work/chart" "$here/view.ts"
  mkdir -p "$here/charts"
  cp "$work/chart/chart.mmd" "$work/chart/report.md" "$here/charts/"
  echo "charts/ updated"
fi

# 5. Replay the known findings on the real callables (fake Firestore from the functions tests).
if [ $replay -eq 1 ]; then
  if [ ! -d "$repo/functions/node_modules" ]; then echo "run npm ci in functions/ first" >&2; exit 2; fi
  WT="$repo" node --test "$here/replay/findings.replay.js" || { echo "replay did not reproduce a finding: suspect the model" >&2; exit 1; }
fi

echo
echo "Broken rules: $(echo ${found:-none} | tr "\n" " ")"
new=""; gone=""
for r in $found; do case " $KNOWN " in *" $r "*) ;; *) new="$new $r" ;; esac; done
for r in $KNOWN; do echo "$found" | grep -qx "$r" || gone="$gone $r"; done
echo "Output kept in $work"
if [ -n "$new" ]; then echo "NEW BREAK:$new" >&2; exit 1; fi
if [ -n "$gone" ]; then echo "KNOWN FINDING NO LONGER BREAKS:$gone" >&2; exit 4; fi
echo "OK: only the known findings break."
exit 0
