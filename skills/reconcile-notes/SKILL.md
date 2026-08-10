---
name: reconcile-notes
description: Run on the integration branch after branches land — archive the notes of merged branches, invalidate the derived baseline, and report which of its claims the landing contradicted. Use this after merging a pull request or a queue of them, when the .branch-notes folder has grown, during repo housekeeping, before a release cut, or whenever the user asks to clean up branch notes. Also use when another skill reports the baseline is stale, since this is the step that keeps it honest.
---

# reconcile-notes

Every other skill is branch-scoped and runs while work is in flight. Nothing runs on the
integration branch, so the moment a branch lands — when what changed is cheapest and most certain
to determine — is currently spent on nothing. The intent layer captures and then never
reconciles, and the drift shows up weeks later as a baseline nobody trusts and a notes folder
nobody reads.

This is the post-landing pass. Three jobs, in order of how easy they are to get wrong.

## What is actually in this folder

Notes are branch-local: `.branch-notes/<branch>.md` exists on `<branch>` and nowhere else. It
reaches the integration branch only by merging, which means **almost everything here came from a
branch that landed.** The folder is not a graveyard of abandoned work; it is a record of shipped
work whose branches have since been deleted.

That inverts the instinct. A file for a branch nobody recognizes is not litter — it is the
reasoning behind code currently running in production, sitting at peak usefulness at exactly the
moment it looks like garbage. Deleting is the rare operation here. Archiving is the normal one.

A note can only reach the integration branch without landing through unusual paths: someone ran
capture on the integration branch directly, or the work merged and was later reverted. Both are
worth reporting rather than sweeping.

## Invocation

```
/reconcile-notes                # classify against local AND remote — the safe default
/reconcile-notes --remote       # remote only; the sensible setting for a shared repo
/reconcile-notes --local        # local only — dangerous, see below
/reconcile-notes --delete       # also act on never-landed notes, after confirming each
/reconcile-notes --dry-run      # classify and report, archive nothing
```

The default requires a branch to be absent from **both** local and remote before its note is
touched. `--remote` is the closer proxy for what a team considers real and is the right setting
in a shared repo where nobody keeps every branch locally.

`--local` is the one that will hurt you. Local branches are a small subset of what exists —
someone who has just cloned has exactly one — so classifying against local alone marks nearly
every note as gone and archives the entire folder while appearing to work perfectly. Require an
explicit confirmation for it, and state the count it's about to touch before doing anything.

`--dry-run` exists because this skill archives without asking. It's the escape hatch for anyone
who wants to see the classification first, and it should be mentioned in the output the first
time the skill runs in a repo.

## Run it on the integration branch

```bash
git fetch --all --prune
BASE_REF=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
[ -z "$BASE_REF" ] && for c in main master trunk develop; do
  git show-ref -q --verify "refs/remotes/origin/$c" && { BASE_REF=$c; break; }
done
[ "$(git rev-parse --abbrev-ref HEAD)" = "$BASE_REF" ] || echo "not on $BASE_REF — stop"
```

If `BASE_REF` can't be resolved at all, stop and ask rather than falling through — this skill classifies notes as landed-or-not against it, and an empty value would classify everything as never landed on a skill whose whole job is not to lose those files.

On a feature branch this would archive notes for work that hasn't landed from where you're
standing. Check, and stop if it doesn't hold.

`--prune` is what makes the rest work. Without it, deleted remote branches still appear to exist
and nothing is ever classified as gone.

## 1. Classify

```bash
find .branch-notes -name '*.md' -not -path '*/_archive/*' -not -name '_*.md' \
  | sed 's|^\.branch-notes/||; s|\.md$||'
```

Both exclusions are load-bearing. Branch names contain slashes, so `feature/rate-limit` lives at
`.branch-notes/feature/rate-limit.md`; a flat `basename` would collide it with `hotfix/rate-limit`.
And nothing matching `_*.md` is ever classified — the underscore prefix marks a file as permanent.

For each note, its branch is in one of four states:

```bash
git rev-parse --verify "$branch"        2>/dev/null   # exists locally
git rev-parse --verify "origin/$branch" 2>/dev/null   # exists on remote
git branch -r --merged "origin/$BASE_REF" | grep -q "origin/$branch"
```

- **Live** — exists locally or on remote. Leave alone, always.
- **Landed** — gone, and its commits are in the integration branch. **Archive.**
- **Unknown** — gone, merge status undeterminable. Squash merges look unmerged because the
  commits don't survive verbatim, so this is a large category in most repos. **Archive.**
- **Never landed** — gone, and nothing from it is reachable. Rare, per the section above.
  **Confirm before deleting.**

Where a note records a merge commit or a pull request number, use it — that resolves Unknown to
Landed directly, and is worth checking before falling back to the default.

Default to the safe intersection: a branch must be absent from **both** local and remote before
its note is touched. Local branches are a small subset of what exists — someone who has just
cloned has one — so classifying against local alone would sweep nearly the entire folder while
appearing to work correctly.

## 2. Archive, and only archive

Landed and Unknown are archived automatically. This is the one place in git-intent that applies
rather than proposes, and the exception is narrow on purpose:

- it moves markdown inside `.branch-notes/`, never source
- `git mv` keeps the content tracked and the history intact — nothing is destroyed
- it is the overwhelmingly common path, and a proposal nobody executes leaves a chore after
  every single merge, which is how the folder rots in the first place

```bash
mkdir -p .branch-notes/_archive/feature
git mv .branch-notes/feature/rate-limit.md .branch-notes/_archive/feature/rate-limit.md
```

Mirror the path so files stay findable by branch name later, when someone asks why a piece of
code exists.

**Stage the moves; do not commit them.** The human commits, having seen `git status`, and the
undo is one command. Print it:

```bash
git reset && git checkout -- .branch-notes/    # undo everything this did
```

Commit housekeeping on its own. Mixing it into a feature commit makes both harder to review.

## 3. Deleting requires a yes

Never-landed notes are listed, never removed on your own initiative. Show what would go and
what makes it look abandoned, and wait for an explicit answer.

The asymmetry is the entire argument. An extra file in `_archive/` costs a few kilobytes. A
deleted note destroys reasoning that exists nowhere else — not in the diff, not in the history,
not in anyone's memory. **When in doubt, archive.** Any ambiguity resolves toward keeping.

Never delete a live branch's note even if the branch looks stale. A branch quiet for two months
may be paused rather than dead, and its author will have no idea why their context vanished.

## 4. Invalidate the baseline, and say what it got wrong

```bash
INTENT="$(git rev-parse --git-common-dir)/intent"
ANCHOR=$(sed -n 's/^Generated at: \([0-9a-f]*\).*/\1/p' "$INTENT/base.md" 2>/dev/null)
git diff --stat "$ANCHOR"..HEAD
git diff --name-only "$ANCHOR"..HEAD | awk -F/ 'NF>1 {print $1"/"$2}' | sort -u
```

The cache is regenerable, so invalidating it is free — delete it, or run `/baseline-scan`. What is not
free, and what makes this step worth doing here rather than lazily on next read, is naming the
contradictions while the landing that caused them is still in view:

- an area the baseline called dormant that this landing touched
- a directory that now exists and isn't in the recorded structure
- a test or build command that moved in CI config
- a `CODEOWNERS` or `.gitattributes` change, which is policy and deserves a human's eye

Report these. Don't fix them by hand — regenerate.

## Output

```
.branch-notes/ on main — 47 notes, 14 classified
baseline cache: a3f21c8, 84 commits behind

ARCHIVED (applied, staged, not committed)
  feature/rate-limit.md        landed 3 weeks ago
  fix/timezone-parsing.md      landed 6 weeks ago
  feature/csv-import.md        squash-merged, inferred from PR #412 in note
  ... 9 more

KEEP (branch still live)
  refactor/payments-v2.md      active on remote, last commit 2 days ago

NEEDS A DECISION — never landed, nothing will delete these without your say-so
  spike/graphql-poc.md         branch gone, no commits reachable from main
    Note records 3 dated decisions including a rejected schema approach.
    Deleting loses them. Archiving costs nothing.

BASELINE CONTRADICTED
  "src/legacy/ — dormant 2y" — 11 commits touched it in this range
  src/webhooks/ exists and is not in the recorded structure
  Lint command moved: ruff → ruff check --fix (.github/workflows/ci.yml)

  Regenerate:  /baseline-scan

To commit:  git commit -m "chore: archive landed branch notes"
To undo:    git reset && git checkout -- .branch-notes/
```

If `_base.md` still exists as a committed file, say so — it is the pre-cache layout, and its
presence means some skills are reading a stale committed copy while others read the cache.

## Judgment

**When in doubt, archive.** Restated because it is the only rule here that matters. Every
ambiguous classification resolves toward keeping the file.

**Consider not deleting at all.** These are small text files. A repo with two hundred of them
has a folder that is slightly untidy, not a problem. If the motivation is aesthetic rather than
practical, archiving everything and deleting nothing is a defensible policy — say so when the
delete list is short, which it usually is.

**Archived notes are inputs, not sediment.** `release-notes` reads them for why each change
happened; `onboard-file` reads them for why a file is shaped this way. The archive is the reason
capture is worth doing at all, and treating it as a bin to be emptied defeats the system.

**Never write policy.** A `CODEOWNERS` or `.gitattributes` change spotted here is reported to a
human. Automated bookkeeping that could quietly alter merge policy would be the most dangerous
thing in this repo.
