#!/bin/sh
# One command: read the flags from the code, check each rule with TLC on both configs, and compare
# the result with the known findings in SKILL.md. Exit 0: as expected. Exit 1: a rule changed
# (a new break, or a known finding no longer breaks). Exit 2: the code no longer matches the model.
#
# usage: .claude/skills/formal-ai-quota-pools/run.sh [out dir]
# env:   TLA2TOOLS=<path to tla2tools.jar> to skip the download; JAVA=<java binary>.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
out=${1:-${TMPDIR:-/tmp}/formal-ai-quota-pools.$$}
mkdir -p "$out"
java=${JAVA:-java}

# TLC, pinned.
tla_version=1.7.4
tla_sha=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
jar=${TLA2TOOLS:-$HOME/.cache/tla2tools/$tla_version/tla2tools.jar}
if [ ! -f "$jar" ]; then
  mkdir -p "$(dirname "$jar")"
  echo "Downloading tla2tools.jar $tla_version ..."
  curl -fsSL -o "$jar.part" "https://github.com/tlaplus/tlaplus/releases/download/v$tla_version/tla2tools.jar"
  echo "$tla_sha  $jar.part" | shasum -a 256 -c - >/dev/null
  mv "$jar.part" "$jar"
fi

# Sync check: has the covered code moved since the model was last confirmed?
sync=$(sed -n 's/^Sync commit: `\([0-9a-f]*\)`.*/\1/p' "$here/SKILL.md")
changed=$(git -C "$root" log --oneline "$sync"..HEAD -- functions/aiUsageLimit.js functions/index.js functions/accountDeletion.js functions/appCheckReplay.js firestore.rules 2>/dev/null || echo "(sync commit $sync not found)")
if [ -n "$changed" ]; then
  echo "NOTE: covered code changed since sync commit $sync; confirm the model still describes it:"
  echo "$changed" | sed 's/^/  /'
fi

flags=$(node "$here/extract-flags.mjs" "$root") || exit 2
printf '%s\n' "$flags" > "$out/flags.txt"
echo "Flags read from the code:"
echo "$flags" | sed 's/^/  /'

cp "$here/AIQuotaPools.tla" "$out/"

# Expected result: "<cfg> <rule>" pairs that break today (SKILL.md, "Known findings").
known_breaks=""

rules_all="UidWithinDailyLimit PoolWithinDailyLimit NoWrongLockout"
status=0
for cfg in AIQuotaPools rollover deletion core; do
  # Check every rule at once; when one breaks, note it, drop it and run again, so each rule gets
  # a verdict.
  rules=$rules_all
  pass=0
  broken=""
  while [ -n "$rules" ]; do
    pass=$((pass + 1))
    run="$out/$cfg-$pass"
    mkdir -p "$run"
    awk -v rules="$rules" '
      FNR == NR { v[$1] = $3; next }
      /^INVARIANTS/ { print; print "    TypeOK"; n = split(rules, r, " "); for (i = 1; i <= n; i++) print "    " r[i]; exit }
      { for (k in v) if ($1 == k) { $0 = "    " k " = " v[k] } print }
    ' "$out/flags.txt" "$here/$cfg.cfg" > "$run/check.cfg"
    (cd "$out" && "$java" -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto \
        -metadir "$run/meta" -config "$run/check.cfg" AIQuotaPools.tla > "$run/tlc.out" 2>&1) || true
    states=$(sed -n 's/^[0-9]* states generated, \([0-9]*\) distinct states found.*/\1/p' "$run/tlc.out" | tail -1)
    if grep -q "No error has been found" "$run/tlc.out"; then
      break
    fi
    rule=$(sed -n 's/^Error: Invariant \([A-Za-z]*\) is violated.*/\1/p' "$run/tlc.out" | head -1)
    if [ -z "$rule" ] || [ "$rule" = TypeOK ]; then
      echo "$cfg: TLC stopped on an error, not a rule. Read $run/tlc.out"
      exit 2
    fi
    broken="$broken $rule"
    echo "$cfg: $rule BREAKS. Steps: $(grep -o '^State [0-9]*: <[A-Za-z]*' "$run/tlc.out" | sed 's/.*<//' | tr '\n' ' ')"
    echo "    TLC output: $run/tlc.out"
    rules=$(echo "$rules" | tr ' ' '\n' | grep -vx "$rule" | tr '\n' ' ' | sed 's/ *$//')
  done
  for rule in $rules_all; do
    case " $broken " in *" $rule "*) verdict=BREAKS ;; *) verdict=HOLDS ;; esac
    case " $known_breaks " in *" $cfg:$rule "*) expected=BREAKS ;; *) expected=HOLDS ;; esac
    if [ "$verdict" = "$expected" ]; then mark="as expected"; else mark="CHANGED (expected $expected)"; status=1; fi
    printf '%-13s %-21s %-7s %s\n' "$cfg" "$rule" "$verdict" "$mark"
  done
  echo "$cfg: last run explored ${states:-?} distinct states"
done

# The model no longer holds the stale clock read (the day is read in the transaction), so the real
# code is replayed too: a call that waits across midnight, and account deletion (TriQ#153).
if [ -d "$root/functions/node_modules" ]; then
  if node "$here/replay.cjs" > "$out/replay.out" 2>&1; then
    echo "replay        real consumeDailyQuota  HOLDS   as expected"
  else
    echo "replay        real consumeDailyQuota  BREAKS  CHANGED (expected HOLDS). Read $out/replay.out"
    status=1
  fi
else
  echo "replay        skipped: run npm ci in functions/ first"
fi

echo "Output: $out"
if [ "$status" -ne 0 ]; then
  echo "A rule differs from the known findings. Read the path with /statechart before you decide (SKILL.md)."
fi
exit "$status"
