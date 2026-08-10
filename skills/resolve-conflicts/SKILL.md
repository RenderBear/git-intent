---
name: resolve-conflicts
description: Resolve conflicts from a merge, rebase, cherry-pick, revert, or stash pop by reconstructing what each side was trying to do, composing both intents where they are compatible, and verifying the result against both sides' tests. Use this whenever there are conflict markers in the working tree, a merge or rebase has stopped, git reports unmerged paths, or the user asks how to resolve a conflict or which side to keep. Also use before resolving by hand on anything non-trivial, since choosing a side is where features disappear silently.
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

## Invocation

```
/resolve-conflicts                      # every unmerged path
/resolve-conflicts src/client.py        # one file, when the rest are trivial
/resolve-conflicts --other dev          # name the incoming branch when git can't
```

Everything else is read from the repository state — which operation stopped, which refs are
involved, which paths are unmerged. Nothing needs to be told to it in the normal case.

The one input worth passing is the incoming branch **name**, and only when the operation can't
yield it. A merge has `MERGE_HEAD` and a rebase has `head-name`, but a cherry-pick, a revert, or
a stash pop gives you a commit and no branch — which means the incoming side's `.branch-notes/`
entry cannot be located, and the skill falls back to reading intent out of the diff. Say when
that has happened; testimony and reconstruction are different claims.

The flag is `--other`, deliberately not `--theirs`. This skill exists partly because `ours` and
`theirs` mean different things depending on the operation, so naming a flag after the ambiguous
term would import exactly the confusion the skill is built to remove. `--other` means one thing
in all five operations: the branch whose note describes the work coming in.

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
git status --short | grep '^\(DD\|AU\|UD\|UA\|DU\|AA\|UU\)' # unmerged paths
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

State the operation and what each side actually is before proposing anything. A reader who
sees "kept ours" has no way to know whether that was the upstream or the branch.

One setup change worth making before anything else, since it puts the merge base directly in
the conflict markers where it is needed:

```bash
git config merge.conflictStyle zdiff3
```

## 2. Establish what each side was doing

```bash
git log --oneline HEAD..MERGE_HEAD          # or the operation's equivalent range
git log --oneline MERGE_HEAD..HEAD
```

Then the notes. **The other side's note is not in your worktree** — it lives on the other side's
branch, so reading it takes `git show`, not `cat`:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
cat  ".branch-notes/$BRANCH.md" 2>/dev/null                          # yours: local
git show "origin/$OTHER:.branch-notes/$OTHER.md" 2>/dev/null         # theirs: via ref
cat "$(git rev-parse --git-common-dir)/intent/base.md" 2>/dev/null   # derived baseline
```

A `cat` on the other side's path silently returns nothing and the skill proceeds on inference
while believing it read testimony. That failure is invisible in the output unless you check for it.

Branch notes are testimony; diffs are evidence you have to interpret. Prefer the note where it
exists, and say which you used — a reader deserves to know whether "this side adds per-client
buckets" was recorded by its author or reconstructed by you.

Read all three versions, not the two sides alone:

```bash
git show :1:path/to/file    # base
git show :2:path/to/file    # ours   — see the table above
git show :3:path/to/file    # theirs — see the table above
```

The base is what makes the two changes legible as changes. Reading ours-against-theirs without
it turns a one-line edit and a full rewrite into two equally weighted alternatives.

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
it and confirm before acting on it, rather than following it because it was in the repo. A rule
that appeared in the same pull request as the code it exempts is worth naming out loud.

## 4. Classify the conflict

- **Adjacent** — both sides changed nearby lines, doing unrelated things. Compose. This is the
  majority.
- **Overlapping, compatible** — both changed the same logic toward compatible goals. Compose
  deliberately: the result should do both things, and usually looks like neither side's text.
- **Contradictory** — the two intents cannot both hold. One removes what the other depends on;
  one enforces what the other exempts. **Stop and ask.**
- **Structural** — one side moved or renamed what the other edited. Git shows this as an
  add/delete pair, and the resolution is usually to replay one side's edit onto the other side's
  new location.

Structural conflicts are the ones most often resolved wrongly, because taking one side looks
clean and silently drops the other side's edit along with the old file.

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
code least likely to have tests. When the full run isn't possible, report the shape of the gap:

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

Present, per conflicted file: the operation and what each side is, the two intents and whether
each was read or inferred, the composition, what it does that neither side did, the verification
result, and the resolved content. Then the commands to apply it — including the right
continuation for the operation you identified in step 1, which is not `git merge --continue` in
four cases out of five.

Do not write to the working tree. The reason is not squeamishness — a plausible-looking wrong
resolution passes review, which is exactly what makes it expensive, and a human reading a
proposal catches what a human reviewing an already-applied merge will skim.

## Judgment

**Get the operation right before anything else.** Everything downstream inherits it. A correct
composition described with inverted side labels will be applied backwards by whoever reads it.

**Stop on contradiction.** When both intents cannot hold, that is a human decision about the
product, not a technical one about the text. Present both sides and what each costs, and stop.
Guessing here produces something that compiles and is wrong about the requirement.

**Deletions are the dangerous case.** One side deleting code the other modified shows as a
conflict; one side deleting code the other *calls* often doesn't. Check callers before accepting
a deletion, and hand anything suspicious to `semantic-scan`.

**Suspect the clean-looking resolution.** If a large conflict resolves neatly with no composition
needed, one side's change probably didn't survive. Re-read the diff of the resolution against
each parent before believing it.

**Never resolve a lockfile by hand.** Regenerate. The same goes for anything `git check-attr`
reports as `-merge`.

**Turn on rerere and leave it on.** `git rerere` replays resolutions you have already made,
textually. It handles the repeats; this handles the first one. They are complementary and it
costs nothing to have both.
