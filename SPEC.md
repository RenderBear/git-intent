# git-intent — specification

Git records what changed with total precision and why it changed not at all. The approach
someone tried on Tuesday and abandoned on Wednesday is gone, because it was never written down —
and no tooling over commit text recovers it.

git-intent stores that missing half and nothing else. It keeps the complement of what git keeps,
derives everything else on demand, and hands the result to whoever acts next. The layer is a
small amount of state over git refs; every act of judgment is delegated to a skill.

**Scope: multi-agent work.** The payoff is largest when more than one agent touches a codebase —
whether at the same time (two agents on two branches) or across time (one agent abandons an
approach, and a later session, a different agent, or a reviewer picks up the branch). The first
case is collision, semantic, and merge-order analysis. The second is testimony: a handoff of
reasoning that would otherwise be lost between sessions. A single agent on a single branch in one
session needs almost none of this; every additional agent makes it matter more.

## 1. Non-goals

Each is a thing this could become and must not.

- **Nothing has to be running.** No daemon, server, database, or background process, and no
  component whose absence stops a skill working. An optional transport (§5) may run in CI, but a
  missing check costs you the check, never correctness.
- **Not a git wrapper.** Nobody needs a nicer `git merge`. If git already does it, this defers.
- **Not an ADR system.** Architecture decisions live in `README.md`, `ARCHITECTURE.md`,
  `CHANGELOG.md`, `docs/adr/`. This does not compete with them.
- **Not a source editor.** No skill writes a tracked source file. Resolutions, archives, and
  prunes are emitted as commands a human runs.
- **Not an orchestrator.** It does not create branches, manage worktrees, or run agents. It reads
  what an orchestrator produced and says what it was for.
- **Not required.** Every skill runs against a repo that never heard of this one. The layer makes
  them sharper, never possible.

## 2. State

One question sorts every artifact: **what does deleting it cost?**

| Kind | Example | Deleting it costs | Location |
|---|---|---|---|
| Cache | churn, hotspots, ownership, coupling, path sets | time — it recomputes | `.git/intent/` |
| Testimony | the abandoned approach, what must survive | the reasoning, permanently | `.branch-notes/<branch>.md` |
| Record | testimony for work that has landed | the same, plus everyone downstream | `.branch-notes/_archive/` |
| Policy | regenerate don't merge; who signs off | git stops enforcing | `.gitattributes`, `CODEOWNERS` |

Cost decides the *kind*. Audience decides the *location*: cache read only by agents lives in
`.git/intent/`; anything a human is meant to browse is committed, because nobody opens `.git/`.

### 2.1 Cache

`.git/intent/base.md` holds what the repo is, computed from git — not committed, because another
clone reproduces it from the same history. Committing it would only buy merge churn and an
authority it hasn't earned.

Anchor it to the **common** git dir, so five worktrees share one cache instead of computing five:

```bash
INTENT="$(git rev-parse --git-common-dir)/intent"
```

It carries `Generated at: <sha>`, and is stale iff `git diff --name-only <sha>..HEAD` touches a
structural input — top-level directories, dependency manifests, CI config. When in doubt,
regenerate; it is a handful of git commands.

It holds only what git can answer: structure and entry points; hot and dormant regions from
churn; ownership and bus factor from authorship; coupling from commit co-occurrence; per-branch
changed-path sets; test/lint/build commands read from CI config; and pointers to the prose docs,
never restatements of them. Hot-versus-dormant is what justifies the file — a module rewritten
three times this quarter and one untouched for two years demand opposite caution.

### 2.2 Testimony — committed, and branch-local

`.branch-notes/<branch>.md` exists only on the branch it describes. That is the property that
keeps the scheme free of self-conflict: two branches never contend for one note, because each
writes only its own.

The consequence is a read rule. Another branch's note is not in your worktree:

```bash
cat .branch-notes/other-branch.md                              # WRONG — not here
git show origin/other-branch:.branch-notes/other-branch.md     # RIGHT
```

A `cat` returns nothing, silently, and the skill proceeds on inference while reporting it read
testimony. This is invariant **I7**.

### 2.3 Reading the other side of a merge

Integration branches — `develop`, `main`, `release/*` — never have a note. They are
accumulations of work, not units of it. The incoming side's intent is the `_archive/` entries of
the branches that landed since the fork point, of which usually one or two touch the conflicted
paths — better testimony than one note would be, each written by whoever made that change.

Any skill reading the other side walks a ladder and reports which rung answered, **and why it
stopped there**:

| Rung | Source | Strength |
|---|---|---|
| 1 | the branch's own note, via `git show` | testimony |
| 2 | `_archive/` entries for what landed in the range | testimony |
| 3 | commit messages and PR bodies | attributed inference |
| 4 | the diff alone | reconstruction |

Rungs 3 and 4 are the normal case and produce usable output. The label matters because a
composition built on rung 2 and one on rung 4 deserve different trust — and the reason carries
weight the bare number doesn't. "Rung 4 — cherry-pick, no branch name to look up" and "rung 4 —
no archive in this repo yet" are different facts, and only the second improves with time.

### 2.4 Record — testimony that has landed

When a branch lands, `reconcile-notes` moves its note to `.branch-notes/_archive/<branch>.md`.
The note stops being perishable (nothing more will be appended), stops being branch-local (it
now lives on the integration branch), and changes retrieval key — nobody remembers `sam/fix-2`
in a year, so archived notes are found by the paths in their frontmatter, not by branch name.

Archived notes feed `release-notes`, `onboard-file`, and rung 2 above. They are the long-lived
half of the system and the reason capture is worth doing.

### 2.5 Policy — where git already reads it

Merge policy is `.gitattributes`; sign-off policy is `CODEOWNERS`. Neither is reinvented here.

```gitattributes
src/vendor/**   -merge          # regenerate; never hand-merge
db/migrations/* merge=ours      # never renumber to resolve
```

Git honours these, so the rule acts rather than advises, and it arrives in a file reviewers treat
as infrastructure. Skills **read** these files and never write them.

## 3. When to run each skill

Nothing here dispatches. There is no event loop; a skill runs because a human typed the command,
an agent rule fired it, or a hook printed a suggestion (§5). What follows is the situation each
skill answers, not a lifecycle it reacts to.

| Situation | Skill | Gate |
|---|---|---|
| Starting a branch — who else is in this code? | `collision-scan` | auto |
| A decision was made or an approach dropped | `capture-diff` | append |
| Preparing a branch for review | `capture-diff`, `review-diff` | append |
| Reviewing, or checking against a requirement | `review-diff` | auto |
| Several branches queued to merge | `merge-order` | auto |
| A merge/rebase/cherry-pick left conflicts | `resolve-conflicts` | propose |
| A branch just landed | `reconcile-notes` | archive / confirm |
| A clean merge you don't trust | `semantic-scan` | auto |
| Cutting a release | `release-notes` | auto |
| Why is this file like this? / What broke? | `onboard-file`, `bisect-report` | auto / runs |

Most of these are answerable at any later time from repository state, so missing the moment costs
a delay, not the answer (§3.7). Two are not: a conflict's resolution window closes once resolved,
and an uncommitted worktree evaporates within the hour. One thing cannot be recovered at all — a
decision that was never written down.

### 3.1 Starting a branch — `collision-scan`

Two populations, in order of urgency:

```bash
git worktree list --porcelain          # other agents on this machine
git -C "$WT" status --porcelain        # modified, staged, AND untracked
```

Local worktrees first. An agent three minutes into a task has written files and committed
nothing; no remote scan sees that, and it is the work most cheaply redirected. Use `status
--porcelain`, not `diff --name-only HEAD` — a file created and never `git add`ed is untracked,
and a diff against `HEAD` omits it, which is most of what three minutes of work looks like.

Remote branches are ranked by **liveness** — commit recency, commits ahead, divergence behind,
whether it already landed — never filtered by date. A date window drops a nine-day-old branch
rewriting the function you are wrapping and keeps a README typo fix from this morning. Anything
below the cut that shares a path is still named.

### 3.2 A decision was made — `capture-diff`

An approach tried and dropped, a vendor limit forcing an ugly shape, a timeout picked out of the
air. `capture-diff` appends while the reasoning is still in context.

Nothing detects this — a decision is a mental act no command observes — so the layer depends here
on a convention (an agent rule, §5) rather than a mechanism. What *is* mechanical is detecting
that it didn't happen:

```bash
test -f ".branch-notes/$BRANCH.md"                       # did capture ever run?
grep -c '^- 20[0-9][0-9]-' ".branch-notes/$BRANCH.md"    # dated reasoning, or a stub?
```

And the highest-value case — an approach tried and abandoned — leaves a fingerprint even after
the diff erases it:

```bash
# touched in this branch's history, identical to base in the final diff
comm -23 <(git log --format='' --name-only $BASE..HEAD | sort -u) \
         <(git diff --name-only $BASE..HEAD | sort -u)

git log --oneline --diff-filter=D $BASE..HEAD -- <path>   # the commit that removed it
git reflog --date=short                                   # work a rebase or reset dropped
```

A file touched in three commits and unchanged in the net diff is something tried and undone —
invisible to every reviewer, because review reads the diff and the diff is where the evidence was
deleted. This turns "was anything abandoned?" (a shrug) into "`decorator.py` was added in
`a1b2c3d` and removed in `118e9f2` — should that be in the note?" (an answer). The deadline is
landing: once `reconcile-notes` archives the note, no later run recovers what was never written.

### 3.3 Conflicts — `resolve-conflicts`

Entry condition, and the only one: `git ls-files -u` is non-empty. Empty means nothing to
resolve, and the skill says so and stops — it does not predict conflicts, which is
`collision-scan` before the fact and `semantic-scan` after.

Five operations produce unmerged paths, and **the operand names invert between them.** In a
rebase, `ours` is the upstream you are replaying onto and `theirs` is your own commit — the
reverse of a merge. Taking `--ours` out of merge habit is the most common way a branch's work
disappears while the result looks clean.

```bash
G=$(git rev-parse --git-dir)                            # never a literal .git
git rev-parse -q --verify MERGE_HEAD                    # merge
ls -d "$G/rebase-merge" "$G/rebase-apply" 2>/dev/null   # rebase — ours/theirs INVERTED
git rev-parse -q --verify CHERRY_PICK_HEAD              # cherry-pick
git rev-parse -q --verify REVERT_HEAD                   # revert
```

Cherry-pick, revert, and stash pop yield a commit and no branch name, so the incoming note can't
be located and intent falls to rung 3 or 4 — the output says so. Gate is **propose**: a plausible
wrong resolution passes review, which is what makes it expensive, so nothing is written to the
tree.

### 3.4 Review — `review-diff`, and drift

`review-diff` produces the risk-ordered summary, or checks the branch against a requirement.
While it is reading both the note and the diff, it also checks the note hasn't drifted:

```bash
ANCHOR=$(sed -n 's/^captured_at: *//p' .branch-notes/$BRANCH.md)
git log --oneline $ANCHOR..HEAD
```

Non-empty means the note is behind the branch — and since `reconcile-notes` archives whatever
note is in the tree at landing, an un-re-anchored note ships its pre-review version forever.
Behavioral commits since the anchor mean `capture-diff` should append and re-anchor; review nits
mean re-anchor alone. This is a finding for the author, never fixed silently.

### 3.5 A branch landed — `reconcile-notes`

Post-landing, on the integration branch:

1. **Archive the landed note** to `_archive/<branch>.md`, mirroring the path so slash-named
   branches stay findable. A note whose `captured_at` predates the tip is archived **flagged
   stale**, never refused — by archive time that is the normal case, and after a squash merge the
   branch is gone and the tip won't resolve at all.
2. **Delete abandoned notes** — branch gone, commits never landed. Squash merges look unmerged,
   so *unknown resolves to archive*, never delete. The failure modes are wildly asymmetric.
3. **Invalidate the cache** and report which of its claims the landing contradicted.

`semantic-scan` also fits here: the merge that just completed cleanly is the population it checks.

### 3.6 A clean merge you don't trust — `semantic-scan`

One branch changes a contract, another depends on the old behaviour, the files never touch, the
merge is clean, both suites pass, and it breaks in production. That is what this looks for.

It is expensive, and mostly finds nothing — its yield is real only when branches diverged long
enough to stop seeing each other, in code a type checker doesn't already guard. So before deep
analysis, rank pairs cheaply and look only where the ranking points (§3.7).

### 3.7 Ranking where to look

When you have many branch pairs and can afford to analyse few, score each on divergence in both
directions, fork-point age, disjoint surface, interface weight, and centrality from the cache.
This is triage, run when you're about to spend on analysis or asking "which long-lived branch is
riskiest" — not a standing monitor.

`semantic-scan` records what it examined, keyed on the tips it saw:

```
checked: feature/billing-v2@8e8a927 develop@e094dde
```

SHAs, not a timestamp: the question at ranking time is whether *this* state was examined, and a
pair analysed yesterday whose side has moved ten commits since is stale in the one direction that
loses a finding. A ranking score is never a finding — "exposed" and "broken" are different
claims, and conflating them turns the ranking into noise.

### 3.8 Catching up what nobody watched

Review and merge happen in a browser tab, where no agent session exists, so the skills that
should run at landing often don't. That is survivable because their effects are functions of
current state, recomputable later: any skill invoked on the integration branch first archives
notes whose branches are gone, flags drifted anchors, and regenerates a stale cache, then does
its own job.

The rule that keeps this safe: **convergence repairs bookkeeping, never testimony.** Archiving
moves a file; regenerating rebuilds a cache; neither invents a claim. Drift is *reported*, not
fixed, because fixing it means writing reasoning into someone else's note.

## 4. Gates

Three classes. This is the whole human-in-the-loop design, and it needs no service because the
loop is the pull request.

- **Auto** — read-only derivation, or a write to `.git/intent/`. No approval; nothing durable, a
  mistake survives nothing.
- **Append** — a write to `.branch-notes/<branch>.md`. No approval at write time: the file lands
  in the PR diff and is reviewed there. **The PR is the gate.**
- **Propose** — anything touching source, destructive, or irreversible. The skill emits reasoning
  and exact commands; a human runs them.

An append is a *claim* and is cheap to be wrong about; a propose is a *change* and is not.

Two skills sit outside this and say so where they act. `bisect-report` executes, because
bisecting can't be done otherwise. `reconcile-notes` archives landed notes itself — a `git mv`
inside `.branch-notes/`, staged not committed, undo printed — because archiving is the ~99% path
after every landing and a proposal nobody runs is how the folder rots. Deletion keeps its gate:
it destroys reasoning that exists nowhere else.

## 5. Transports

How a skill fires is pluggable. All optional, freely mixed, none required.

- **Human.** Type the slash command. Always works, and the floor everything else builds on.
- **Agent rule.** A block in `CLAUDE.md` / `AGENTS.md` / `.cursorrules`. The only transport
  present at the moment a decision happens, so the only one that can prompt capture. It loads on
  every turn, so it carries trigger conditions and nothing else — format lives in the skill.
- **Git hook.** `hooks/` ships `post-checkout` and `post-merge`; they print a suggestion to
  stderr and exit 0. A hook has no session and cannot handle an event, only nudge. Both exit 0
  unconditionally — a hook that blocks gets disabled within a week and takes the useful ones
  with it. `core.hooksPath` *replaces* `.git/hooks`, so where a repo has hooks already, symlink
  the two files individually.
- **CI.** `ci/` ships a POSIX script and a workflow example. This is the only transport that
  reaches the browser tab where review and merge happen. It runs the mechanical checks — note
  present, not a stub, `captured_at` not drifted, any assertions resolving — and comments. **Only
  a violated assertion fails the build**; drift and unresolvable anchors are comments, because a
  check that blocks on a rename gets switched off. Provider-specific YAML is the one thing here
  that isn't plain git, so the logic lives in the script and porting is a new wrapper.

A harness (a worktree manager) can also call skills directly; it needs only refs and SHAs, and
re-derives everything from git at call time.

## 6. Skill contracts

| Skill | Reads | Writes | Gate |
|---|---|---|---|
| `baseline-scan` | git, CI config, `.gitattributes`, `CODEOWNERS` | cache | auto |
| `capture-diff` | git, cache, own note | `.branch-notes/<branch>.md` | append |
| `collision-scan` | git, worktrees incl. uncommitted, others' notes, cache | cache (path sets) | auto |
| `semantic-scan` | git, call sites, notes and archive, cache | cache (ranking) | auto |
| `bisect-report` | git, runs the suite | — | *runs* |
| `review-diff` | git, own note, cache, policy | — | auto |
| `resolve-conflicts` | git stages, both sides via the §2.3 ladder, policy | — | propose |
| `merge-order` | git, queued notes via `git show`, cache | — | auto |
| `onboard-file` | git, cache, archive | — | auto |
| `release-notes` | git, archive | — | auto |
| `reconcile-notes` | git, notes, archive, cache anchor | archive moves, cache invalidation | archive / confirm |

Only `capture-diff` writes testimony. Cache writes are not durable — anything there recomputes.

**The two scans do not overlap.** `collision-scan` works the paths two branches **share** (will
they collide when they land); `semantic-scan` works the paths they **don't** (did they break each
other without colliding). A large disjoint surface raises risk in the second and means nothing in
the first. Where one finds itself in the other's population it hands off by name and stops. The
path intersection is computed once into the cache.

## 7. File formats

### 7.1 `.branch-notes/<branch>.md`

Append-only. Never rewrite an entry — a decision recorded Tuesday describes what was true
Tuesday, and editing it destroys the record of the reversal, often the most valuable thing there.

```markdown
---
branch: feature/rate-limit
requirement: PROJ-412
captured: 2026-08-06
captured_at: c81f0a2
merged:
paths:
  - src/client.py
  - src/config.py
symbols:
  - src/client.py:dispatch
---

# feature/rate-limit

## What this does
Wraps `dispatch()` in a token-bucket limiter, configured by RATE_LIMIT_RPS.

## Why this shape
- 2026-08-04 · in-session — Stripe rate-limits per API key, not per IP, so the
  bucket keys on credential rather than connection; hence in the client, not middleware.
- 2026-08-06 · in-session — Tried a decorator on the retry loop first. Retries
  re-enter dispatch, so it double-counted every retried request.

## Must survive a conflict
The limiter has to wrap retries, not just first attempts. If this merges with a
refactor that relocates dispatch, the limiter moves with it.

## Open
Exhaustion behavior is unspecified and untested.
```

Dates under *Why this shape* are required — a reversal only means something against the attempt
it reversed, and an undated list reads as simultaneous. Each entry marks its provenance:
`in-session` (written while the reasoning was in context) or `reconstructed` (recovered later
from a §3.2 fingerprint and confirmed). The distinction matters most to a reader who never opens
the code, for whom the note is the only account of what happened.

Three fields are normative. `captured_at` is the drift anchor (§3.4); a note without it reads as
current forever. `paths` and `symbols` are the retrieval index, and must be written at capture
time — a squash merge destroys the branch-to-files mapping, after which the only way to find an
archived note is grepping prose for a filename someone happened to type. Both are free, already
computed from `git diff --name-only` and the `-U0` hunk headers. `merged` is left empty and
filled by `reconcile-notes` on archive.

**Assertions (optional).** The *Must survive a conflict* prose is what a human reads and an agent
reasons from. A note may also carry a cheap tripwire — the same claim in a form one `git grep`
can check — so `review-diff`, `resolve-conflicts`, and CI can flag when it stops holding:

```yaml
assert:
  - check: contains src/client.py:dispatch RateLimiter
    why: the limiter has to wrap retries, not just first attempts
```

Three predicates, each one grep: `exists <path>[:<symbol>]`, `contains <path>[:<symbol>]
<needle>`, `absent <needle> [<pathspec>]`. The needle is file-scoped even when the anchor names a
symbol — extracting a symbol's body is brittle in shell, and the value here is being one cheap
grep, so it checks presence in the file, not enclosure. Report that limit where you report the
result.

Evaluation is **anchor-first**, and this is the one rule that matters: resolve the anchor, *then*
the predicate. Three outcomes —

- **holds** — anchor resolved, predicate true.
- **violated** — anchor resolved, predicate false. Something that had to survive did not.
- **unresolvable** — the anchor is gone (renamed, extracted, moved). A **question, not a
  failure**, and it never blocks. Every legitimate refactor moves an anchor, and a rename
  reported as a violation teaches people to ignore violations, which costs the real ones.

`capture-diff` writes the predicate from the paths and symbols it already has and puts the
sentence in `why:`; a human is never asked to hand-write one. It is a tripwire, not a test — a
weak proxy that occasionally catches a real regression for almost no cost, and no note is
worse for having none.

### 7.2 `.git/intent/base.md`

Generated, carrying `Generated at: <sha>`. No prose a human authored — anything that couldn't be
recomputed tomorrow belongs in `ARCHITECTURE.md`. Any output resting on it should state the SHA
it read, since the reader can't see into `.git/` to judge the cache's age.

### 7.3 `.branch-notes/_archive/<branch>.md`

Identical format, moved by `reconcile-notes` with `merged` filled, path mirrored, never rewritten
after. Frozen means assertions in it are **not checked** — an archived note can't be corrected,
so the first rename after landing would leave it permanently violated. Assertions are checked for
live branches only.

## 8. Invariants

Each names a way the layer could rot into something worse than nothing.

- **I1** No skill writes a tracked source file.
- **I2** Every committed intent file arrives through a PR and is reviewed there.
- **I3** Notes are append-only and dated; assertions supersede rather than change.
- **I4** Nothing derivable from git is asked of a human. This outranks completeness.
- **I5** Cache is never authoritative over code. On disagreement the code is right.
- **I6** Every skill degrades to diff-reading on a repo with no notes.
- **I7** Cross-branch reads go through `git show <ref>:<path>`, never `cat`, and every output
  states which rung of §2.3 answered and why.
- **I8** Policy is read from `.gitattributes` / `CODEOWNERS`, never written, and any policy that
  would skip verification or defer to one side is confirmed with a human first.
- **I9** Every argument has a derived default and every skill reports the default it used — a
  wrong default that goes unreported looks completely normal, which is worse than a question.
- **I10** No skill assumes `refs/remotes/origin/HEAD` exists; it is absent in most CI checkouts.
  Fall back through the conventional trunk names, report which answered, ask when none do.
- **I11** No skill hardcodes `.git`; in a linked worktree it is a file. Use `--git-dir` /
  `--git-common-dir`.
- **I12** Branch relevance is ranked by liveness, never filtered by date, and whatever falls
  below a cut is counted in the output, not dropped.
- **I13** An assertion whose anchor no longer resolves is `unresolvable`, never `violated`, and
  never blocks.

## 9. Open questions

Two things are genuinely unsettled, and both should stay stated rather than papered over.

**Will capture fire?** The testimony half rests on someone — reliably, an agent under a rule —
choosing to run `capture-diff`. Nothing enforces it, and if it fires rarely the differentiated
value is thin. This is the bet the project is making, and it is more defensible for instructable
agents than it ever was for humans. Worth measuring rather than assuming.

**`branch.ready` has no clean detector.** "The branch is ready for review" depends on someone
saying so. A PR-open webhook would detect it and is exactly the service §1 rules out, so it stays
a thing a human triggers by running `/capture-diff` or `/review-diff` when they were going to
anyway.
