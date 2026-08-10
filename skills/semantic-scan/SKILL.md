---
name: semantic-scan
description: Find the conflicts git never reported — one branch changes a function's contract while another adds or modifies a caller depending on the old behavior, in different files, with no conflict markers, merging green and failing later. Use this after a merge that resolved suspiciously cleanly, before a release cut, when tests pass but something feels off after integrating branches, or when the user asks what a merge might have broken silently.
---

# semantic-scan

Git's conflict detection is textual and local. Two branches editing the same lines conflict; two branches editing *related meaning* in different files do not. The second case is more dangerous precisely because nothing stops to tell you.

The shape is always the same: one side changes what a function guarantees, the other side adds or modifies code depending on the old guarantee, the files never touch, the merge is clean, the test suites were written against their own branches and both pass.

This finds those. It doesn't fix them — the fix is a code change with a decision in it.

## Invocation

```
/semantic-scan                          # the most recent merge commit
/semantic-scan 4a1f9c2                  # a specific merge
/semantic-scan branch-a branch-b        # a pair that hasn't merged yet
/semantic-scan v2.3.0..HEAD             # every merge in a range, before a release cut
```

The two-branch form is the one worth reaching for deliberately: it runs *before* the merge, when the finding is still cheap. The default form runs after, which is when people think to ask.

A range is expensive — it's one scan per merge — so report how many merges it covers before starting, and take them newest first so an interrupted run has still covered the ones most likely to matter.

## Workflow

### 1. Establish the two sides of the merge

```bash
git log --merges -1 --format='%H %P'          # the merge commit and its parents
MERGE=<sha>; P1=<parent1>; P2=<parent2>
git diff --name-only $P1..$MERGE
git diff --name-only $P2..$MERGE
```

For an unmerged pair, use the merge base instead:

```bash
BASE=$(git merge-base branch-a branch-b)
git diff --name-only $BASE..branch-a
git diff --name-only $BASE..branch-b
```

The interesting set is where those two file lists **don't** intersect. Overlapping files already conflicted and someone already looked at them.

### 2. Extract contract changes from side A

A contract change is anything that alters what callers can rely on, whether or not the signature moved:

- Signature: parameters added, removed, reordered, or retyped; defaults changed
- Return: type, shape, nullability, or the meaning of a sentinel value
- Errors: what's raised, what's swallowed, what's now raised that wasn't
- Side effects: something that used to write, lock, retry, or cache, and now doesn't — or now does
- Invariants: ordering, idempotency, thread safety, whether a collection is sorted
- Semantics of unchanged signatures: a validator that starts rejecting empty strings, a limit that starts counting retries

The last category is where the real damage lives. A changed signature breaks the build and gets found; a function that keeps its shape and changes its meaning does not.

```bash
git diff $BASE..branch-a -- <changed files>
git diff -U0 $BASE..branch-a | grep '^@@'                    # enclosing symbols, cheap
git show branch-a:.branch-notes/branch-a.md 2>/dev/null      # what it was trying to do
```

The note lives on the branch it describes, so it is read through the ref. After a merge it has usually been archived, so try `.branch-notes/_archive/branch-a.md` on the integration branch too.

The branch note's "must survive a conflict" line often names the invariant directly, which is faster and more reliable than inferring it.

### 3. Find dependents introduced by side B

For each changed contract, look for callers that side B added or modified:

```bash
git grep -n 'dispatch(' $P2 -- '*.py'
git diff $BASE..branch-b -- $(git grep -l 'dispatch(' $P2)
```

Two categories, and the second is easy to miss:

- **New callers** — side B added code calling the changed symbol. Check against the new contract.
- **Modified callers** — side B changed existing call sites in ways that assume the old behavior. These look fine in isolation because they were fine when written.

Indirect dependents count. If side B's new code calls something that calls the changed function, the dependency is real even though it doesn't appear in a grep for the symbol.

### 4. Report findings with confidence

Every finding needs both sides shown, or it isn't checkable:

```
Scanned merge 4a1f9c2 — refactor/payments-v2 + feature/rate-limit
14 files from each side, no overlap. 3 contract changes examined.

LIKELY BROKEN
  dispatch() no longer retries internally (client.py:L61, from payments-v2)
    Retry moved up into PaymentDispatcher.send().
  feature/rate-limit added a limiter inside dispatch (client.py:L88)
    assuming retries pass through it. They no longer do.
    Effect: retries bypass the rate limiter entirely. Passes both suites —
    neither covers retry-under-limit.

WORTH CHECKING
  validate_charge() now rejects empty metadata (models.py:L204)
    csv-import constructs charges with metadata={} in two places
    (importer.py:L77, L112). May be intentional; may not.

NOT DETERMINABLE
  Config loading order changed in both branches. Whether the composed order
  is correct depends on deployment environment behavior that isn't in the
  repo. Flagging rather than guessing.

COVERAGE
  Dynamic dispatch not analyzed: 3 call sites go through getattr() in
  handlers.py. Anything reached that way was not checked.
```

The last two sections matter as much as the first. A silent false negative is this skill's characteristic failure — the whole premise is that dangerous things leave no trace — so what *wasn't* examined has to be visible. Reflection, dynamic dispatch, string-keyed registries, serialized call graphs, and anything crossing a network boundary are all outside what static reading can see, and a report that doesn't say so implies a completeness it doesn't have.

## Judgment

**Show both sides, always.** "This might be broken" without the two specific locations is unactionable, and after two of those the report stops being read.

**Rank by silence, not severity.** A break that fails loudly on the next test run costs an hour. A break that passes both suites and surfaces in production is the reason to run this. Lead with the ones nothing else will catch.

**Deletions are the highest-yield input.** Reviewers skim deletions and git never conflicts a deletion against a distant caller. When one side removed something, check what the other side started depending on.

**Say when nothing was found.** "Three contract changes, no dependents introduced by the other side" is a real result. Manufacturing findings to justify the run is how the section gets skipped when it eventually matters.

**A finding is a question, not a fix.** Whether the new contract or the old caller is right is a decision about the requirement. Present it; don't resolve it.