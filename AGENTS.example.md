# git-intent — the agent rule to copy

git-intent's skills are slash commands and hooks. One thing, though, no command or hook can reach: a decision being *abandoned* leaves no git state — no commit, no ref — so the only thing that can record it is an instruction already in the room when it happens. That is what this file is for. Without it, capture runs only after the fact, reconstructing reasoning at the moment recall is worst.

**Pick one setup below and copy its fenced block** into the repo's `CLAUDE.md`, `AGENTS.md`, or `.cursorrules`:

- **A — Assisted** (default, start here): you invoke the skills; the agent captures intent as you work and warns you, but never creates worktrees or merges on its own.
- **B — Fully automated**: the agent takes a request and runs the whole loop, stopping only to ask about scoping or an integration it can't settle.

Whatever you paste is loaded on every turn, forever, competing with the project's own instructions for attention — so copy **one** block, not both, and don't inline how the skills work. That lives in the skills, which load only when they fire.

---

## A — Assisted (default)

You drive: you invoke the skills by name, and the agent assists. The one thing it does unprompted is record intent — because an abandoned approach can't be caught any other way. It never creates worktrees, splits work, or merges on its own. This is the floor; start here, and move to B only once your notes and tests are solid.

```markdown
## git-intent (assisted)

Recording intent — run capture-diff to append to .branch-notes/<branch>.md,
without being asked, whenever:
  - an approach is tried and abandoned (invisible in the final diff — the next
    person will otherwise try it too)
  - an external constraint forces a design
  - a value is chosen that will look arbitrary later (a timeout, a batch size)
  - something is written that looks wrong and isn't
Commit at each working state; append to the note at each decision — these
happen at different rates. Never record what the diff already shows.

Before a PR: capture-diff, then review-diff. If review changed behaviour, run
capture-diff again — the note is archived as-is when the branch lands, so a
stale note is the version that survives.
On conflicts: resolve-conflicts, not by hand.
After landing, on the integration branch: reconcile-notes.

Automation level: assisted. The human invokes the skills; the agent never
creates worktrees, splits work, or merges on its own.
```

---

## B — Fully automated

The agent takes a request and runs the loop end to end: scope, branch, worktree, build, check, merge. It stops for you on exactly two occasions — scoping it can't settle, or an integration it can't settle safely — and does everything else on its own.

Move here only once your "Must survive" lines and your tests are solid. Those two stops are what hold full automation back, and they lean entirely on notes and tests being real; a repo with thin notes and few tests should stay on A. (The trade is [`SPEC.md`](SPEC.md) §4.1.) This block is heavier than A by necessity — it carries the loop.

```markdown
## git-intent (fully automated)

Recording intent — run capture-diff to append to .branch-notes/<branch>.md,
without being asked, whenever an approach is abandoned, a constraint forces a
design, a value is chosen that will look arbitrary later, or something looks
wrong and isn't. Commit at each working state; append at each decision.
Never record what the diff already shows.

Working in parallel — operate like a careful integrator, not a single-threaded
editor:
  - When a request arrives: scope-work. Fork one branch + worktree per
    independent unit, but only where the contract between them can be written
    down first; otherwise sequence them. One intent is one branch — don't fan
    out the steps of a single change.
  - One unit = one branch = one worktree, cut from the integration branch:
        git worktree add ../wt/<slug> -b <type>/<slug>
    Never edit main / develop / release/* directly.
  - Before writing code: collision-scan.
  - While working: capture-diff as you decide; write the "Must survive" line.
  - Before landing: semantic-scan --pre-land, then merge into the target.
  - After landing: reconcile-notes.

Automation level: full. Run the whole loop on your own — worktrees, branches,
splitting, --dispatch, --auto, merges. Stop to ask a person on exactly two
occasions:
  1. scoping is uncertain — the request is ambiguous, or a fork's contract
     can't be written down (so the work can't be split safely);
  2. integration can't be settled safely — a real conflict, two intents that
     contradict, a "Must survive" line you can't show still holds, or tests
     you can't get green.
Never proceed quietly past either.
```

---

## What does not go in branch notes (either setup)

Keep durable reasoning out of the notes. Say this in the repo's own instructions if it isn't already clear:

```markdown
Constraints, architectural decisions, and conventions belong in ARCHITECTURE.md
or docs/adr/ — reviewed, owned, durable. Branch notes are per-branch and get
archived; don't put standing decisions in them.
```

The test for any candidate line: could it be recovered from the repo tomorrow? If yes, it belongs in a commit message, the architecture docs, or nowhere. Branch notes hold the remainder — the part that exists only in someone's head, and only for about an hour.
