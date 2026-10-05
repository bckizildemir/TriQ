# Swift skill triggers

> **Update 2026-10-02 — the hook moved to user level.** It is now `~/.claude/hooks/swift-skill-reminder.sh`,
> registered once in `~/.claude/settings.json`; the copy in `.claude/settings.local.json` was removed.
> CatCareCalendar and TTB share one script: the test arm `*Tests/*|*Tests.swift|*UITests*` covers
> `Tests/` and `TTBUITests/`, and `swiftdata-pro` is named only for files that use SwiftData. The script
> also reads a subagent's own transcript (`<session>/subagents/agent-<agent_id>.jsonl`), which fixes a
> repeat-reminder loop inside subagents. Where this document describes the per-repo hook or the two
> TTB-vs-CatCareCalendar hook differences, the update wins. Full record:
> CatCareCalendar `docs/swift-skill-trigger-setup.md`.

Two mechanisms make the mandatory Swift skills fire. `CLAUDE.md` and `.claude/rules/swift-skills.md`
state the rule up front, for the agent to follow before it edits. A `PostToolUse` hook re-states it
after the edit, catching the turn where the agent skipped the rule.

## The hook

Live definition: `.claude/settings.local.json`, `hooks.PostToolUse[0]`, matcher `Edit|MultiEdit|Write`.
Read the script there — this doc records the design, not the body.

- **A non-Swift path exits silently with rc=0.** The hook stays quiet about files it has no opinion on.
- **Path picks one primary skill, content adds the rest.** The `Tests/` and `Views/` path arms win
  first, and a content grep catches everything else. Concurrency, Liquid Glass, and navigation chrome
  are additive, so one file can name several skills.
- **It self-silences.** It greps the transcript for a skill already invoked this session and drops it
  from the message, so it only ever asks for what has not run. When nothing is left, it emits
  nothing. Observed in CCC on 2026-08-17: silent after two edits, then a note on the third.
- **It advises, never blocks.** It returns `additionalContext` and always exits 0.

`ios-memory-perf` has no trigger. Perf work is not detectable from the shape of a diff, so the
`CLAUDE.md` table is its only route.

### Where the hook does not fire

`.claude/settings.local.json` is machine-local and gitignored, so it never arrives with the code. A
fresh clone has no hook, and neither does a checkout that sits outside the repository — a sibling
handoff directory has no parent `.claude/` to inherit from. There the routing table in `CLAUDE.md`
and `.claude/rules/swift-skills.md` is the whole mechanism.

A worktree under `.claude/worktrees/` is not such a case. It sits inside the repository, hook
configuration resolves from parent directories, and the hook fires there normally. CCC proved this
on 2026-08-17: an agent in `.claude/worktrees/fix-taskaddview-review` got six `PostToolUse:Edit`
notes, each carrying the worktree's own path. An earlier revision of this doc claimed the opposite.

The matcher is the real limit. It sees `Edit`, `MultiEdit`, and `Write` only, so an edit through
Bash, inside a subagent, or by the user in Xcode never reaches it.

Install the hook per machine by copying `hooks.PostToolUse` from a checkout that has it into
`.claude/settings.local.json`. Merge it into the existing JSON rather than replacing the file: that
file also carries `permissions` and other machine-local keys, and a hooks block does not belong
inside `permissions.allow`.

## Shared with CatCareCalendar

CatCareCalendar (CCC) runs the same hook script. Keep the two copies identical except where the repos
genuinely differ. Two deliberate differences remain. Each is a fact about the repo, not drift:

| Difference | TTB | CCC | Reason |
|---|---|---|---|
| Test path arm | `*/Tests/*`, `*Tests.swift`, `*TTBUITests*` | `*Tests/*`, `*Tests.swift`, `*UITests*` | The UI test target names differ. |
| `swiftdata-pro` | dropped | kept | TTB has zero `import SwiftData`, re-measured 0 on 2026-08-17. CCC has 57 files that import it. |

A third difference closed on 2026-08-16: TTB grepped file contents for `XCTestCase` and CCC did not.
Both do now.

The rest of the script is shared. Any other drift is a bug in one copy — diff both before you edit
either one.

The hook script is not the only shared surface. Since 2026-08-25 `.claude/settings.json` is one too:
its `permissions.allow` block carries the same six `mcp__xcodebuildmcp__*` entries in both repos.
Diff that file as well. Those six rules are inert on a fresh clone, because the `xcodebuildmcp`
server is configured in `~/.claude.json` rather than in a tracked `.mcp.json`.

## Skills do not leak between repos

Only `.claude/skills/` inside a repo loads for that repo. TTB's 8 project skills are invisible to CCC,
and CCC's are invisible to TTB, so a project-skill edit cannot reach the other repo.

The shared surface is `~/.claude/skills`, which holds the personal skills — including the six mandatory
Swift ones — installed per machine and used by both repos on purpose. An edit there changes both.
Neither repo ships those six, and neither repo may write to `~/.claude/skills` on the other's behalf.

## The `.claude/rules/` frontmatter key — settled, do not reopen

`paths:` is the correct key. Both repos already ship it. Do not switch to `globs:`.

- A rule with `paths:` stays out of context until the agent reads a file matching one of its globs.
- `globs:` is not recognised. A rule whose only key is `globs:` has no filter at all, so it loads at
  session start and sits in context for the whole session — the opposite of what it looks like.
- A `paths:` rule whose globs match nothing never loads.
- `claudemd_rule_globs` inside the `claude` binary is the internal field name, not the frontmatter
  key. It is a false lead; do not treat it as evidence for `globs:`.
- Confirmed twice on 2026-08-17. The official docs at `code.claude.com/docs/en/memory.md` say
  "Rules can be scoped to specific files using YAML frontmatter with the `paths` field", and a
  controlled experiment with three sentinel rule files and one fresh agent reproduced all three
  behaviours above. Cursor's `.mdc` rule files use `globs:`; that is Cursor's dialect, and the overlap
  in wording is what makes this worth writing down.
