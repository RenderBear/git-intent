# git-intent — specification

Git records what changed with total precision and why it changed not at all. The gap is not a
missing feature; it is structural. No amount of tooling over commit text recovers the approach
someone tried on Tuesday and abandoned on Wednesday, because it was never written down.

git-intent is the layer that closes that gap, and nothing more. It stores the complement of
what git stores, derives everything else on demand, and hands the result to whoever acts next.

The model is Conductor's. Conductor does not write code; it owns worktree lifecycle and
delegates the work inside each one to an agent. git-intent owns **intent lifecycle** — when
intent gets captured, carried, reconciled, and retired — and delegates every act of judgment
to a skill. The layer is a state machine over git refs. The intelligence is rented.

## 1. Non-goals

These are load-bearing. Each one is a thing this could become and must not.

- **Not a service.** No daemon, no server, no database, no background process. Every event is
  detectable from git state by a command that terminates.
- **Not a git wrapper.** Nobody needs a nicer `git merge`. If git already does it, this defers.
- **Not an ADR system.** Decisions about architecture live in `README.md`, `ARCHITECTURE.md`,
  `CHANGELOG.md`, and `docs/adr/`. Those have their own review discipline and this must not
  compete with it.
- **Not a source editor.** No skill writes to a tracked source file. Ever. Resolutions,
  archives, and prunes are emitted as commands a human runs.
- **Not required.** Every skill runs against a repo that has never heard of this one. The
  layer makes them cheaper and sharper, never possible.

## 2. State

Three kinds of state, distinguished by who can produce them. The distinction decides where
each lives, and everything else follows from it.

| Kind | Example | Producible by | Location |
|---|---|---|---|
| Derived | churn, hotspots, ownership, structure | anyone with the repo | `.git/intent/` — cache |
| Testimony | the abandoned approach, what must survive | only the author, only now | `.branch-notes/` — committed |
| Policy | regenerate don't merge; who signs off | a human, deliberately | `.gitattributes`, `CODEOWNERS` |

### 2.1 Derived state is a cache, not a document

`.git/intent/base.md` holds what the repo is, computed from git. It is **not committed**.

The argument for committing it was always that it contained hand-written constraints someone
had to author. Once those move to `ARCHITECTURE.md` and `docs/adr/` where they belong, nothing
remains that another clone could not reproduce from the same history. Committing a reproducible
artifact buys nothing and costs three things: merge churn on every landing, an authority the
file has not earned, and a staleness problem that needs a human to adjudicate.

The cache is anchored to the **common** git dir, not the per-worktree one:

```bash
INTENT="$(git rev-parse --git-common-dir)/intent"
```

In a linked worktree `.git` is a file rather than a directory, and `--git-dir` resolves per
worktree while `--git-common-dir` resolves to the shared repository. Anchoring to the common dir
means a tool that spins up five worktrees for five parallel branches computes this once instead
of five times. The cache belongs to the repository, not the checkout.

As a cache, staleness stops being a judgment call:

```
Generated at: <sha>
```

Stale iff `git diff --name-only <sha>..HEAD` touches a structural input — top-level directories,
dependency manifests, CI config. Regeneration is a handful of git commands; when in doubt,
regenerate rather than reason about it.

The cache holds only what git can answer:

- structure and entry points, from the tree
- hot and dormant regions, from churn over a window
- ownership and bus factor, from authorship
- coupling — files that change together — from commit co-occurrence
- test, lint, and build commands, read from CI config verbatim
- pointers to `README.md` / `ARCHITECTURE.md` / `docs/adr/`, never restatements of them

Hot-versus-dormant is the section that justifies the file. A module rewritten three times this
quarter and one untouched for two years demand opposite caution, and nothing in a directory
listing says which is which.

### 2.2 Testimony is committed, and branch-local by construction

`.branch-notes/<branch>.md` exists only on the branch it describes. This is not an accident to
work around — it is the property that makes the scheme free of self-conflict. Two branches never
contend for the same note file, because each only ever writes its own.

The consequence is a read rule that the current skills get wrong, in three places:

```bash
# WRONG — that path does not exist in your worktree
cat .branch-notes/other-branch.md

# RIGHT
git show origin/other-branch:.branch-notes/other-branch.md 2>/dev/null
```

Any skill reading another branch's note reads it through `git show <ref>:<path>`. A silent
miss here degrades the skill to diff-guessing while it reports having read testimony.

### 2.3 Policy lives where git already reads it

Merge policy is `.gitattributes`. Sign-off policy is `CODEOWNERS`. Neither is reinvented here.

```gitattributes
src/vendor/**   -merge          # regenerate; never hand-merge
*.lock          -merge
db/migrations/* merge=ours      # never renumber to resolve
```

Two reasons this matters beyond tidiness. Git itself honors `.gitattributes`, so the rule acts
rather than advises. And a policy change now arrives in a file reviewers already treat as
infrastructure, which substantially closes the injection surface — a rule that exempts code
from review no longer arrives as prose in the same PR as the code it exempts.

Skills **read** these files. Skills never write them.

## 3. Lifecycle

Eight events. Six are detectable from git state alone, which is the entire argument that no
service is needed: any transport can evaluate the detector and decide.

| Event | Detector | Actor | Gate | Effect |
|---|---|---|---|---|
| `branch.start` | `git rev-list --count $BASE..HEAD` = 0 | `collision-scan` | auto | none |
| `decision.made` | *not directly — see §3.2* | `capture-diff` | append | note appended |
| `branch.ready` | ahead of base, human says so | `capture-diff`, `review-diff` | append | note completed |
| `review.round` | `git log <anchor>..HEAD` non-empty | `review-diff` → `capture-diff` | append | note re-anchored |
| `queue.forming` | ≥2 unmerged branches ahead of base | `merge-order` | auto | none |
| `conflict.raised` | `git ls-files -u` non-empty | `resolve-conflicts` | propose | nothing written |
| `branch.landed` | commits reachable from base ref | `reconcile-notes`, `semantic-scan` | archive / confirm | note archived, cache invalidated |
| `release.cut` | a tag appears on the base ref | `release-notes` | auto | none |

### 3.0 Two skills are outside the lifecycle, deliberately

`onboard-file` and `bisect-report` have no position here and should not be given one. They
answer questions — *why is this code like this?* and *what broke?* — rather than reacting to
moments in a branch's life. A question arrives when someone has it, which is not an event a
detector can wait for.

This distinction is worth stating rather than papering over by inventing a `file.unfamiliar`
event. Nine of eleven skills hang off the lifecycle; two are diagnostics you reach for. A spec
that forced all eleven into the table would be describing a system nobody built.

### 3.1 `branch.start`

A new branch off the integration branch. `collision-scan` reports overlapping in-flight work
while it is still cheap to talk. Read-only, no gate. Refresh the derived cache here if stale —
it is the cheapest moment, and everything downstream reads it.

### 3.2 `decision.made` — and how to know it didn't fire

An approach is tried and dropped; a vendor limit forces an ugly shape; a timeout is picked out
of the air. `capture-diff` appends in-session, while the reasoning is still in context.

The event itself cannot be detected. A decision is a mental act, and no command observes it —
which is why this is the one transport that must be a rule in the repo rather than a hook, and
the one place the layer depends on a convention rather than a mechanism.

But the testimony layer is the differentiated half of this project, and resting it on an
unobservable trigger with no feedback would mean never knowing whether it worked. So the spec
requires detecting the **absence** instead, which is entirely mechanical:

```bash
test -f ".branch-notes/$BRANCH.md"                  # did capture ever run?
grep -c '^- 20[0-9][0-9]-' ".branch-notes/$BRANCH.md"   # dated reasoning, or a stub?
```

And for the highest-value case specifically — an approach tried and abandoned — there *is* a
retroactive detector, because abandoned work leaves a fingerprint even after the diff erases it:

```bash
# touched in this branch's history, identical to base in the final diff
comm -23 <(git log --format='' --name-only $BASE..HEAD | sort -u) \
         <(git diff --name-only $BASE..HEAD | sort -u)

# added, then deleted — the abandoned approach, by name
comm -12 <(git log --diff-filter=A --format='' --name-only $BASE..HEAD | sort -u) \
         <(git log --diff-filter=D --format='' --name-only $BASE..HEAD | sort -u)

git log --oneline --diff-filter=D $BASE..HEAD -- <path>   # the commit usually says why
git reflog --date=short                                   # work a rebase or reset dropped
```

A file touched in three commits and unchanged in the net diff is the signature of something
tried and undone. Every reviewer is blind to it, because review reads the diff and the diff is
exactly where the evidence was deleted.

So the guarantee is three-layered, and the layers are honest about their strength:

| | Mechanism | Strength |
|---|---|---|
| Trigger | a rule in the repo's `AGENTS.md` | convention — can silently not happen |
| Absence check | note missing, or a stub with no dated entries | mechanical, runs in `review-diff` |
| Retroactive recovery | touched-but-reverted paths, add-then-delete pairs, reflog | mechanical, names the file |

The third layer is what makes the second one actionable. "Was anything abandoned?" gets a shrug;
"`decorator.py` was added in `a1b2c3d` and removed in `118e9f2` — should that be in the note?"
gets an answer. Nobody remembers in the abstract and everybody remembers when shown a filename.

`review.round` is the deadline. Once the branch lands and `reconcile-notes` archives the note,
the reasoning is gone for good and no later run recovers it.

### 3.3 `branch.ready`

Before the PR. `capture-diff` derives everything derivable and asks the single question no
history can answer:

> If this conflicts with something, what has to survive?

Then `review-diff` produces the risk-ordered summary. One question, once, per branch. Any
second question is a chance for someone to decide this is not worth the trouble.

### 3.4 `review.round` — the first hole this spec closes

A note stamped `Last captured at c81f0a2` and three rounds of review later describes code that
no longer exists. Worse, it is the *merged* note that gets archived, so the version preserved
forever is the pre-review one.

Detection is mechanical:

```bash
ANCHOR=$(grep -oE '[0-9a-f]{7,40}' .branch-notes/$BRANCH.md | tail -1)
git log --oneline $ANCHOR..HEAD
```

Non-empty means the note is behind the branch. `review-diff` reports the drift on every run —
it already reads both the note and the diff, so this costs one comparison in a skill people are
already running. If the intervening commits changed behavior, `capture-diff` appends and
re-anchors. If they were review nits, re-anchor alone.

### 3.5 `conflict.raised`

`git ls-files -u` non-empty, or one of `MERGE_HEAD` / `REBASE_HEAD` / `CHERRY_PICK_HEAD` present.

The skill's first job is to identify **which operation** it is in, because the operand names
invert. During a rebase, `ours` is the upstream you are replaying onto and `theirs` is your own
commit — the reverse of a merge. Resolutions that take "ours" out of habit are the single most
common way a branch's work disappears while the merge looks clean.

```bash
git rev-parse -q --verify MERGE_HEAD        # merge
ls .git/rebase-merge .git/rebase-apply      # rebase — ours/theirs INVERTED
git rev-parse -q --verify CHERRY_PICK_HEAD  # cherry-pick
git rev-parse -q --verify REVERT_HEAD       # revert
```

This is why the skill is `resolve-conflicts` and not `resolve-merge`: the name promised one
operation and the failure mode lives in the other three.

Gate is **propose**, permanently. A plausible wrong resolution passes review, which is precisely
what makes it expensive. Nothing is written to the tree.

### 3.6 `branch.landed` — the second hole this spec closes

Currently nothing runs on the integration branch. Every skill is branch-scoped and
human-invoked, so a merge — the moment when what changed is cheapest and most certain to
determine — is spent on nothing.

`reconcile-notes` runs post-landing and does three things:

1. **Archive the landed note** to `.branch-notes/_archive/<branch>.md`, mirroring the path so
   slash-named branches stay findable. A merged branch's note is at peak usefulness at exactly
   the moment it looks like garbage: it now describes code running in production.
2. **Delete abandoned notes** — branch gone, commits never landed. Squash merges look
   unmerged, so *unknown resolves to archive*, never to delete. The failure modes are wildly
   asymmetric.
3. **Invalidate the derived cache** and report which of its claims the landing contradicted.

Step 3 is why this replaces `prune-notes` rather than sitting beside it. `prune-notes` already
fetches, prunes, and classifies what actually landed — it is most of a reconciler already, and
it is the only skill that naturally runs on the integration branch.

Archived notes are not dead weight. They are the input to `release-notes` (why each change
happened, not just what landed) and to `onboard-file` (why this file is shaped like this).

## 4. Gates

Three classes. This is the whole human-in-the-loop design, and it needs no service because the
loop is the pull request.

**Auto** — read-only derivation, or a write to `.git/intent/`. No approval. Nothing durable,
nothing shared, nothing a mistake survives.

**Append** — a write to `.branch-notes/<branch>.md`. No approval *at write time*, because the
file lands in the PR diff and gets reviewed there with everything else. **The PR is the gate.**
This is the move that keeps the layer out of the way: it reuses review that already happens
instead of adding prompts that train people to click through.

**Propose** — anything touching source, anything destructive, anything irreversible. The skill
emits the reasoning and the exact commands; a human runs them.

An append is a *claim*. A propose is a *change*. Claims are cheap to be wrong about and are
caught by the existing review; changes are not and are not.

Two skills sit outside this, and both say so where they act. `bisect-report` executes, because
bisecting cannot be done any other way. `reconcile-notes` archives landed notes itself — a `git mv` of
markdown inside `.branch-notes/`, staged and not committed, with the undo printed. Its exception
is justified by the shape of the work rather than by convenience: archiving is the ~99% path
after every landing, and a proposal nobody executes is how the folder rots. Deletion stays behind
an explicit yes, because that destroys reasoning that exists nowhere else.

## 5. Transports

Events are declarative; how they fire is pluggable. Three transports, none required, all
optional, freely mixed. This is the "no separate service" answer in full.

**Human.** Type the slash command. Always works, requires nothing, and is the floor every
other transport builds on.

**Agent rule.** A block in `CLAUDE.md` / `AGENTS.md` / `.cursorrules`. The only transport that
can fire `decision.made`, because it is the only one present at the moment a decision happens.

**Git hook.** Shipped in [`hooks/`](hooks/). `post-checkout` → `branch.start`, `post-merge` →
`branch.landed`, enabled with `git config core.hooksPath hooks`.

A hook **cannot handle an event** — it has no session, no context, and no way to ask anything.
So these detect and print a suggestion to stderr, and the work still happens in an agent session
on a human's say-so. The alternative, a hook shelling out to something that writes to the repo,
is the separate service §1 rules out. Both exit 0 unconditionally: a hook that blocks gets
disabled within a week and takes the useful ones with it.

One sharp edge, documented at the point of use: `core.hooksPath` **replaces** the hook directory
entirely, so any existing `.git/hooks` content stops running the moment it is set. Where a repo
already has hooks, the two files are symlinked individually instead.

**Harness.** A worktree manager that already knows about branch creation and landing can fire
the events directly. The contract it needs is small:

```
branch.start     { branch, base_ref }
branch.ready     { branch, base_ref }
review.round     { branch, anchor_sha }
conflict.raised  { operation: merge|rebase|cherry-pick|revert, paths[] }
branch.landed    { branch, merge_sha, base_ref }
```

Each payload carries only refs and SHAs. No state is passed between events; everything is
re-derived from git at handling time. An event that never fires costs correctness nothing —
the next skill invocation derives what it needs.

## 6. Skill contracts

Every skill declares what it reads and what it writes. Composability depends on it.

| Skill | Reads | Writes | Gate |
|---|---|---|---|
| `baseline-scan` *(was capture-base)* | git, CI config, `.gitattributes`, `CODEOWNERS` | `.git/intent/base.md` | auto |
| `capture-diff` | git, cache, own note | `.branch-notes/<branch>.md` | append |
| `collision-scan` | git, others' notes via `git show` | — | auto |
| `semantic-scan` | git, call sites | — | auto |
| `bisect-report` | git, runs the suite | — | *runs* |
| `review-diff` | git, own note, cache, policy | — | auto |
| `resolve-conflicts` | git stages, both notes, policy | — | propose |
| `merge-order` | git, all queued notes via `git show` | — | auto |
| `onboard-file` | git, cache, archive | — | auto |
| `release-notes` | git, archive | — | auto |
| `reconcile-notes` *(was prune-notes)* | git, notes, cache anchor | archive moves, cache invalidation | archive / confirm |

Eleven skills, three renamed, one materially widened. `baseline-scan` moves out of the "writes
durable state" group entirely — after §2.1 it writes only a cache, which puts it with the
derivers rather than with `capture-diff`.

## 7. File formats

### 7.1 `.branch-notes/<branch>.md`

Append-only. Never rewrite an existing entry: a decision recorded on Tuesday describes what was
true on Tuesday, and editing it destroys the record of the reversal, which is often the most
valuable thing in the file.

```markdown
# feature/rate-limit

## Requirement
PROJ-412 — rate limiting for outbound requests.

## What this does
Wraps `dispatch()` in a token-bucket limiter, configured by RATE_LIMIT_RPS.

## Why this shape
- 2026-08-04 — Stripe rate-limits per API key, not per IP, so the bucket keys on
  credential rather than connection. This is why it lives in the client rather
  than in middleware.
- 2026-08-06 — Tried a decorator on the retry loop first. Retries re-enter
  dispatch, so it double-counted every retried request.

## Must survive a conflict
The limiter has to wrap retries, not just first attempts. If this merges with a
refactor that relocates dispatch, the limiter moves with it.

## Open
Exhaustion behavior is unspecified and untested.

---
Last captured at c81f0a2 · 2026-08-06
```

Dates under *Why this shape* are required. The reversal on the 6th only means something against
the attempt on the 4th, and an undated list reads as simultaneous.

`Last captured at` is normative — it is the anchor `review.round` compares against. A note
without it cannot be checked for drift.

### 7.2 `.git/intent/base.md`

Generated. Carries `Generated at: <sha>`. Contains no prose a human authored — if a claim in it
could not be recomputed tomorrow from the same history, it belongs in `ARCHITECTURE.md`.

### 7.3 `.branch-notes/_archive/<branch>.md`

Identical format, moved by `reconcile-notes`. Path structure mirrored so `feature/rate-limit` archives
to `_archive/feature/rate-limit.md` rather than colliding with `hotfix/rate-limit`.

## 8. Invariants

Testable. Each one names a way the layer could rot into something worse than nothing.

- **I1** No skill writes to a tracked source file.
- **I2** Every committed intent file arrives through a PR and is reviewed there.
- **I3** Notes are append-only and dated.
- **I4** Nothing derivable from git is ever asked of a human. This is the adoption constraint,
  and it outranks completeness.
- **I5** Derived state is never authoritative over code. On disagreement, the code is right and
  the cache is stale.
- **I6** Every skill degrades gracefully to diff-reading on a repo with no notes.
- **I7** Cross-branch reads go through `git show <ref>:<path>`, never `cat`.
- **I8** Policy is read from `.gitattributes` and `CODEOWNERS`, never written to them, and any
  policy that would skip verification or defer to one side is confirmed with a human before it
  is acted on.
- **I9** Every argument has a derived default, and every skill reports which default it used.
  Deriving silently is not the goal — a wrong default that goes unreported produces output that
  looks completely normal, which is strictly worse than having asked.
- **I10** No skill assumes `refs/remotes/origin/HEAD` exists. It is written by `git clone` and
  not by `git remote add` + `fetch`, so it is absent in most CI checkouts. Skills fall back
  through the conventional trunk names, report which answered, and ask when none do.

## 9. Decisions taken, and what would reopen them

**The derived cache is uncommitted.** Settled. The reasoning holds only as long as the file stays
purely derived — the moment anyone wants one hand-written line in it, the argument collapses and
it should become a committed file with a `-merge` attribute instead. That is the trigger to watch
for, and it will present itself as a reasonable small request.

**`reconcile-notes` splits its gate: archive automatically, confirm before deleting.** Settled, on the
finding in §3.6 — notes are branch-local, so a note reaches the integration branch only by
landing, which makes the abandoned-work pile that the original prune step was built to sweep
nearly empty by construction. Archiving is the ~99% path and holding it behind a proposal leaves
a chore after every merge. Deleting is rare and irreversible, so it keeps its gate.

**`branch.ready` still has no clean detector.** It depends on someone saying so, and it is the
one genuinely open item. A pull-request-open webhook would detect it precisely, and is exactly
the service §1 rules out. Left as-is: the event fires when a human runs `/capture-diff` or
`/review-diff`, which is when they were going to run it anyway.

**`decision.made` is undetectable by design, not by omission.** It leaves no git state — no
commit, no ref, nothing a terminating command could observe. It is reachable only from inside a
session that was present when the decision happened, which is why the agent-rule transport is
the one that cannot be replaced by a hook. This is the single point where the layer depends on a
convention rather than a mechanism, and it should stay stated plainly rather than papered over.
