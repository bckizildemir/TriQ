# Skill provenance

This directory holds the 8 agent skills that ship with this repository. Six of them were vendored
— copied in from an upstream project. Five of those six were then edited locally, in `186b03c`,
`85747e5` and `dfb0901`, to remove hazards and to pin the Firebase project. The other two are
first-party and were written here. A skill whose policy is `fork` must never be refreshed from
upstream without first re-reading the local edits: the edits are deliberate, and a blind copy
would silently revert them.

Upstream: <https://github.com/firebase/agent-skills>, with each skill at `skills/<name>/`. All six
vendored skills come from one snapshot: commit `9067c1e3d3afbb212235356702db6ab4b82ec88a`
(2026-05-06), "Removing hard-coded version numbers (#114)". Pristine copies of that snapshot live
in this repo at commit `a203381`, before the local edits landed — that commit is the diff base for
"what did we change".

Caution: git history alone does not prove that the vendored files are pristine at `a203381`. Before
that commit the skills lived in `.agents/skills/`, which `.gitignore` excludes. Git therefore shows
every file as newly added at `a203381`, and holds no record of the import or of any edit before it.
The audit recipe below, which compares `a203381` against upstream, is the only proof. Do not read
the clean history as evidence.

| Skill | Origin | Policy |
|---|---|---|
| firebase-basics | upstream | `fork` |
| firebase-auth-basics | upstream | `fork` |
| firebase-firestore | upstream | `fork` |
| firebase-hosting-basics | upstream | `fork` |
| firebase-security-rules-auditor | upstream | `fork` |
| xcode-project-setup | upstream | `fork` |
| ttb-firebase-functions-debugging | first-party | `own` |
| ttb-share-link-deep-links | first-party | `own` |

## Why `fork`, not `track`

Caution: every upstream fact in this section was read in a clone of upstream, and this repository
cannot re-check any of it. Upstream is not a git remote here, and no upstream object is present:
`git cat-file -t 9067c1e3d3afbb212235356702db6ab4b82ec88a` fails, and so does `git cat-file -t` on
each of the two hashes below.

Since the snapshot, 10 upstream commits touch those 6 skills, and all 6 have changed upstream. Two
of those commits show why an automatic refresh is unsafe:

- `2a55732` "Add Genkit redirection and installation instructions under Common Issues (#132)" — a
  5-line addition to `skills/firebase-basics/SKILL.md`, the only file it touches. It adds a pointer
  to the Genkit skills under Common Issues: `npx skills add genkit-ai/skills`. It carries no
  `curl | bash` line. TTB commit `186b03c` deleted the vendored Genkit skills, because they carried
  the only `curl | bash` installer lines. A refresh therefore restores a pointer to skills this repo
  chose not to keep. It does not restore the deleted installer lines.
- `c3bb9d5` "Update Firestore skill for location selection (#116)" — TTB commit `186b03c` removed
  exactly that hazard: the branch that would create an Enterprise database in `nam5`, when this
  repo runs `(default)`, Standard edition, in `eur3`. `186b03c` deleted the whole
  `references/enterprise/` subtree, `provisioning.md` included. The TTB half of this bullet is
  re-derivable here, and the path matters:

  ```sh
  git log --oneline -S'nam5' -- .claude/skills/firebase-firestore/
  git log --oneline -S'nterprise' -- .claude/skills/firebase-firestore/
  ```

  Both return exactly `186b03c` and the import `a203381`. Scoped to
  `.claude/skills/firebase-firestore/references/enterprise/` both return nothing, because that path
  does not exist at `HEAD` and git simplifies it out of the history; add `--full-history` and the
  same pair comes back.

A blind refresh puts both back: the `nam5` branch as a live hazard, and the Genkit pointer as a
reference this repo dropped on purpose.

## Re-deriving the facts

Two checks follow. Neither re-derives the Policy column: `fork` versus `own` is a decision recorded
here, not a fact any command computes. The second check re-derives Origin for the six upstream
skills; nothing proves `first-party` for the other two beyond the absence of an upstream copy.

**Has this skill been edited locally since import?** This is the day-to-day check. It compares the
current tree against the import commit in this repo, so no clone is needed:

```sh
git rev-parse HEAD:.claude/skills/<name>
git rev-parse a203381:.claude/skills/<name>
```

Equal hashes mean the skill is untouched since import. Different hashes mean local edits exist, and
this lists them:

```sh
git log --oneline -- .claude/skills/<name>
```

**Is the snapshot commit recorded above the true origin of the imported files?** This is a one-time
audit of this record, not a drift check — both hashes are fixed historical commits, so they always
match and say nothing about the current tree. Run the second command in a clone of upstream:

```sh
git rev-parse a203381:.claude/skills/<name>
git rev-parse 9067c1e3:skills/<name>
```

All 6 vendored skills matched at `a203381` when this file was written, `xcode-project-setup`
included. That is a statement about the import commit, not about `HEAD`, where five of the six
carry local edits. It was checked in a clone of upstream and cannot be re-checked here. Its
`Package.resolved` and its nested `scripts/xcode_spm_setup/.gitignore` are upstream files, not local
additions, so they do not disturb the hash. A tree hash covers the whole subtree, so one added or
renamed file makes it differ even when every shared file is identical. Do not read a mismatch as
edited content before you see the per-file picture:

```sh
diff -ru <upstream-clone>/skills/<name> .claude/skills/<name>
```

A new or re-synced skill gets a row here. Nothing enforces this file; it is documentation for
people and agents.
