---
name: resolve-conflicts
description: Resolve conflicts from a merge, rebase, cherry-pick, revert, or stash pop by reconstructing what each side was trying to do, composing both intents where they are compatible, and verifying the result against both sides' tests. Proposes by default (a human applies); --auto applies and verifies autonomously, stopping only on an intent contradiction, a violated invariant, or failed verification. Use this whenever git reports unmerged paths, conflict markers exist in the working tree, or a merge or rebase has stopped. Requires an operation in progress with real conflicts — with a clean tree there is nothing to resolve and the skill says so and stops.
---

# resolve-conflicts

A conflict is two intentions colliding. Git shows the collision as text, because text is all it
has. Resolving the text without recovering the intentions is how functionality disappears: the
result compiles, the tests someone happens to run pass, and one side's work is quietly gone.

The default outcome should be a composition, not a choice. Most conflicts are two compatible
changes that happened to land on adjacent lines, and picking a side throws away half of a solved
problem for no reason.

**By default this skill proposes; it does not apply.** It produces the resolved content, the
reasoning, and the verification result, and a human writes it into the tree. That is automation
level `assisted`, and it is the default because a plausible-looking wrong resolution passes review
— which is exactly what makes it expensive.

**`--auto` (or a repo set to `full`) applies and verifies autonomously** — and stops for a human on
exactly three conditions: an **intent contradiction** (the two sides can't both hold), a
**violated invariant** (either side's `assert`, or a landed one, breaks against the composition),
or **failed verification** (the composed result doesn't pass both sides' tests). Never past those
three. Full automation is safe *because* of that backstop, not in spite of it: `--auto` is not
"trust the merge", it is "apply it unless a contradiction, a broken promise, or a red test says
stop". Everything below runs identically in both modes up to step 7 — the reconstruction, the
composition, the verification are the same work; only who commits the result differs.

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
/resolve-conflicts                      # every unmerged path — propose (assisted)
/resolve-conflicts src/client.py        # one file, when the rest are trivial
/resolve-conflicts --other dev          # name the incoming branch when git can't
/resolve-conflicts --auto               # apply and verify; stop only on the three conditions
```

`--auto` selects `full` for this one resolution regardless of the repo's automation level. There
is no override in the other direction — dropping to a human is always allowed, so a repo set to
`full` still honors a plain invocation as a request to propose.

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

**Both sides' `assert` blocks are the cheap half of this, and they run where the tests don't.**
Each entry is what that branch's author said had to survive — which is the exact
question in front of you — written so one command can falsify it. Collect the live assertions
from both notes (an entry named by another's `supersedes:` is history, not a requirement) and
evaluate each against the **composed** content, anchor first:

```bash
git grep -qn '\bdispatch\b' -- src/client.py   || echo unresolvable   # anchor
git grep -qn 'RateLimiter'  -- src/client.py   || echo violated       # predicate
```

An assertion that held on its own side and fails against your composition is the strongest
finding this skill produces: it is that branch's author, in writing, saying the thing you just
did was not allowed.

Unresolvable has to stay separate from violated, and here more than anywhere — relocating code
*is* frequently the composition, so anchors move constantly and calling that a violation would
turn the section into noise on its first run. Report it as a question and name the assertion that
needs re-anchoring once the resolution lands.

Where a side has no note, or a note with no assertions, say that rather than reporting zero
violations. Zero checks and zero failures look identical in a summary and mean opposite things.

```
VERIFIED
  ours/test_client.py        14 passed
  theirs/test_dispatcher.py   9 passed
  assert a1 (ours)           holds — RateLimiter still present in client.py

NOT VERIFIED
  Retry-under-limit behavior. Neither suite covers exhaustion; the composed
  limiter changes what happens there. This is the case both sides were most
  likely to get wrong and it is currently untested.
  assert b2 (theirs)         unresolvable — this resolution moved dispatch into
                             transport.py; re-anchor after applying
  theirs                     no assertions in the note — 0 checked, not 0 failed
```

An unverifiable claim reported as unverified is a useful output. An unverifiable claim reported
as verified is the failure mode this whole skill exists to prevent.

## 7. Hand it over — or land it

Present, per conflicted file: the operation and what each side is, the two intents **and which
rung each came from**, the composition, what it does that neither side did, and the verification
result.

**Assisted (default).** Show the resolved content and the commands to apply it — including the
right continuation for the operation identified in step 1, which is not `git merge --continue` in
four cases out of five. Do not write to the working tree. A plausible-looking wrong resolution
passes review, which is exactly what makes it expensive, and a human reading a proposal catches
what a human reviewing an already-applied merge will skim.

**`--auto` / full.** Only here does the skill write. The gate is the three conditions from the
top, checked in this order before anything is applied:

1. **Intent contradiction** — step 4 classified a conflict as *Contradictory*. Stop; this is a
   product decision, not a merge.
2. **Violated invariant** — step 6 found a live `assert` (either side, or a landed one) that
   holds on its own side and fails against the composition. Stop; that is an author, in writing,
   saying the composition is not allowed. `unresolvable` does **not** stop — it is a question.
3. **Failed verification** — both sides' tests don't pass against the composed content, or the
   code that would verify the dangerous path doesn't exist. Stop; an unverifiable resolution
   applied silently is the exact failure this skill exists to prevent.

Clear all three and it applies: stage the resolved files, run the operation's continuation, and
report what it did with the same per-file breakdown a proposal would have carried — plus the undo
command. Never commit; staging is the boundary, so a human still sees `git status` before it's
permanent. If any condition trips, fall back to `assisted` for the whole resolution and say which
condition sent it back — a partial auto-apply is worse than none.

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

**`--auto` never widens the gate, it just removes the typing.** The three stop conditions are the
same in both modes — `assisted` shows a human every resolution, `full` shows them only the ones
that trip a condition. If `--auto` would ever apply something `assisted` would have flagged, the
condition list is wrong, not the mode.

## Next — close the loop

End by naming the continuation and what a violated invariant needs — a stopped resolution is a
decision waiting on a person, and the footer says whose and about what.

```
Next
  · git <op> --continue        the operation's own continuation (not always merge --continue)
  · /capture-diff              record why the composition took the shape it did — it's a decision
  · /semantic-scan --pre-land  re-check invariants against the resolved result before landing
  · --auto                     apply this resolution autonomously (or drop --auto to propose)
```

After a contradiction or a violated invariant, the useful next line is who decides and what the
supersede would say — not a git command.