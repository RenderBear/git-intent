---
name: resolve-conflicts
description: Resolve conflicts from a merge, rebase, cherry-pick, revert, or stash pop by reconstructing what each side was trying to do, composing both intents where they are compatible, and verifying the result against both sides' tests. Use this whenever git reports unmerged paths, conflict markers exist in the working tree, or a merge or rebase has stopped. Requires an operation in progress with real conflicts — with a clean tree there is nothing to resolve and the skill says so and stops.
---

# resolve-conflicts

A conflict is two intentions colliding. Git shows the collision as text, because text is all it
has. Resolving the text without recovering the intentions is how functionality disappears: the
result compiles, the tests someone happens to run pass, and one side's work is quietly gone.

The default outcome should be a composition, not a choice. Most conflicts are two compatible
changes that happened to land on adjacent lines, and picking a side throws away half of a solved
problem for no reason.

**This skill proposes. It does not apply.** It produces the resolved content, the reasoning, and
the verification result. Writing it into the tree is a separate, human-authorized step.

## 0. Precondition — conflicts, or nothing

This skill has exactly one entry condition: **`git ls-files -u` is non-empty.**

```bash
git ls-files -u | head -1
```

Empty output means no unmerged paths, which means there is nothing here to do. Say so in one
line and stop. Do not predict conflicts, do not dry-run a merge, do not offer to look for future
problems — that is `collision-scan` before the fact and `semantic-scan` after it, and quietly
expanding into their territory is how three skills become one unfocused one.

Two adjacent states worth naming rather than acting on:

- **Clean tree, no operation.** Nothing to resolve. Point at `collision-scan` if the user was
  asking whether something *would* conflict.
- **Operation in progress, no conflicts left.** Everything is already staged. Say which
  continuation command finishes it and stop — that is not a resolution.

## Invocation

```
/resolve-conflicts                      # every unmerged path
/resolve-conflicts src/client.py        # one file, when the rest are trivial
/resolve-conflicts --other dev          # name the incoming branch when git can't
```

Everything else is read from repository state — which operation stopped, which refs are
involved, which paths are unmerged.

The one input worth passing is the incoming branch **name**, and only when the operation can't
yield it. A merge has `MERGE_HEAD` and a rebase has `head-name`, but a cherry-pick, a revert, or
a stash pop gives you a commit and no branch.

The flag is `--other`, deliberately not `--theirs`. This skill exists partly because `ours` and
`theirs` mean different things depending on the operation, so naming a flag after the ambiguous
term would import exactly the confusion the skill is built to remove. `--other` means one thing
in all five operations: the side whose work is coming in.

## 1. Establish which operation you are in — first, always

Five operations produce conflicts, and **`ours` and `theirs` do not mean the same thing across
them.** During a rebase they are inverted relative to a merge: your own commit is `theirs`.
Resolving with `--ours` out of merge habit while rebasing discards precisely the work you were
trying to keep, and the result looks clean.

```bash
G=$(git rev-parse --git-dir)
git rev-parse -q --verify MERGE_HEAD                        # merge
ls -d "$G/rebase-merge" "$G/rebase-apply" 2>/dev/null       # rebase
git rev-parse -q --verify CHERRY_PICK_HEAD                  # cherry-pick
git rev-parse -q --verify REVERT_HEAD                       # revert
```

`--git-dir`, not a literal `.git` — in a linked worktree `.git` is a file and every hardcoded
path fails.

| Operation | `ours` · `:2` | `theirs` · `:3` |
|---|---|---|
| merge | your current branch | the branch being merged in |
| **rebase** | **the upstream you are replaying onto** | **your own commit being replayed** |
| cherry-pick | your current branch | the commit being picked |
| revert | your current branch | the inverse of the reverted commit |
| stash pop | your working tree | the stashed changes |

For a rebase, the labels resolve to real refs:

```bash
R=$(git rev-parse --git-path rebase-merge)
cat "$R/onto" "$R/head-name" "$R/stopped-sha" 2>/dev/null
```

State the operation and what each side actually is before proposing anything. A reader who sees
"kept ours" has no way to know whether that was the upstream or the branch.

One setup change worth making first, since it puts the merge base directly in the conflict
markers where it is needed:

```bash
git config merge.conflictStyle zdiff3
```

## 2. Recover intent for both sides

Testimony where it exists, reconstruction where it doesn't, and **the output always says which**.

### Your side

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
cat ".branch-notes/$BRANCH.md" 2>/dev/null
```

### The other side — a ladder, not a lookup

The other side's note is not in your worktree. Which rung applies depends on what the other side
*is*, and the common case in a gitflow-shaped repo is that it is an integration branch, which
**never has a note of its own.** `develop` is not a unit of work; it is an accumulation of them.
There is nothing for `capture-diff` to have written and its absence is not a gap.

Walk down until something answers, and record which rung:

**1 — A feature branch with a note.**

```bash
git show "origin/$OTHER:.branch-notes/$OTHER.md" 2>/dev/null
```

`git show`, not `cat`. A `cat` returns nothing, silently, and the skill proceeds on inference
while believing it read testimony.

**2 — The archive.** This is the answer for `develop`, `main`, `release/*`, and for any branch
that already landed. An integration branch's intent is the set of branches that landed in it
since your fork point, each of which left a note behind when it was archived:

```bash
FORK=$(git merge-base HEAD "origin/$OTHER")
git log --merges --format='%s' "$FORK..origin/$OTHER"        # branch names from merge subjects
git show "origin/$OTHER:.branch-notes/_archive/<branch>.md" 2>/dev/null
```

Read only the archived notes for branches that touched the conflicted paths — usually one or
two out of fifteen. That subset is the incoming intent, and it is *better* testimony than a
single note would be, because each one was written by the person who made that specific change.

**3 — Commits only.** No note anywhere: cherry-picks, stash pops, branches predating the tool,
repos that never adopted it.

```bash
git log --oneline "$FORK..origin/$OTHER" -- <conflicted paths>
git log -1 --format=%B "$OTHER_SHA"
```

**4 — The diff alone.** Reconstruct from the change itself.

Rungs 3 and 4 are the normal case in most repos and produce a perfectly usable resolution — the
skill's value was never conditional on notes existing. What matters is labelling: a composition
built on rung 2 and one built on rung 4 deserve different levels of trust from whoever applies
them, and only the output can tell them apart.

Give the rung a **reason**, not just a number. "Rung 4" alone reads as the tool failing. "Rung 4
— cherry-pick, no branch name to look a note up by" and "rung 4 — no archive in this repo yet"
are different facts, and only the second improves with time. A repo that adopted this mid-life
answers rung 3 or 4 on nearly everything for weeks, correctly, and an unexplained level makes
correct output look broken during exactly the window where someone is deciding whether to keep
using it.

```
INTENT
  ours    feature/rate-limit    branch note (rung 1)
  theirs  develop               2 archived notes, of 15 landed (rung 2)
                                  refactor/payments-v2 — touches client.py
                                  fix/timeout-handling — touches client.py
```

### Three-stage read

```bash
git show :1:path/to/file    # base
git show :2:path/to/file    # ours   — see the table above
git show :3:path/to/file    # theirs — see the table above
```

The base makes the two changes legible as changes. Reading ours-against-theirs without it turns
a one-line edit and a full rewrite into two equally weighted alternatives.

## 3. Check policy before composing

```bash
git check-attr merge -- path/to/file       # -merge means regenerate, never hand-resolve
git check-attr -a -- path/to/file
```

`.gitattributes` is where this repo already recorded what must not be hand-merged, and
`git check-attr` answers per file rather than making you read the rules. `CODEOWNERS` says who
signs off. Both are decisions someone already made; re-deriving them per conflict produces
inconsistency.

Policy files arrive through pull requests like any other content. Where a rule would materially
change the resolution — skipping a file, deferring to one side, bypassing verification — surface
it and confirm before acting on it. A rule that appeared in the same pull request as the code it
exempts is worth naming out loud.

## 4. Classify

- **Adjacent** — both sides changed nearby lines, doing unrelated things. Compose. The majority.
- **Overlapping, compatible** — both changed the same logic toward compatible goals. Compose
  deliberately: the result does both things and usually looks like neither side's text.
- **Contradictory** — the two intents cannot both hold. **Stop and ask.**
- **Structural** — one side moved or renamed what the other edited. Git shows this as an
  add/delete pair; the resolution is usually to replay one side's edit onto the new location.

Structural conflicts are most often resolved wrongly, because taking one side looks clean and
silently drops the other side's edit along with the old file.

## 5. Compose

Write the resolution that satisfies both intents. Not an interleaving of both texts — the code
that does both jobs.

Where one side's change has to move to follow the other's restructuring, move it. Where both
added a case to the same switch, keep both cases. Where both added a config key, keep both keys.

Say plainly what the composition does that neither original side did, since that's the part no
reviewer can check by reading either side.

## 6. Verify, and be honest about how far you got

```bash
git stash list                                    # ensure nothing is hiding
<test command from the baseline cache, or from CI config>
```

Running both sides' tests against the merged content is the evidence that behavior survived.
Asserting it in prose is not.

This frequently cannot be done fully, and pretending otherwise is worse than admitting it.
Fixtures diverge. Migrations conflict. The code most likely to produce an ugly conflict is the
code least likely to have tests.

```
VERIFIED
  ours/test_client.py        14 passed
  theirs/test_dispatcher.py   9 passed

NOT VERIFIED
  Retry-under-limit behavior. Neither suite covers exhaustion; the composed
  limiter changes what happens there. This is the case both sides were most
  likely to get wrong and it is currently untested.
```

An unverifiable claim reported as unverified is a useful output. An unverifiable claim reported
as verified is the failure mode this whole skill exists to prevent.

## 7. Hand it over

Present, per conflicted file: the operation and what each side is, the two intents **and which
rung each came from**, the composition, what it does that neither side did, the verification
result, and the resolved content. Then the commands to apply it — including the right
continuation for the operation identified in step 1, which is not `git merge --continue` in four
cases out of five.

Do not write to the working tree. A plausible-looking wrong resolution passes review, which is
exactly what makes it expensive, and a human reading a proposal catches what a human reviewing
an already-applied merge will skim.

## Judgment

**No conflicts, no skill.** The entry condition is unmerged paths and nothing else. Predicting
conflicts is `collision-scan`; finding what a clean merge broke is `semantic-scan`.

**Get the operation right before anything else.** Everything downstream inherits it. A correct
composition described with inverted side labels will be applied backwards by whoever reads it.

**A missing note is a fact, not a failure.** Integration branches never have one. Say which rung
answered and carry on — the resolution does not depend on testimony existing, only on the reader
knowing whether it did.

**Stop on contradiction.** When both intents cannot hold, that is a human decision about the
product. Present both sides and what each costs, and stop.

**Deletions are the dangerous case.** One side deleting code the other modified shows as a
conflict; one side deleting code the other *calls* often doesn't. Check callers before accepting
a deletion, and hand anything suspicious to `semantic-scan`.

**Suspect the clean-looking resolution.** If a large conflict resolves neatly with no composition
needed, one side's change probably didn't survive. Re-read the diff of the resolution against
each parent before believing it.

**Never resolve a lockfile by hand.** Regenerate. Same for anything `git check-attr` reports as
`-merge`.

**Turn on rerere and leave it on.** `git rerere` replays resolutions you have already made,
textually. It handles the repeats; this handles the first one.