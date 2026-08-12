# git-intent — specification

Git records what changed with total precision and why it changed not at all. The gap is not a
missing feature; it is structural. No amount of tooling over commit text recovers the approach
someone tried on Tuesday and abandoned on Wednesday, because it was never written down.

git-intent is the layer that closes that gap, and nothing more. It stores the complement of
what git stores, derives everything else on demand, and hands the result to whoever acts next.

The layer owns **intent lifecycle** — when intent gets captured, carried, reconciled, and
retired — and delegates every act of judgment to a skill. What remains here is a state machine
over git refs. The intelligence is rented.

## 1. Non-goals

These are load-bearing. Each one is a thing this could become and must not.

- **Nothing has to be running.** No daemon, no server, no database, no background process — and
  no component whose absence stops a skill working. Every moment is detectable from git state by
  a command that terminates. This is the form of the rule that survives §6's CI transport, which
  *is* something someone operates but which nothing depends on: an absent check costs you the
  check, never correctness (I6). "Not a service" was the old wording and it drew the line in the
  wrong place — the question was never whether a process exists, but whether anything breaks
  when it doesn't.
- **Not a git wrapper.** Nobody needs a nicer `git merge`. If git already does it, this defers.
- **Not an ADR system.** Decisions about architecture live in `README.md`, `ARCHITECTURE.md`,
  `CHANGELOG.md`, and `docs/adr/`. Those have their own review discipline and this must not
  compete with it.
- **Not a source editor.** No skill writes to a tracked source file. Ever. Resolutions,
  archives, and prunes are emitted as commands a human runs.
- **Not an orchestrator.** It does not create branches, manage worktrees, or run agents. It
  reads what an orchestrator produced and tells whoever acts next what it was for.
- **Not required.** Every skill runs against a repo that has never heard of this one. The
  layer makes them cheaper and sharper, never possible.

## 2. State

One question sorts every artifact: **what does deleting it cost?**

| Kind | Example | Deleting it costs | Default location |
|---|---|---|---|
| Cache | churn, hotspots, ownership, coupling, path sets, exposure | time | `.git/intent/` |
| Testimony | the abandoned approach, what must survive | the reasoning, permanently | `.branch-notes/<branch>.md` |
| Record | testimony for work that has landed | the same, plus everyone downstream | `.branch-notes/_archive/` |
| Policy | regenerate don't merge; who signs off | git stops enforcing | `.gitattributes`, `CODEOWNERS` |

Two earlier forms of this taxonomy each failed on a specific artifact. Sorting by *who could
produce* an item could not place an archived note, which is author-only but neither perishable
nor branch-local. Sorting by *regenerability* could not place §4.1's record of which pairs have
already been analyzed — that is not recoverable from history, yet losing it costs only a
redundant re-analysis. Cost of deletion places both, and it is the property the rules actually
depend on.

**Cost decides the kind. Audience decides the location.** These are separate rules, and
conflating them is what made "derived" and "lives in `.git/intent/`" look like one fact. Cache
written for agents belongs in `.git/intent/` because nothing else needs to see it. Cache written
for a human must be committed, because nobody browses `.git/` in any interface a human uses —
and it carries `-merge` in `.gitattributes` (§2.5) so it regenerates rather than conflicting.
The objection to committing derived state was never that it was derived; it was merge churn and
unearned authority, and `-merge` plus a generated-file header are what answer those.

### 2.1 Cache

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
- per-branch changed-path sets, so two skills needing the same intersection compute it once
- pairwise exposure scores, and the tip SHAs at which each pair was last analyzed (§4.1)
- test, lint, and build commands, read from CI config verbatim
- pointers to `README.md` / `ARCHITECTURE.md` / `docs/adr/`, never restatements of them

Hot-versus-dormant is the section that justifies the file. A module rewritten three times this
quarter and one untouched for two years demand opposite caution, and nothing in a directory
listing says which is which.

### 2.2 Testimony is committed, and branch-local by construction

`.branch-notes/<branch>.md` exists only on the branch it describes. This is not an accident to
work around — it is the property that makes the scheme free of self-conflict. Two branches never
contend for the same note file, because each only ever writes its own.

The consequence is a read rule:

```bash
# WRONG — that path does not exist in your worktree
cat .branch-notes/other-branch.md

# RIGHT
git show origin/other-branch:.branch-notes/other-branch.md 2>/dev/null
```

A silent miss here degrades a skill to diff-guessing while it reports having read testimony.
The failure produces no error and no empty-string check catches it unless one is written, which
is why this is invariant **I7** rather than a note in a workflow.

### 2.3 Integration branches have no note, and never will

`develop`, `main`, and `release/*` are not units of work; they are accumulations of them. There
is nothing for `capture-diff` to have written and the absence is not a gap.

This is a load-bearing fact rather than an edge case, because the most common conflict in a
gitflow-shaped repo is a feature branch against `develop`. The incoming side's intent is the
`_archive/` entries of branches that landed since the fork point:

```bash
FORK=$(git merge-base HEAD "origin/$OTHER")
git log --merges --format='%s' "$FORK..origin/$OTHER"
git show "origin/$OTHER:.branch-notes/_archive/<branch>.md" 2>/dev/null
```

Usually one or two of fifteen actually touch the conflicted paths, and that subset is *better*
testimony than a single note would be, because each entry was written by whoever made that
specific change.

Any skill reading the other side of a merge walks a ladder and reports which rung answered:

| Rung | Source | Claim strength |
|---|---|---|
| 1 | the branch's own note, via `git show` | testimony |
| 2 | `_archive/` entries for what landed in the range | testimony |
| 3 | commit messages and PR bodies | attributed inference |
| 4 | the diff alone | reconstruction |

Rungs 3 and 4 are the normal case in most repos and produce perfectly usable output. What
matters is the label: a composition built on rung 2 and one built on rung 4 deserve different
trust from whoever applies them, and only the output can distinguish them.

The label carries the **reason** the ladder stopped there, not just the number. "Rung 4" alone
reads as the tool failing. "Rung 4 — cherry-pick, no branch name to look a note up by" and
"rung 4 — this repo has no archive yet" are different facts, and only the second improves with
time. A repo adopting this mid-life answers rung 3 or 4 on nearly everything for weeks, which is
correct, and an unexplained level makes correct output look broken during exactly the window
where someone is deciding whether to keep using it.

### 2.4 Record — testimony that has landed

When a branch lands, `reconcile-notes` moves its note to `.branch-notes/_archive/<branch>.md`.
That is a state transition, not filing. Three things change:

- It stops being perishable. The work is done; nothing further will be appended.
- It stops being branch-local. It now lives on the integration branch and is read by people who
  never saw the branch.
- Its retrieval key changes. Nobody remembers `sam/fix-2` in eighteen months, so archived notes
  are found by the paths and symbols in their frontmatter (§8.1), not by branch name.

Archived notes are the input to `release-notes`, `onboard-file`, and rung 2 above. They are the
long-lived half of the system and the reason capture is worth doing at all.

### 2.5 Policy lives where git already reads it

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

Eight moments. **One is unrepeatable, three have windows that close, and four converge** — their
effect is derivable from repository state at any later time, so missing one costs a delay rather
than the thing itself. That split is the transport argument in full: nothing has to be watching,
because most of what could be missed can be caught up afterwards.

| Moment | Detector | Actor | Gate | If nobody was watching |
|---|---|---|---|---|
| `decision.made` | *none — see §3.2* | `capture-diff` | append | **lost.** No commit, no ref, nothing to recover from |
| `branch.start` | `git rev-list --count $BASE..HEAD` = 0 | `collision-scan` | auto | **window closes.** Uncommitted work is not in git at all |
| `conflict.raised` | `git ls-files -u` non-empty | `resolve-conflicts` | propose | **window closes.** Empty by construction once resolved |
| `review.round` | `git log <anchor>..HEAD` non-empty | `review-diff` → `capture-diff` | append | drift converges; the capture it should trigger does not |
| `branch.ready` | ahead of base, human says so | `capture-diff`, `review-diff` | append | converges |
| `queue.forming` | ≥2 unmerged branches ahead of base | `merge-order` | auto | converges, though the answer's value decays |
| `branch.landed` | commits reachable from base ref | `reconcile-notes`, `semantic-scan` | archive / confirm | converges |
| `release.cut` | a tag appears on the base ref | `release-notes` | auto | converges |

The convergent rows are, not coincidentally, the ones that happen where no agent is. Review and
merge occur in a browser tab, so no transport in §6 reaches them — and the long-lived half of the
system depends on `branch.landed`, which is a button on a web page. **Convergence (§4.2) is what
makes that survivable**: the effect is recomputed on the next invocation rather than missed.

The three closing windows are what a transport genuinely has to reach, and the honest status is
that only one of them is reliably reachable. `conflict.raised` happens in a terminal because git
forces it there, which is why `resolve-conflicts` is the most dependable skill in the set.
`decision.made` is reachable only from a session that was present, and `branch.start`'s
uncommitted population evaporates within the hour.

Earlier versions of this section claimed eight events and six detectors. Six *are* detectable,
but nothing dispatches on them: hooks print to stderr and exit, and every other transport waits
for someone to type a command. The system is pull with prompts, and describing it as event-driven
was vocabulary the mechanism never earned.

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
while it is still cheap to talk. Read-only, no gate. Refresh the cache here if stale — it is the
cheapest moment, and everything downstream reads it.

Two populations, scanned in order, because they carry different urgency:

```bash
git worktree list --porcelain          # parallel agents on this machine
git -C "$WT" status --porcelain        # modified, staged, and untracked
```

Local worktrees come first. An agent three minutes into a task has written files and committed
nothing; no remote scan will ever see that work, and it is the work most cheaply redirected.
This population has no note by construction — nothing has been committed — so its intent is
always rung 4 and labelled as such.

`status --porcelain`, not `diff --name-only HEAD`: a file the agent created and never added is
**untracked**, and a diff against `HEAD` does not list it. Untracked files are most of what
three minutes of work looks like, so the diff form misses precisely the population this stage
exists to find. They are also the only state in the whole model that is not in git at any
point, which is why this window closes in hours rather than at a merge boundary.

Remote branches are ranked by **liveness**, not filtered by date: commit recency, commits ahead,
divergence behind, and whether the branch has already landed. A date window drops a nine-day-old
branch that rewrites the function you are wrapping and keeps one that got a README typo fix this
morning. The liveness cut is a budget, and anything below it that shares a path is named anyway.

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
test -f ".branch-notes/$BRANCH.md"                       # did capture ever run?
grep -c '^- 20[0-9][0-9]-' ".branch-notes/$BRANCH.md"    # dated reasoning, or a stub?
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

**Commit frequency is orthogonal and should not be conflated.** Commits carry what and why for
one change; notes carry the branch-scope claims and the abandoned paths that no commit can hold.
Since a note is a tracked file, writing one *is* committing — the guidance is to commit at each
working state and append at each decision, which fire at different rates. Frequent commits do buy
the layer one thing: without them, `captured_at` and the branch tip are the same SHA and §3.4's
drift check silently always passes.

### 3.3 `branch.ready`

Before the PR. `capture-diff` derives everything derivable and asks the single question no
history can answer:

> If this conflicts with something, what has to survive?

Then `review-diff` produces the risk-ordered summary. One question, once, per branch. Any
second question is a chance for someone to decide this is not worth the trouble.

### 3.4 `review.round`

A note anchored at `c81f0a2` and three rounds of review later describes code that no longer
exists. Worse, it is the *merged* note that gets archived, so the version preserved forever is
the pre-review one.

Detection is mechanical, from the frontmatter anchor:

```bash
ANCHOR=$(sed -n 's/^captured_at: *//p' .branch-notes/$BRANCH.md)
git log --oneline $ANCHOR..HEAD
```

Non-empty means the note is behind the branch. `review-diff` reports the drift on every run —
it already reads both the note and the diff, so this costs one comparison in a skill people are
already running. If the intervening commits changed behavior, `capture-diff` appends and
re-anchors. If they were review nits, re-anchor alone.

### 3.5 `conflict.raised`

**Entry condition, and the only one:** `git ls-files -u` is non-empty.

Empty means there is nothing to resolve, and `resolve-conflicts` says so in one line and stops.
It does not predict conflicts, dry-run merges, or look for future problems — that is
`collision-scan` before the fact and `semantic-scan` after it. A skill that expands into its
neighbours' territory makes all three less trustworthy.

Five operations produce unmerged paths, and **the operand names invert between them**. During a
rebase, `ours` is the upstream you are replaying onto and `theirs` is your own commit — the
reverse of a merge. Resolving with `--ours` out of merge habit is the single most common way a
branch's work disappears while the result looks clean.

```bash
G=$(git rev-parse --git-dir)                            # never a literal .git
git rev-parse -q --verify MERGE_HEAD                    # merge
ls -d "$G/rebase-merge" "$G/rebase-apply" 2>/dev/null   # rebase — ours/theirs INVERTED
git rev-parse -q --verify CHERRY_PICK_HEAD              # cherry-pick
git rev-parse -q --verify REVERT_HEAD                   # revert
                                                        # stash pop: none of the above
```

`--git-dir`, not `.git`: in a linked worktree `.git` is a file and every hardcoded path fails,
which is precisely the multi-agent setup this layer targets.

Cherry-pick, revert, and stash pop yield a commit and no branch name, so the incoming side's
note cannot be located and intent falls to rung 3 or 4. The output says so.

This is why the skill is `resolve-conflicts` and not `resolve-merge`: the name promised one
operation and the worst failure mode lives in another.

Gate is **propose**, permanently. A plausible wrong resolution passes review, which is precisely
what makes it expensive. Nothing is written to the tree.

### 3.6 `branch.landed`

`reconcile-notes` runs post-landing and does three things:

1. **Archive the landed note** to `.branch-notes/_archive/<branch>.md`, mirroring the path so
   slash-named branches stay findable. Per §2.4 this is a state transition: the note becomes a
   record, and it is at peak usefulness at exactly the moment it looks like garbage.
2. **Delete abandoned notes** — branch gone, commits never landed. Squash merges look
   unmerged, so *unknown resolves to archive*, never to delete. The failure modes are wildly
   asymmetric.
3. **Invalidate the cache** and report which of its claims the landing contradicted.

A note whose `captured_at` predates the branch tip is archived **flagged as stale**, never
refused. By archive time the branch has landed, so `captured_at` trails the tip whenever any
commit followed capture — the normal case per §3.4 — and after a squash merge the branch is
gone and the tip does not resolve at all. Refusing would block the ~99% path that §5 exempts
from gating precisely so the folder does not rot. The flag is the whole requirement: §3.4's
drift must not become permanent *silently*, in the one skill whose entire job is not to lose
things.

`semantic-scan` also fires here: the merge that just completed cleanly is the population this
layer exists to check.

## 4. Predicates

Two things in this design are not events and were only ever filed under §3 because they fire in
the same places. A predicate is evaluated against current state by whoever happens to be running,
answers the same way regardless of when it is asked, and has no moment it can miss.

They are how the layer survives having no dispatcher. §3's four convergent moments do not need
to be caught because §4.2 catches up their effects; §3's long-lived risk does not need an event
because §4.1 ranks it continuously.

### 4.1 Exposure — risk ranking as a standing state

Deep semantic analysis costs too much to run over a repo, so it needs a triage layer, and that
layer is cheap enough to keep current continuously.

Every input is one git command and none reads a diff: divergence in both directions, fork-point
age, disjoint surface, interface weight, centrality from the cache, and **staleness of the last
check**. That last input is what makes this a monitor rather than a scan — never-analyzed
outranks already-analyzed at equal risk.

Staleness is measured against the branches, not against the clock. After each analysis
`semantic-scan` writes back the pair and the two tip SHAs it examined:

```
checked: feature/billing-v2@8e8a927 develop@e094dde
```

A timestamp records *when* a pair was examined but not *what* was examined, so a pair analyzed
yesterday whose side has since gained ten commits ranks as fresh — under-ranked, in the one
direction that loses a finding. SHAs make the test mechanical: compare the recorded pair against
`git rev-parse` on both refs, and unequal means re-analyze.

This entry is the one thing in the cache that history cannot reproduce, and it is why §2 sorts
on cost of deletion rather than on regenerability. Losing it costs a redundant analysis and
never a missed one, because absent resolves to never-checked, which ranks highest.

This is the answer for long-lived branches. A six-week feature branch against `develop` has had
sixty days for its assumptions to rot, nothing has ever looked, and no event fires until someone
tries to land it on a Friday. Exposure surfaces it before that.

An exposure score is never a finding. "This pair is exposed" and "this pair is broken" are
different claims, and conflating them turns the ranking into noise within two runs.

### 4.2 Convergence — catching up what nobody was watching

Someone clicks Merge in a browser. No hook fires, no session exists, `reconcile-notes` never
runs. Three weeks later `.branch-notes/` holds fourteen notes for branches that no longer exist,
`_archive/` is empty, and every skill that reads the archive has been answering rung 3 while
believing the repo simply never adopted the layer.

The fix is not a transport that reaches the browser. It is noticing that **the effect of a
convergent moment is a function of current state, not of having been present when it happened.**
Each of these is answerable today, next week, or next year, with the same result:

| Question | Test | Repairs |
|---|---|---|
| Notes for branches that are gone? | note exists, branch absent local **and** remote | archive them (§3.6) |
| Note behind its branch? | `captured_at` ≠ tip | flag drift, prompt re-anchor (§3.4) |
| Cache behind the tree? | `Generated at` SHA vs structural inputs | regenerate (§2.1) |
| Pairs never analyzed at their current tips? | `checked:` SHAs vs `git rev-parse` | rank them (§4.1) |
| Archive index behind the archive? | index older than newest archived note | regenerate (§8.4) |

**Any skill invoked on the integration branch evaluates this before doing its own work**, reports
what it found, and repairs only what its own gate already permits. `reconcile-notes` archives,
because §5 grants it that. Everything else reports and names the skill that would fix it —
`release-notes` finding four unarchived notes says so and points at `reconcile-notes`; it does
not archive them itself.

The rule that makes this safe is that **convergence repairs bookkeeping and never testimony.**
Archiving moves a file. Regenerating rebuilds a cache. Neither invents a claim. Drift is
*reported* rather than fixed, because fixing it means appending reasoning to somebody else's note
and no amount of catching up entitles anything to do that.

Assertions are checked **only for live branches** (§8.1). An archived note is frozen by §8.3 and
cannot be superseded, so the first legitimate rename after it lands would put it permanently in
violation — and a check that accumulates permanent failures is a check that gets ignored, taking
the live ones with it. Scope to notes belonging to branches still in flight, or to the notes a
pull request touches.

What this buys is precise and worth stating narrowly: a missed convergent moment becomes a
delay, not a loss. It does nothing for §3's three closing windows, and nothing at all for
`decision.made`, which remains the one thing in this design that a later run cannot reconstruct.

## 5. Gates

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
bisecting cannot be done any other way. `reconcile-notes` archives landed notes itself — a
`git mv` of markdown inside `.branch-notes/`, staged and not committed, with the undo printed.
It regenerates `_archive/INDEX.md` (§8.4) under the same exception and for a stronger reason:
that file is generated output, so there is nothing in it for a human to approve, and holding a
regeneration behind a proposal only guarantees the index drifts from the archive it describes.
Its exception is justified by the shape of the work rather than by convenience: archiving is the
~99% path after every landing, and a proposal nobody executes is how the folder rots. Deletion
stays behind an explicit yes, because that destroys reasoning that exists nowhere else.

## 6. Transports

Moments are declarative; how they fire is pluggable. Five transports, none required, all
optional, freely mixed. This is the "nothing has to be running" answer in full.

**Human.** Type the slash command. Always works, requires nothing, and is the floor every
other transport builds on.

**Agent rule.** A block in `CLAUDE.md` / `AGENTS.md` / `.cursorrules`. The only transport that
can fire `decision.made`, because it is the only one present at the moment a decision happens.

That block is loaded on every turn in the repo, forever, competing with the project's own
instructions. So it carries trigger conditions and nothing else; format and workflow live in
the skill, which loads when it fires and costs nothing until then.

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

**CI.** A workflow in the repository being worked on, shipped in [`ci/`](ci/). This is the only
transport that reaches the browser tab — which is where §3's four convergent moments actually
happen, and therefore the only one that addresses the fact that review and merge are attended by
nobody with a session.

It works because the falsifiability layer is mechanical by construction. Resolving an assertion's
anchor, comparing `captured_at` to a tip, and asking whether a note has dated entries are `git
grep` and `git log`. No model, so no session.

On `pull_request`, scoped to the notes that PR touches:

- a live assertion **violated** → failing check
- a live assertion **unresolvable** → comment, never a failure (I15)
- `captured_at` behind the branch tip → comment
- note missing, or a stub with no dated entries → comment

On push to the integration branch, it *reports* what §4.2's convergence pass would repair. It
does not repair it: archiving is a commit to the integration branch and nothing here has a
mandate to make one.

Two things separate this from the thing §1 rules out. It is a command that terminates, triggered
by a git event, holding no state between runs. And nothing depends on it — remove the workflow
and you lose the checks and keep every skill, which is I6.

What it costs, uniquely in this set, is portability: every other transport is plain git, and this
one is written against a specific provider's YAML. So the checking lives in a POSIX script the
workflow calls, and porting is a different six-line wrapper rather than a rewrite.

**Only `violated` fails the build.** Unresolvable is a question and drift is a reminder, and a
check that blocks on either gets disabled within a week — the same argument this section already
makes for hooks exiting 0. There is a second reason, and it is the sharper one: an assertion
enforced as strictly as `.gitattributes` has turned one branch author's sentence into repository
policy that nobody voted on. Assertions and policy are both claims the repo can be checked
against (§2), and the only thing keeping them apart is that one of them can be ignored.

**Harness.** A worktree manager that already knows about branch creation and landing can fire
the moments directly. The contract it needs is small:

```
branch.start     { branch, base_ref }
branch.ready     { branch, base_ref }
review.round     { branch, anchor_sha }
conflict.raised  { operation: merge|rebase|cherry-pick|revert|stash, paths[] }
branch.landed    { branch, merge_sha, base_ref }
```

Each payload carries only refs and SHAs. No state is passed between events; everything is
re-derived from git at handling time. An event that never fires costs correctness nothing —
the next skill invocation derives what it needs.

## 7. Skill contracts

Every skill declares what it reads and what it writes. Composability depends on it.

| Skill | Reads | Writes | Gate |
|---|---|---|---|
| `baseline-scan` | git, CI config, `.gitattributes`, `CODEOWNERS` | cache | auto |
| `capture-diff` | git, cache, own note | `.branch-notes/<branch>.md`, incl. assertions | append |
| `collision-scan` | git, worktrees incl. uncommitted, others' notes via `git show`, cache | cache (path sets) | auto |
| `semantic-scan` | git, call sites, notes and archive incl. assertions, cache | cache (exposure, checked SHAs) | auto |
| `bisect-report` | git, runs the suite | — | *runs* |
| `review-diff` | git, own note incl. assertions, cache, policy | — | auto |
| `resolve-conflicts` | git stages, both sides via the §2.3 ladder incl. assertions, policy | — | propose |
| `merge-order` | git, queued notes via `git show` incl. assertions, cache | — | auto |
| `onboard-file` | git, cache, archive | — | auto |
| `release-notes` | git, archive | — | auto |
| `reconcile-notes` | git, notes, archive frontmatter, cache anchor | archive moves, `_archive/INDEX.md`, cache invalidation | archive / confirm |

Only `capture-diff` writes testimony. Four skills write to the cache, which is not a durable
write — anything there can be deleted and recomputed.

**One writer, two readers, and the referents differ.** `capture-diff` locates a claim at decision
time. Everything downstream checks it against one of two things: another transition —
*does this composition preserve what each side claimed?*, which is `resolve-conflicts` and
`semantic-scan` — or a specification — *does this state satisfy the clause it was written for?*,
which is `review-diff`'s requirement mode. Same mechanism, different referent, and `review-diff`'s
`?` verdict is the same honesty as `unresolvable`: an assertion that could not be evaluated,
reported as such rather than resolved by guessing.

### 7.1 The two scans do not overlap

`collision-scan` and `semantic-scan` look adjacent and are disjoint by construction:

| | Population | Question |
|---|---|---|
| `collision-scan` | paths that **intersect** | will these collide when they land |
| `semantic-scan` | paths that are **disjoint** | did they break each other without colliding |

Neither reasons about the other's population. `collision-scan` seeing a signature change with a
caller in an unshared file emits a handoff line naming `semantic-scan` and stops; `semantic-scan`
never reports "same file, different regions". A large disjoint surface *raises* exposure in the
second skill and means nothing in the first, which is the clearest evidence they measure
different things.

Path intersection is computed once into the cache, so whichever runs second does not recompute it.

## 8. File formats

### 8.1 `.branch-notes/<branch>.md`

Append-only. Never rewrite an existing entry: a decision recorded on Tuesday describes what was
true on Tuesday, and editing it destroys the record of the reversal, which is often the most
valuable thing in the file.

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
  - src/client.py:_retry_with_backoff
assert:
  - id: a1
    added: 2026-08-06
    check: contains src/client.py:dispatch RateLimiter
    why: the limiter has to wrap retries, not just first attempts
---

# feature/rate-limit

## Requirement
PROJ-412 — rate limiting for outbound requests.

## What this does
Wraps `dispatch()` in a token-bucket limiter, configured by RATE_LIMIT_RPS.

## Why this shape
- 2026-08-04 · in-session — Stripe rate-limits per API key, not per IP, so the
  bucket keys on credential rather than connection. This is why it lives in the
  client rather than in middleware.
- 2026-08-06 · in-session — Tried a decorator on the retry loop first. Retries
  re-enter dispatch, so it double-counted every retried request.

## Must survive a conflict
The limiter has to wrap retries, not just first attempts. If this merges with a
refactor that relocates dispatch, the limiter moves with it.

## Open
Exhaustion behavior is unspecified and untested.
```

Dates under *Why this shape* are required. The reversal on the 6th only means something against
the attempt on the 4th, and an undated list reads as simultaneous.

Each dated entry also carries its **provenance**, and there are exactly two values.
`in-session` was appended while the reasoning was still in context. `reconstructed` was recovered
later from a §3.2 fingerprint and is an inference somebody confirmed. Those are different claims
and today nothing distinguishes them — which matters most to a reader who never opens the code,
for whom the note is not documentation but the only account of what happened. The absence check
in §3.2 (`grep -c '^- 20[0-9][0-9]-'`) matches both forms unchanged.

`captured_at` is normative — it is the anchor `review.round` compares against, and a note
without it cannot be checked for drift.

`paths` and `symbols` are the retrieval index and are normative for the same reason. They cost
nothing, since both are already computed from `git diff --name-only` and the `-U0` hunk headers,
and they must be written **at capture time**: once a branch is squash-merged and deleted, the
commits do not survive verbatim and the branch-to-files mapping is unrecoverable. Without them,
finding an archived note means grepping prose for a filename someone happened to type, and a
note saying "moved the limiter inside dispatch" is invisible to a search for `src/client.py`.

`merged` is left empty by `capture-diff` and filled by `reconcile-notes` on archive.

#### `assert` — the claim, written so a command can falsify it

*Must survive a conflict* is prose, which means nothing can check it. `assert` is its checkable
shadow. The prose stays: it is what a human reads and what an agent reasons from, and it says
*why* in a way no predicate does.

Three predicates, and deliberately no more:

| Predicate | Form | Holds when |
|---|---|---|
| `exists` | `exists <path>[:<symbol>]` | the path is tracked, and the symbol matches within it |
| `contains` | `contains <path>[:<symbol>] <needle>` | the anchor resolves **and** the needle appears in that file |
| `absent` | `absent <needle> [<pathspec>]` | the needle appears nowhere in scope |

Each is one `git grep`. A fourth predicate is how this becomes a language nobody writes, and
§3.3's one-question budget is the reason to hold that line.

**Evaluation is anchor-first, and the ordering is the whole design.** Resolve the anchor, then
evaluate the predicate:

```bash
git grep -qn '\bdispatch\b' -- src/client.py   || echo unresolvable   # anchor
git grep -qn 'RateLimiter'  -- src/client.py   || echo violated       # predicate
```

Three outcomes, never two:

- **holds** — the anchor resolved and the predicate is true
- **violated** — the anchor resolved and the predicate is false. Something that had to survive did not
- **unresolvable** — the anchor is gone: file renamed, symbol extracted, module split

Collapsing the third into the second is how an assertion layer gets switched off. Every
legitimate refactor moves an anchor, and a rename reported as a violation teaches people to
ignore violations — which costs the real ones too. **Unresolvable is a question — should this
assertion be superseded? — and never a failure.** It is the same argument §6 makes for hooks
exiting 0, applied to a different mechanism.

`absent` has no anchor and is therefore two-valued. That is a real asymmetry and not an
oversight: nothing about it can go stale, so nothing about it needs a third outcome.

The needle is **file-scoped even when the anchor names a symbol.** Extracting a symbol's body is
language-specific and brittle in shell, and this layer buys its reliability by being one grep.
So `contains src/client.py:dispatch RateLimiter` asserts that `dispatch` still exists in that
file and `RateLimiter` appears somewhere in it — not that one encloses the other. Report that
limit where the result is reported; a check overstating its precision is worse than a coarser
one that doesn't.

**Assertions supersede; they are never edited (I3).** A refactor that legitimately relocates an
anchor gets a new entry naming the old one:

```yaml
  - id: a2
    added: 2026-09-02
    supersedes: a1
    check: contains src/transport.py:send RateLimiter
    why: dispatch moved to transport.py in PROJ-511; the requirement is unchanged
```

`a1` is neither edited nor deleted. The live set is *derived* — an assertion is live iff nothing
supersedes it — which keeps the file append-only and leaves a readable history of what was once
required and when it stopped being. That is the same thing the dated entries preserve, for the
same reason.

**`capture-diff` writes the predicate; the human writes the sentence.** The human answers §3.3's
one question in prose; the skill turns it into a check using the paths and symbols it has already
computed, and puts the sentence in `why:` so the translation can be audited. Asking anyone to
hand-write `contains src/client.py:dispatch RateLimiter` violates I4 and would end adoption in a
week. The audit is §5's existing gate: sentence and predicate arrive in the PR diff side by side.

A note with no `assert` block is normal and not a defect — the branch may have had no claim worth
checking, which is the honest state for most typo fixes and dependency bumps.

### 8.2 `.git/intent/base.md`

Generated. Carries `Generated at: <sha>`. Contains no prose a human authored — if a claim in it
could not be recomputed tomorrow from the same history, it belongs in `ARCHITECTURE.md`.

### 8.3 `.branch-notes/_archive/<branch>.md`

Identical format, moved by `reconcile-notes`, with `merged` filled in. Path structure mirrored
so `feature/rate-limit` archives to `_archive/feature/rate-limit.md` rather than colliding with
`hotfix/rate-limit`. Never rewritten after archiving.

Frozen also means **never checked**. §8.1's assertions are evaluated for live branches only: an
archived note cannot be superseded, so the first legitimate rename after it lands would put it
permanently in violation, and a check that accumulates permanent failures is a check nobody reads.

### 8.4 `.branch-notes/_archive/INDEX.md`

Generated, committed, and the only file in this design written for a human to browse.

`_archive/` becomes two hundred files named after branches nobody remembers, which is a folder
nobody opens. §2.4 says archived notes are found by the paths and symbols in their frontmatter —
found by *what*, though? Grepping frontmatter is an agent's move, not a person's. Without an index
the layer's longest-lived artifact is reachable by machine and unreachable by everyone else.

```markdown
<!-- generated by reconcile-notes · 2026-09-14 · 63 notes · do not edit -->

## src/client.py
- [feature/rate-limit](feature/rate-limit.md) — token-bucket limiter on dispatch · 2026-08-06
- [refactor/payments-v2](refactor/payments-v2.md) — extracted dispatch into PaymentDispatcher · 2026-09-01

## src/config.py
- [feature/rate-limit](feature/rate-limit.md) — RATE_LIMIT_RPS · 2026-08-06
```

Keyed on `paths`, because a path is what somebody has in front of them when the question arrives.

This is the first artifact for §2's location rule, and it is worth naming as such. Every entry is
recomputed from the frontmatter of every archived note, so deleting it costs a regeneration and
nothing else — **Cache**, by §2's test. It is committed anyway, because its audience is human.
Cost decided the kind; audience decided the location.

Being a committed generated file, it needs `-merge`, or two branches archiving different notes
conflict in output neither of them wrote:

```gitattributes
.branch-notes/_archive/INDEX.md   -merge
```

`reconcile-notes` regenerates it **wholesale**, never appending. An appended index would be the
one generated file in the repo holding state that cannot be rebuilt from its inputs — precisely
the mistake §4.1's timestamps made before Phase 0 removed them.

## 9. Invariants

Testable. Each one names a way the layer could rot into something worse than nothing.

- **I1** No skill writes to a tracked source file.
- **I2** Every committed intent file arrives through a PR and is reviewed there.
- **I3** Notes are append-only and dated. Assertions supersede rather than change, and the live
  set is derived from what nothing supersedes.
- **I4** Nothing derivable from git is ever asked of a human. This is the adoption constraint,
  and it outranks completeness.
- **I5** Cache is never authoritative over code. On disagreement, the code is right and the
  cache is stale.
- **I6** Every skill degrades gracefully to diff-reading on a repo with no notes.
- **I7** Cross-branch reads go through `git show <ref>:<path>`, never `cat`, and every output
  states which rung of §2.3 answered *and why that was the highest rung available*. A bare level
  is indistinguishable from a malfunction to anyone adopting the layer mid-life.
- **I8** Policy is read from `.gitattributes` and `CODEOWNERS`, never written to them, and any
  policy that would skip verification or defer to one side is confirmed with a human before it
  is acted on.
- **I9** Every argument has a derived default, and every skill reports which default it used.
  Deriving silently is not the goal — a wrong default that goes unreported produces output that
  looks completely normal, which is strictly worse than having asked.
- **I10** No skill assumes `refs/remotes/origin/HEAD` exists. It is written by `git clone` and
  not by `git remote add` + `fetch`, so it is absent in most CI checkouts. Skills fall back
  through the conventional trunk names, report which answered, and ask when none do.
- **I11** No skill hardcodes `.git`. Paths come from `--git-dir` or `--git-common-dir`, because
  in a linked worktree `.git` is a file.
- **I12** Branch relevance is ranked by liveness, never filtered by date alone, and whatever
  falls below a cut is counted in the output rather than dropped.
- **I13** A skill that finds itself in the other scan's population (§7.1) hands off by name
  rather than answering.
- **I14** Any output resting on the cache states the `Generated at:` SHA it read. I5 says the
  code wins on disagreement, and that is a rule the reader has to be able to apply — a reader
  who never opens the code, or who cannot open `.git/intent/` because it is not on any surface
  a human browses, has no other way to know how old the claim is.
- **I15** An assertion whose anchor no longer resolves is reported `unresolvable`, never
  `violated`, and never blocks. Refactors move anchors; a layer that reports legitimate refactors
  as failures gets switched off, and takes every real violation with it.

## 10. Decisions taken, and what would reopen them

**State is sorted by cost of deletion.** Settled, after two earlier forms each failed on a
specific artifact. The producer-based taxonomy could not place an archived note; the
regenerability-based one could not place §4.1's record of what has been analyzed, which no clone
can reproduce yet costs nothing but time to lose. The trigger to add a fifth row is an artifact
whose loss costs something *other* than time, reasoning, or enforcement.

**`base.md` is uncommitted.** Settled, but on a narrower argument than the one it used to rest
on. The old trigger was authorship — "the moment anyone wants one hand-written line in it." That
test is wrong, and §4.1 is the proof: it added machine-written state that no clone can reproduce
and it passed an authorship check cleanly. The trigger is **audience**. `base.md` stays
uncommitted for as long as only agents read it; the moment a human is expected to open it, §2's
location rule says commit it with `-merge`, and the same holds for any index built for human
retrieval.

**Assertions are three-valued, file-scoped, and written by the skill.** Settled, on three
findings. Two-valued would collapse `unresolvable` into `violated`, and since every legitimate
refactor moves an anchor, the layer would report correct work as failure until someone turned it
off (I15). Symbol-scoped needles would need language-specific body extraction, which trades this
layer's one reliable property — it is a single `git grep` — for precision it can only sometimes
deliver. And hand-authored predicates would violate I4 and §3.3's one-question budget, so the
human writes the sentence and `capture-diff` writes the check, with both landing in the PR diff
where the translation can be audited.

The trigger to reopen is a claim that genuinely cannot be expressed in the three predicates and
recurs across branches. The answer then is a fourth predicate with the same one-command property,
never an expression language — the moment an assertion needs parsing rather than dispatching,
this has become a test framework competing with the repo's own.

**Convergence replaces dispatch.** Settled. §3 claimed eight events and six detectors while
nothing dispatched on any of them — hooks print to stderr and exit, and every other transport
waits for someone to type a command. The fix was not to add a dispatcher, which is the service §1
rules out, but to notice that most of these moments do not need to be caught: four are functions
of current state and can be recomputed whenever anyone next looks. The trigger to reopen is a
convergent moment whose *value* decays fast enough that recomputing it later is worthless.
`queue.forming` already sits near that line — a merge order computed after the merges is
archaeology — and if a second one joins it, convergence is buying less than this section claims.

**CI is a transport, and only `violated` blocks.** Settled. It satisfies the sharpened §1: a
command that terminates, triggered by a git event, holding no state between runs, whose absence
costs the check and never correctness. Blocking on unresolvable or on drift would get it deleted
within a week — §6's argument for hooks exiting 0, unchanged — and would also convert one branch
author's sentence into repository policy nobody voted on. The trigger to reopen is evidence that
the advisory output is ignored in practice, in which case the answer is fewer checks, not harder
ones.

**Exposure is a standing predicate, not an event.** Settled that it belongs in the model,
unsettled in where it sits. §4.1 is a numbered subsection of a section whose first line reads
"Eight events," and exposure is explicitly not one — it is a predicate over current state that
any invocation can evaluate, and it exists because the highest-risk case in §4.1's own example
is one where *no event fires until someone tries to land it on a Friday*. It stays under §3 for
now because it fires in the same places. The trigger to move it is a second predicate of the
same shape — unarchived notes for branches that are gone, anchors that have drifted — at which
point those two are a section of their own and §3 is about events again.

**`reconcile-notes` splits its gate: archive automatically, confirm before deleting.** Settled,
on the finding in §3.6 — notes are branch-local, so a note reaches the integration branch only by
landing, which makes the abandoned-work pile that the original prune step was built to sweep
nearly empty by construction. Archiving is the ~99% path and holding it behind a proposal leaves
a chore after every merge. Deleting is rare and irreversible, so it keeps its gate.

**`resolve-conflicts` is gated on unmerged paths, not on merges.** Settled. It covers five
operations because the operand inversion in rebase is where the expensive mistake lives, and it
refuses to run without conflicts because predicting them is two other skills' work.

**`branch.ready` still has no clean detector.** It depends on someone saying so, and it is the
one genuinely open item. A pull-request-open webhook would detect it precisely, and is exactly
the service §1 rules out. Left as-is: the event fires when a human runs `/capture-diff` or
`/review-diff`, which is when they were going to run it anyway.

**`decision.made` is undetectable by design, not by omission.** It leaves no git state — no
commit, no ref, nothing a terminating command could observe. It is reachable only from inside a
session that was present when the decision happened, which is why the agent-rule transport is
the one that cannot be replaced by a hook. This is the single point where the layer depends on a
convention rather than a mechanism, and it should stay stated plainly rather than papered over.