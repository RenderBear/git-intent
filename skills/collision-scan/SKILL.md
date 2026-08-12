---
name: collision-scan
description: Find out who else is working in the same code before conflicts become expensive — which parallel agents and which live branches share files and symbols with yours, what each side is trying to do, and which overlaps are worth a conversation now. Use this when starting a feature, returning to a long-running branch, before a rebase or a large refactor, when running several agents in parallel, or whenever the user asks who else is touching a file or what else is in flight. Also use when a branch has been open more than a week, since divergence compounds quietly.
---

# collision-scan

A merge conflict is a scheduling failure. The overlap existed the day both branches started; git just doesn't mention it until the cost of fixing it has multiplied.

The output is not a warning. It's the information needed for a five-minute conversation — or, when the other side is an agent you started, for a decision you can act on before it has finished writing.

## What this skill is not

**Overlapping paths only.** This skill compares work that touches the same files and symbols. Two branches changing *related meaning* in files that never touch is `semantic-scan`'s job, and the two divide cleanly on that line:

| | Looks at | Question |
|---|---|---|
| `collision-scan` | paths that **intersect** | will these collide when they land |
| `semantic-scan` | paths that are **disjoint** | did they break each other without colliding |

So this skill never chases callers, never reasons about contracts, and hands off when it sees one: a branch changing a signature that another branch calls in a file it doesn't touch is a `semantic-scan` finding, and the right output is one line saying so.

## Two populations, scanned in order

Local worktrees and remote branches are different questions with different urgency, and merging them into one severity list loses that.

**Stage 0 — local worktrees.** Agents running *now*, in the next room, with uncommitted work. Actionable in seconds: you can stop one. Costs three commands total and runs first.

**Stages 1–3 — remote branches.** Work that exists but isn't moving this minute. Ranked, capped, reported as a funnel.

Report them as separate sections. "Two agents are in your files right now" and "a branch from last week overlaps" demand different reactions.

## Cost, and where the cap belongs

| Stage | Cost per branch | What it does |
|---|---|---|
| 0. Worktrees | three commands, total | catch parallel agents, including uncommitted work |
| 1. Liveness | one `for-each-ref`, batched | rank branches by how alive they are |
| 2. Overlap | two git commands | drop branches sharing no file with yours |
| 3. Intent | a diff read plus reasoning | the actual work, and ~100× stage 2 |

Stages 0–2 stay uncapped — cheap enough to run over everything, and running them over everything is what lets the scan promise it didn't miss anybody. **The cap belongs on stage 3**, ranked by overlap strength, never by recency.

That ranking is the important part. Recency is a bad proxy for relevance: a branch quiet for nine days that rewrites `dispatch()` matters far more than ten branches that touched the README this morning. Recency tells you whether the author is *around to talk to* — which matters once you have a finding, and predicts nothing about whether there is one.

Every stage reports its own funnel. A branch dropped without mention is worse than a slow scan.

## Invocation

```
/collision-scan                  # worktrees, then live remote branches
/collision-scan --local          # stage 0 only — parallel agents, nothing remote
/collision-scan --live 40        # rank remote branches, take top 40 (default 30)
/collision-scan --live all       # every branch, no liveness cut
/collision-scan --limit 25       # analyze more overlaps (default 10)
/collision-scan --count          # the funnel, nothing expensive
/collision-scan origin/dev       # against a different target
```

`--count` runs stages 0–2 and stops, so you see how many branches actually overlap before committing to the expensive part. On a large repo it is often all anybody needed.

`--limit` caps stage 3 only. Branches past the cap are **named in the output**, not hidden.

## Workflow

### 0. Local worktrees — parallel agents, first and cheapest

```bash
git worktree list --porcelain
```

For each worktree other than this one, take its `HEAD` and `branch`, then read what it is actually doing — which for live agent work means the **uncommitted** state, not the branch diff:

```bash
git -C "$WT" status --porcelain             # modified, staged, and untracked
git -C "$WT" diff --name-only "$BASE"       # committed on that branch
```

The first is the reason this stage exists. An agent three minutes into a task has written files and committed nothing; no remote scan will ever see that work, and it is the work most cheaply redirected.

`status --porcelain`, not `diff --name-only HEAD` — a file the agent created and never added is **untracked**, and a diff against `HEAD` does not list it. That is most of what three minutes of work looks like, so the diff form misses exactly the population this stage exists to find.

Report worktrees separately and first:

```
PARALLEL AGENTS — 3 other worktrees

  ../wt-payments  refactor/payments-v2   src/client.py
    12 files, uncommitted. Both touching dispatch().
    Nothing has been committed — cheapest possible moment to redirect one.

  ../wt-csv       feature/csv-import     src/config.py
    clean tree, 4 commits ahead. Distant regions.

  ../wt-docs      docs/api-notes         no overlap
```

An uncommitted overlap has no note to read and no commits to reason from, so intent comes from the diff and gets labelled as inferred. Say so — this is the one population where testimony is structurally unavailable.

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

### 2. Rank remote branches by liveness, then cut

```bash
git fetch --all --prune
git for-each-ref --sort=-committerdate refs/remotes/origin \
  --format='%(refname:short)|%(committerdate:unix)|%(authorname)'
git rev-list --left-right --count "origin/$TARGET...origin/$branch"
```

A date window alone is the wrong filter — it drops a nine-day-old branch that rewrites your function and keeps a branch that got a README typo fix this morning. Rank instead, on signals that are all one command each:

- **Recency** of the last commit
- **Volume** — commits ahead of the target
- **Divergence** — commits behind, because a branch far behind will conflict with more than its own diff suggests
- **Not landed** — exclude branches already merged into the target

Take the top `--live N`, default 30, or `--live all` to skip the cut.

The cut is a budget, not a claim about relevance — so the count below the cut is reported, and any branch below it that shares a path with you is named as a footnote even though it wasn't ranked in. That footnote is what stops the parked two-month refactor from disappearing.

### 3. Intersect paths — cheap, before anything expensive

```bash
for branch in $LIVE; do
  THEIR_BASE=$(git merge-base "origin/$branch" "origin/$TARGET")
  git diff --name-only "$THEIR_BASE..origin/$branch"
done
```

Keep only branches sharing at least one path with yours. Everything else is reported as a count and nothing more.

Two exclusions from the overlap signal, or every branch matches every branch:

- Lockfiles, generated directories, and anything `git check-attr merge -- <path>` reports as `-merge`. Everyone touches `package-lock.json`; it predicts nothing.
- Files with very high change frequency across all branches — a shared constants or barrel file that ten branches append to is noise, and appears as a single grouped line rather than ten findings.

Path intersection is also what `semantic-scan` needs, inverted. The baseline cache at `$(git rev-parse --git-common-dir)/intent/` holds the per-branch path lists so the second skill to run doesn't recompute them.

### 3b. Report the funnel before spending anything

Stages 0–3 are cheap and now complete, so the true scale is known before the expensive part starts. Print it:

```
  3 local worktrees                            2 overlap
312 branches on origin
 30 live — ranked by recency, volume, divergence
 14 share a file with feature/rate-limit      16 no overlap
  8 of those also share a symbol
```

Each line accounts for the one above it. Numbers that don't reconcile are how a reader learns not to trust the "no overlap" line.

If the overlap count exceeds `--limit`, say what will be deferred **before** starting rather than after. Above roughly 25, say plainly that the run will be slow and let the user narrow the target or raise the limit. A scan that silently takes four minutes gets interrupted; one that says "this will take a few minutes, 31 branches overlap" gets waited for.

### 4. Reconstruct intent, only for what's left

Rank the overlapping branches, strongest signal first:

1. **Same symbol** — the hunk headers from step 1 intersect. These justify the skill.
2. **Same file, adjacent regions** — within ~50 lines.
3. **Same file, distant regions** — git will merge it; worth a line, not an analysis.

Take `--limit` branches from the top. For each:

```bash
git show "origin/$branch:.branch-notes/$branch.md" 2>/dev/null
git log --oneline "$THEIR_BASE..origin/$branch"
git diff "$THEIR_BASE..origin/$branch" -- <shared paths>
```

`git show`, not `cat`. Their note lives on their branch, not in your worktree — a `cat` returns nothing, silently, and the scan proceeds on inference while believing it read testimony.

The finding you're after is not "both changed `dispatch()`". It's the pair of intentions and how they interact: one wraps it, one relocates it, and the wrap has to move with it.

### 5. Classify

- **HIGH** — same function or symbol. The resolution requires knowing both intents; a textual merge will produce something that compiles and is wrong.
- **MEDIUM** — same file, different regions. Git resolves it. Worth knowing, not worth interrupting anyone.
- **LOW** — same subsystem, no shared file. One line, so nobody is surprised later.
- **HANDOFF** — one side changes a symbol the other calls from a file neither shares. Not this skill's finding. Name it and point at `semantic-scan`.

Directional consequence matters more than severity. Say what happens *if theirs lands first*, and what happens if yours does — that's what turns the finding into a decision about ordering.

### 6. Report

```
feature/rate-limit vs origin/main

  3 local worktrees                            2 overlap
312 branches on origin
 30 live — ranked by recency, volume, divergence
 14 share a file with this branch              16 no overlap
 10 analyzed — symbol overlap first             4 deferred, listed below

PARALLEL AGENTS
  ../wt-payments  refactor/payments-v2  src/client.py — uncommitted, 12 files
    Both touching dispatch(). Nothing committed yet on either side.
    Intent inferred from the working tree; no note exists to read.

HIGH — same function
  refactor/payments-v2 (sam, 2 days ago)
    src/client.py — both modifying dispatch()
      yours:  wraps dispatch in a token-bucket limiter
      theirs: extracts dispatch into a PaymentDispatcher class
    If theirs lands first, your limiter needs to move with it.

MEDIUM — same file, different regions
  feature/csv-import (dana, 5 days ago)
    src/config.py — both adding keys, ~40 lines apart.

HANDOFF — no shared file, possible contract break
  feature/webhooks changes validate_charge()'s error behaviour; this branch
  adds two callers in importer.py. Different files, so it will merge clean.
  → /semantic-scan feature/webhooks feature/rate-limit

CLEAN — analyzed, nothing to flag
  8 branches share a file but their changes don't interact.

DEFERRED — overlap, not analyzed (--limit 10 reached; --limit 14 for all)
  chore/rename-utils     src/config.py       distant regions
  docs/api-notes         src/client.py       comment block only
  spike/cache-poc        src/client.py       same file, no shared symbol
  test/fixtures-refresh  src/config.py       distant regions

BELOW THE LIVENESS CUT but touching your files
  spike/retry-backoff (6 weeks ago) — src/client.py
```

Name the author and the recency. The action this produces is a conversation with a person, and a finding that doesn't say who to talk to leaves the reader to look it up.

The funnel and the DEFERRED block do the same job from opposite ends: together they account for every branch, so the reader can tell "nothing else overlaps" from "nine other things overlap and I stopped looking".

## Judgment

**Worktrees first, always.** They are the cheapest stage and the most actionable finding, because uncommitted work can be redirected rather than merged. On a machine running parallel agents this is most of the value.

**Rank by overlap, cap by overlap — never by recency.** Recency belongs in the liveness cut, which is a budget, and nowhere else.

**Account for every branch.** The funnel plus the deferred list plus the below-cut footnote should sum to the branch count.

**Don't inflate.** If nothing overlaps, say that in one line. A scan that manufactures MEDIUMs to look useful gets skipped within a fortnight, and then the one real HIGH is skipped too.

**Hand off rather than half-doing it.** The moment a finding is about a caller in a file neither branch shares, it belongs to `semantic-scan`. Reasoning about contracts here duplicates that skill badly and makes both less trustworthy.

**This is not a gate.** It surfaces overlap and stops. Who rebases, who waits, whether the refactor lands first — those are calls for the people involved.

**Fork-based workflows are blind spots.** Contributor branches on forks aren't on your remote and won't be scanned. Say so rather than reporting "no overlap", which is a materially different claim from "nothing I can see".