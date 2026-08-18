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

## Working in parallel — for repos running agents in worktrees

The blocks above make the *skills* fire. This one makes the *agent* operate like a careful human
integrator instead of a single-threaded editor — it's what you add when more than one agent works
the repo at once. Heavier than the capture rule, so add it only for that case.

```markdown
## Working in parallel

Operate like a careful human integrator, not a single-threaded editor.

- **When a request arrives:** scope-work. If it holds more than one
  independent intent, fork one branch/worktree per intent — but only where the
  contract between them can be written down first. If it can't, sequence them;
  never race two agents at a contract that doesn't exist yet. One intent is one
  branch — don't fan out the steps of a single change.
- **One unit of work = one branch = one worktree.** Never edit an integration
  branch (main / develop / release/*) directly. Cut a worktree per task:
      git worktree add ../wt/<slug> -b <type>/<slug>
  Work only inside it. The git-intent cache is shared across worktrees
  automatically, so parallel agents don't clobber each other's baseline.
- **Before writing code:** collision-scan. If another worktree or live branch
  is already in these files, settle who owns what now, not at merge.
- **While working:** capture-diff as you decide — and write the "Must survive"
  line, the one thing about this work that later changes must not quietly undo.
- **Before landing:** semantic-scan --pre-land. It brings up every "Must survive"
  line your change runs into — your own, a live peer's in another worktree, or
  one from work that already landed. For each, decide: does it still hold, does
  your change replace it, or does it no longer apply. How that decision gets
  made is the automation level below.
- **After landing:** reconcile-notes on the integration branch.

Don't wait to be asked for any of these.
```

## Automation level

This one line decides who makes the call when your change runs into a "Must survive" line someone
wrote, or when a merge conflicts.

```markdown
## Automation level

assisted (default) — ask a person. When a change runs into a "Must survive"
                     line, or a merge conflicts, stop and lay out the options;
                     a person decides.
full               — decide it yourself where you can, and only stop for a
                     person on three things: the two sides contradict, a "Must
                     survive" line you can't show still holds, or the tests go
                     red. Never quietly past those three.
```

Start at `assisted`. Move to `full` once the "Must survive" lines and the tests are solid enough to
lean on — they are what make full safe, so a repo with thin notes and few tests should stay at
`assisted`. A single command can still opt in with `resolve-conflicts --auto`.

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