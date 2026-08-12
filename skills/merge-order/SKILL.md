---
name: merge-order
description: Work out which pending branches or pull requests depend on which, so the same conflict isn't resolved four times. Use this when several branches are queued to merge, when a refactor is competing with feature work, before a release cut, or when the user asks what to merge first or in what order. Reports dependencies and expected friction rather than prescribing a sequence.
---

# merge-order

Merging a queue in arrival order means every branch rebases onto every earlier branch's surprises. Merging the structural change first means everything else rebases onto it once.

That's the whole insight, and it's worth about ten minutes. But a tool that emits a numbered sequence gets ignored the moment someone's PR is approved and sitting at the bottom of it — the sequence is advisory, the approval is real, and advisory loses.

So this reports **what depends on what, and why**. A dependency survives being ignored, because it's a fact about the code rather than a plan for the week. Someone who merges out of order at least knows what they've bought.

## Invocation

```
/merge-order                              # branches active in the last 10 days
/merge-order feature/a feature/b hotfix/c # exactly these, in any order
/merge-order --since 30d                  # widen the activity window
/merge-order --target release/2.4         # queue aimed at a release branch
```

Naming branches explicitly is the common case before a release cut, when the queue is whatever is approved rather than whatever is recent. Say which set you used either way — a scan that quietly omitted an approved PR is worse than one that took longer.

**This one grows quadratically, so bound the queue before starting.** Step 3 compares every pair: ten branches is 45 comparisons, forty is 780. Above roughly a dozen branches, report the count and ask which ones are actually queued rather than analyzing a fortnight of activity that nobody intends to merge this week.

That question is a fair one to ask here, unlike almost everywhere else in git-intent, because the answer isn't in the repository. Git knows which branches exist; it has no idea which are approved, which are waiting on review, or which the author has quietly given up on. A merge queue is a social fact.

## Workflow

### 1. Collect the queue

```bash
git fetch --all --prune
TARGET="${TARGET:-$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')}"
[ -z "$TARGET" ] && for c in main master trunk develop; do
  git show-ref -q --verify "refs/remotes/origin/$c" && { TARGET=$c; break; }
done
git for-each-ref --sort=-committerdate refs/remotes/origin \
  --format='%(refname:short) %(committerdate:relative) %(authorname)'
```

Take the branches the user named, or those active in the last 10 days and not already merged into the target. State which set you used.

### 2. Characterize each branch

```bash
for branch in $QUEUE; do
  BASE=$(git merge-base "origin/$branch" "origin/$TARGET")
  git diff --name-only "$BASE..origin/$branch"
  git diff -U0 "$BASE..origin/$branch" | grep '^@@'
  git show "origin/$branch:.branch-notes/$branch.md" 2>/dev/null
done
```

Each note lives on its own branch, so reading the queue's notes means `git show <ref>:<path>` — a `cat` finds nothing but the current branch's own note, and returns silence for the rest.

Sort each into a kind, because kind predicts blast radius better than size:

- **Structural** — moves, renames, extracts, signature changes. Wide surface, little behavior. Everything that touches the moved code has to follow it.
- **Interface** — schema, API route, config key, shared type. Callers in branches that don't otherwise overlap.
- **Contained** — behavior inside existing boundaries. Conflicts only with branches touching the same lines.
- **Mechanical** — formatting, lockfiles, generated output. Conflicts constantly, means nothing.

### 3. Find the real dependencies

Cut the pair count before doing this. Two branches with no shared file cannot have an ordering constraint, so the only pairs worth examining are those whose path sets intersect — which is a set operation over data step 2 already collected, not another pass over git:

```bash
# only compare pairs that share at least one path
comm -12 <(sort "$paths_a") <(sort "$paths_b") | head -1
```

On a real queue this removes most of the pairs, because most branches are independent. Report how many pairs survived — "18 of 45 pairs share a file" tells the reader why the answer came back mostly empty.

For each surviving pair, the question isn't whether they overlap — it's whether one *has* to precede the other:

- B edits a symbol A relocates → **A first**, or B's edit has to be replayed onto a location that doesn't exist yet.
- B calls an interface A changes → **A first**, or B merges green against a signature that's about to vanish.
- Both append independently to the same file → **no dependency**, just a textual conflict either way.
- Neither touches the other's surface → **independent**, and it's worth saying so, because a queue with three independent branches doesn't need this skill's output at all.

A directed order between two branches is only real in the first two cases. Everything else is a preference, and should be labelled as one.

### 4. Check each branch's assertions against the others

The first two cases above are inferences. Where the queued branches carry assertions, they stop being inferences and become a check — this is the only place in git-intent where one branch's testimony is evaluated against another branch's code, and it is what the whole assertion layer was building toward.

Take each queued note's live assertions (skip anything another entry supersedes) and resolve **the anchor only** against every other queued branch's tip:

```bash
# does rate-limit's anchor src/client.py:dispatch survive payments-v2?
git grep -qw -e dispatch "origin/refactor/payments-v2" -- src/client.py
git cat-file -e "origin/refactor/payments-v2:src/client.py" 2>/dev/null   # file still there at all?
```

**Resolve the anchor, never the predicate.** The other branch's tree does not contain this branch's change — `RateLimiter` isn't in payments-v2 because rate-limit hasn't merged — so evaluating the full check against a sibling reports a violation for every assertion in the queue. The anchor is the part that exists in the shared base, which is exactly why it's the part that can be disturbed.

Two outcomes:

- **Anchor survives** — that branch does not move this claim's ground. No constraint from this assertion.
- **Anchor does not resolve** — the other branch renamed, extracted, or deleted what this claim is anchored to. **This branch merges first**, or its claim has to be re-established by hand during the second merge, by whoever is resolving a conflict and has never read the note.

That second case is `merge-order`'s central heuristic — *B edits a symbol A relocates → A first* — arriving as a fact instead of a reading of the diff. Report it as such, and quote the assertion's `why:` line: "these two branches share a file" is arguable, and "payments-v2 dissolves the anchor rate-limit's limiter depends on, and the note says a version that only limits first attempts passes tests" is not.

Where a branch has no note, or a note with no assertions, say so. Zero constraints found and zero constraints checkable look identical in a queue report and mean opposite things.

### 5. Report

```
Queue: 5 branches into dev
baseline cache: a3f21c8 · 3 of 5 branches have notes

DEPENDENCIES

  refactor/payments-v2 → feature/rate-limit                    [assertion]
    v2 extracts dispatch() into PaymentDispatcher. rate-limit wraps dispatch().
    rate-limit a1 anchors on src/client.py:dispatch, which does not resolve at
    v2's tip — "the limiter has to wrap retries, not just first attempts".
    If rate-limit merges first, its limiter has to be relocated by hand during
    the second merge, and a version that only limits first attempts will pass
    tests. Real ordering constraint.

  refactor/payments-v2 → fix/timeout-handling
    Same extraction; timeout-handling edits the same function body.

NO CONSTRAINT

  feature/csv-import      independent — no shared files
  chore/bump-deps         lockfile only; conflicts with everything, resolve by
                          regenerating whichever lands second
  feature/csv-import      no note — 0 constraints checkable, not 0 found

EXPECTED FRICTION

  refactor/payments-v2 is 41 files and has been open 3 weeks. Whatever merges
  after it rebases across the extraction. If it can't merge in the next few
  days, merging the contained branches first and rebasing v2 once is the
  cheaper trade — one painful rebase for its author instead of three small
  ones spread across three people.

Suggested: payments-v2, then rate-limit and timeout-handling in either order.
csv-import and bump-deps any time.
```

The friction section is what makes this usable. A bare ordering says nothing about what happens when reality doesn't cooperate, and reality usually doesn't — the long-lived refactor is exactly the branch most likely to be blocked on review.

## Judgment

**Say when there's no constraint.** Most queues are mostly independent. Reporting "three of these five can merge in any order" is a real result and prevents the ceremony from spreading to cases that don't need it.

**Age is a cost, not a priority.** A three-week-old refactor should probably go first because everything rebases across it once — not because it has waited longest. Say which reason applies.

**Don't arbitrate.** Whose branch waits is a decision about people's time and a release date, and the tool doesn't know either. Name the trade and stop.

**Recheck after each merge.** Every merge changes the target, and dependencies computed against the old target go stale immediately. This is cheap to re-run; treat it as a per-merge check rather than a plan for the week.