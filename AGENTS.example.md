This transport exists for one event the others can't reach. A decision being abandoned leaves
no git state behind — no commit, no ref, nothing a hook could detect — so the only thing that
can catch it is something already in the room when it happens. Without this block, capture runs
only retrospectively, reconstructing reasoning at the moment recall is worst.

The optional [`hooks/`](hooks/) cover two of the other events. Everything else is a slash command.

## Keep it short

Whatever you paste is **loaded on every turn in this repo, forever**, competing with the
project's own instructions for attention. Long rules get skimmed by models the same way long
onboarding docs get skimmed by people.

So the block names *when to act* and nothing else. How to write the note, what the file looks
like, what goes in which section — all of that lives in `capture-diff`, which loads when the
skill fires and costs nothing until then. Resist the urge to inline it.

---

## Minimal — recommended

Four lines of trigger, one of hygiene. This is the whole of what the always-on layer needs.

```markdown
## Recording intent

This repo uses git-intent. Use the `capture-diff` skill to append to
`.branch-notes/<branch>.md` — without being asked — when:

- an approach is tried and abandoned (invisible in the final diff, and the
  next person will otherwise try it too)
- an external constraint forces a design
- a value is chosen that will look arbitrary later — a timeout, a batch size
- something is written that looks wrong and isn't

Commit at each working state; append to the note at each decision. These
happen at different rates — don't tie them together.

Never record what the diff already shows.
```

That last line does more work than its length suggests. Without it, notes drift into prose
restatements of the changeset, and a note that duplicates the diff is worse than no note: it
costs review attention and buries the two lines that mattered.

---

## Full loop — optional

Add if you want the whole lifecycle prompted rather than invoked. Everything here is also
reachable as a slash command or a hook, so this block buys convenience, not capability.

```markdown
### Also

- Before opening a PR: `capture-diff`, then `review-diff`.
- If review changed behavior: `capture-diff` again. The note is archived as-is
  when the branch lands, so a stale note is the version that survives.
- On conflicts: `resolve-conflicts` rather than resolving by hand.
- After landing, on the integration branch: `reconcile-notes`.
```

The second line is the one worth keeping even if you drop the rest. Review changes code, nobody
re-runs capture, and `reconcile-notes` archives whatever is in the tree — so the pre-review note
becomes the permanent record of a branch that shipped something else. `review-diff` reports the
gap on every run, but only if someone is running it.

---

## What does not go in branch notes

Say this in the repo's own instructions if it isn't already obvious there:

```markdown
Constraints, architectural decisions, and conventions belong in ARCHITECTURE.md
or docs/adr/ — reviewed, owned, and durable. Branch notes are per-branch and
get archived. Don't put standing decisions in them.
```

The test for any candidate line: **could this be recovered from the repository tomorrow?**
If yes, it belongs in a commit message, in the architecture docs, or nowhere. Branch notes are
for the remainder — the part that exists only in someone's head, and only for about an hour.