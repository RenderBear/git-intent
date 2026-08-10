---
name: collision-scan
description: Find out who else is working in the same code before conflicts become expensive — which active branches overlap with yours, what each side is trying to do, and which overlaps are worth a conversation now. Use this when starting a feature, returning to a long-running branch, before a rebase or a large refactor, or whenever the user asks who else is touching a file, whether a change will conflict, or what else is in flight. Also use when a branch has been open more than a week, since divergence compounds quietly.
---

# collision-scan

A merge conflict is a scheduling failure. The overlap existed the day both branches started; git just doesn't mention it until the cost of fixing it has multiplied. 

The output is not a warning. It's the information needed for a five-minute conversation: what each side is doing, and what has to change if the other one lands first.

## Scoping, and why it's three stages

The naive version — read every branch, reason about each — is unusable on any repo big enough to need it. A monorepo with three hundred open branches would mean three hundred diffs and three hundred intent reconstructions to surface the two that matter.

The stages exist because they cost wildly different amounts:

| Stage | Cost per branch | What it does |
|---|---|---|
| 1. Activity | one `for-each-ref`, batched | drop branches nobody has touched |
| 2. Overlap | two git commands | drop branches that share no file with yours |
| 3. Intent | a diff read plus reasoning | the actual work, and ~100× stage 2 |

So stages 1 and 2 stay uncapped — they're cheap enough to run over everything, and running them over everything is what lets the scan promise it didn't miss anybody. **The cap belongs on stage 3**, and it is ranked by overlap strength, never by recency.

That ranking is the important part. Recency is a bad proxy for relevance: a branch quiet for nine days that rewrites `dispatch()` matters far more than ten branches that touched the README this morning. A cap on stage 1 would drop the first one silently, which is the exact failure this skill's design refuses.

Every stage reports its own funnel. A branch dropped without mention is worse than a slow scan.

## Invocation

```
/collision-scan                  # active branches, against the current branch
/collision-scan --since 30d      # widen the activity window (default 10d)
/collision-scan --limit 25       # analyze more overlaps (default 10)
/collision-scan --count          # just the funnel, nothing expensive
/collision-scan --all            # ignore the activity window entirely
/collision-scan origin/dev       # against a different target
```

`--count` exists for the case where you don't know the shape of the repo yet. It runs stages 1 and 2 and stops, so you see how many branches actually overlap before committing to the expensive part.

`--limit` caps stage 3 only. Branches past the cap are **named in the output**, not hidden — the whole point is that you can see what was deferred and re-run with a higher limit if one of the names looks alarming.

The target sets the merge base each branch is measured from. It defaults to the repo's integration branch, resolved as below; pass one explicitly when your branch is aimed at a release branch rather than the trunk.

## Workflow

### 1. Establish your own change surface

```bash
TARGET="$1"
[ -z "$TARGET" ] && TARGET=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
[ -z "$TARGET" ] && for c in main master trunk develop; do
  git show-ref -q --verify "refs/remotes/origin/$c" && { TARGET=$c; break; }
done   # origin/HEAD is often unset; `git remote set-head origin -a` fixes it

BASE=$(git merge-base HEAD "origin/$TARGET")
git diff --name-only $BASE..HEAD
git diff -U0 $BASE..HEAD | grep '^@@'
```

The second command is the useful one. Git's hunk headers carry the enclosing function or class name, which gives symbol-level granularity for the price of a diff — no parsing, no language server. That's what separates "same file" from "same function", and the difference between those two is the difference between a note and a phone call.

### 2. Enumerate candidates

```bash
git fetch --all --prune
git for-each-ref --sort=-committerdate refs/remotes/origin \
  --format='%(refname:short) %(committerdate:relative) %(authorname)'
```

Default window: branches with commits in the last **10 days**. Adjust with `--since`; `--all` removes the filter.

Ten days is a proxy, not a truth. A refactor parked for two months still lands eventually, and its collision is worse for having aged. So the count of excluded branches stays in the output, and if any excluded branch touches a file you changed, name it as a one-line footnote even though it wasn't scanned.

Exclude the target branch itself, and exclude branches already merged into the target.

### 3. Intersect paths — cheap, before anything expensive

```bash
for branch in $CANDIDATES; do
  THEIR_BASE=$(git merge-base "origin/$branch" "origin/$TARGET")
  git diff --name-only "$THEIR_BASE..origin/$branch"
done
```

Keep only branches sharing at least one path with yours. Everything else is reported as a count and nothing more.

Two exclusions from the overlap signal, or every branch matches every branch:

- Lockfiles, generated directories, and anything `git check-attr merge -- <path>` reports as `-merge`. Everyone touches `package-lock.json`; it predicts nothing.
- Files with very high change frequency across all branches — a shared constants or barrel file that ten branches append to is noise, and appears as a single grouped line rather than ten findings.

### 3b. Report the funnel before spending anything

Stages 1 and 2 are cheap and now complete, so the true scale is known before the expensive part starts. Print it:

```
312 branches on origin
 47 with commits in the last 10 days        265 dormant
 14 share a file with feature/rate-limit     33 no overlap
  8 of those also share a symbol
```

Each line accounts for the one above it, so the two columns always reconcile: 265 + 47 = 312, and 33 + 14 = 47. Numbers that don't add up are how a reader learns not to trust the "no overlap" line.

This is the whole output of `--count`. On a large repo it is often all anybody needed — "fourteen branches touch my files" answers the question that prompted the run.

If the overlap count exceeds `--limit`, say what will be deferred **before** starting rather than after, and if it exceeds roughly 25, say plainly that the full run will be slow and let the user decide whether to narrow the target or raise the limit. A scan that silently takes four minutes gets interrupted; one that says "this will take a few minutes, 31 branches overlap" gets waited for.

### 4. Reconstruct intent, only for what's left

Rank the overlapping branches before spending anything on them, strongest signal first:

1. **Same symbol** — the hunk headers from step 1 intersect. These are the findings that justify the skill.
2. **Same file, adjacent regions** — within ~50 lines of each other.
3. **Same file, distant regions** — git will merge it; worth a line, not an analysis.

Take `--limit` branches from the top of that ranking. Never order this list by commit date: recency predicts whether someone is *around to talk to*, which matters for the conversation, and predicts nothing at all about whether their change collides with yours.

For each surviving branch:

```bash
git show "origin/$branch:.branch-notes/$branch.md" 2>/dev/null
git log --oneline "$THEIR_BASE..origin/$branch"
git diff "$THEIR_BASE..origin/$branch" -- <shared paths>
```

`git show`, not `cat`. Their note lives on their branch, not in your worktree — a `cat` returns nothing, silently, and the scan proceeds on inference while believing it read testimony.

Read the branch note if it exists — it says what they were trying to do, which is otherwise a reconstruction. Where there's no note, derive from the diff and say so.

The finding you're after is not "both changed `dispatch()`". It's the pair of intentions and how they interact: one wraps it, one relocates it, and the wrap has to move with it.

### 5. Classify

- **HIGH** — same function or symbol, or one branch changes a signature the other calls. The resolution requires knowing both intents; a textual merge will produce something that compiles and is wrong.
- **MEDIUM** — same file, different regions. Git resolves it. Worth knowing, not worth interrupting anyone.
- **LOW** — same subsystem, no shared file. Mentioned in one line, mostly so nobody is surprised later.

Directional consequence matters more than severity. Say what happens *if theirs lands first*, and what happens if yours does — that's what turns the finding into a decision about ordering.

### 6. Report

```
feature/rate-limit vs origin/main

312 branches on origin
 47 with commits in the last 10 days        265 dormant
 14 share a file with this branch            33 no overlap
 10 analyzed — symbol overlap first            4 deferred, listed below

HIGH — same function
  refactor/payments-v2 (sam, 2 days ago)
    src/client.py — both modifying dispatch()
      yours:  wraps dispatch in a token-bucket limiter
      theirs: extracts dispatch into a PaymentDispatcher class
    If theirs lands first, your limiter needs to move with it.

MEDIUM — same file, different regions
  feature/csv-import (dana, 5 days ago)
    src/config.py — both adding keys, ~40 lines apart.

CLEAN — analyzed, nothing to flag
  8 branches share a file but their changes don't interact.

DEFERRED — overlap, not analyzed (--limit 10 reached; --limit 14 for all)
  chore/rename-utils     src/config.py       distant regions
  docs/api-notes         src/client.py       comment block only
  spike/cache-poc        src/client.py       same file, no shared symbol
  test/fixtures-refresh  src/config.py       distant regions

DORMANT but touching your files
  spike/retry-backoff (6 weeks ago) — src/client.py
```

Name the author and the recency. The action this produces is a conversation with a person, and a finding that doesn't say who to talk to leaves the reader to go look it up.

The funnel at the top and the DEFERRED block do the same job from opposite ends: together they account for every one of the 312 branches, so the reader can tell the difference between "nothing else overlaps" and "nine other things overlap and I stopped looking".

## Judgment

**Don't inflate.** If nothing overlaps, say that in one line. A scan that manufactures MEDIUMs to look useful gets skipped within a fortnight, and then the one real HIGH is skipped too.

**Rank by overlap, cap by overlap — never by recency.** A branch untouched for nine days that rewrites the function you're wrapping outranks ten branches that edited the README this morning. Recency tells you whether the author is around to talk to, which matters once you have a finding and predicts nothing about whether there is one.

**Account for every branch.** The funnel plus the deferred list should sum to the branch count. Numbers that don't reconcile are how a reader learns not to trust the "no overlap" line.

**This is not a gate.** It surfaces overlap and stops. Who rebases, who waits, whether the refactor lands first — those are calls for the people involved, and a tool that recommends them will be wrong about the politics roughly half the time.

**Fork-based workflows are blind spots.** Contributor branches on forks aren't on your remote and won't be scanned. Say so rather than reporting "no overlap", which is a materially different claim from "nothing I can see".

**Run it more than once.** The scan is a snapshot and branches move. The second run, about a week in, catches the branch that started after yours — which is the one most likely to surprise you.