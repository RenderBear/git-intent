# AGENTS.example.md

Copy the block below into the `AGENTS.md`, `CLAUDE.md`, or `.cursorrules` of a repo where
you want git-intent active. It is what turns `capture-diff` from a thing you remember to
run into a thing that happens on its own.

This transport exists for one event the others can't reach. A decision being abandoned leaves
no git state behind — no commit, no ref, nothing a hook could detect — so the only thing that
can catch it is something already in the room when it happens. Without this block, capture only
ever runs retrospectively, reconstructing reasoning at the moment recall is worst.

The optional [`hooks/`](hooks/) cover two of the other events. Everything else is a slash command.

---

## git-intent

This repo uses [git-intent](https://github.com/RenderBear/git-intent) to keep a record of
why changes were made, not just what changed.

### While working on a branch

Append to `.branch-notes/<current-branch>.md` when any of these happen:

- An approach is tried and abandoned — record what and why. This is invisible in the
  final diff, and the next person will otherwise try the same thing.
- An external constraint forces a design (vendor limits, an API contract, a consumer
  that can't break).
- A value is chosen that looks arbitrary — a timeout, a batch size, a retry count.
  Note where it came from, or say it was a guess.
- Something is written that looks wrong and isn't, so nobody "fixes" it later.

Keep entries to one or two lines, and date them. Do not restate the diff — files changed,
functions added, and tests written are all derivable and belong nowhere in this file.

Use the `capture-diff` skill for the file format and the trailing anchor line.

### Before opening a PR

Run `capture-diff` against the target branch to complete the note, then `review-diff`
for a risk-ordered summary.

### After a review round

If review changed behavior, run `capture-diff` again — append what changed and move the
anchor. The note is archived as-is when the branch lands, so a note left at its pre-review
state is the version that survives permanently. `review-diff` reports the gap on every run.

### When merging

Use `resolve-conflicts` for conflicts rather than resolving by hand. It reads both sides'
`.branch-notes/` entries, identifies whether you are in a merge or a rebase before naming
a side, and verifies the result against both sides' tests.

### After merging

Run `reconcile-notes` on the integration branch. It archives the notes of branches that landed
and reports what the merge made false in the derived baseline.

### Background

`/baseline-scan` computes what this repo is — structure, hot and dormant areas, ownership,
coupling — into an uncommitted cache. It asks nothing and regenerates in seconds, so if it
looks stale, regenerate rather than working around it.

Constraints, deliberate oddities, and architectural decisions do **not** go in branch notes
or the baseline. They go in `ARCHITECTURE.md` or `docs/adr/`, where they are reviewed and owned.
