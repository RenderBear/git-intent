---
name: semantic-scan
description: Find the conflicts git never reported — one branch changes a function's contract while another adds or modifies a caller depending on the old behavior, in different files, with no conflict markers, merging green and failing later. Also ranks branch pairs by exposure as triage, orders a merge queue by what depends on what (--order), and runs the pre-land check that stops a branch from quietly undoing a standing decision a peer or a landed branch made. Use this after a merge that resolved suspiciously cleanly, before a release cut, before landing a long-running branch, when several branches are queued and you need a merge order, when tests pass but something feels off after integrating, or when the user asks what a merge might have broken silently or what to merge first.
---

# semantic-scan

Git's conflict detection is textual and local. Two branches editing the same lines conflict; two branches editing *related meaning* in different files do not. The second case is more dangerous precisely because nothing stops to tell you.

The shape is always the same: one side changes what a function guarantees, the other side adds or modifies code depending on the old guarantee, the files never touch, the merge is clean, both suites were written against their own branches and both pass.

## The disjoint-paths line, and where it stops

The *analysis* here is the inverse of `collision-scan`. Where two branches touch the same file, git will conflict or a reviewer will look, and `collision-scan` covers it. This skill's analysis exists for the case git can't see:

| | Looks at | Question |
|---|---|---|
| `collision-scan` | paths that **intersect** | will these collide when they land |
| `semantic-scan` analysis | paths that are **disjoint** | did they break each other without colliding |

That line governs the two *scans of in-flight work*. It does **not** govern the two *integration-time* modes, which sit above it and use the whole relationship, intersecting paths included — because "what must land first" and "does this landing run into a standing decision" don't care which side of the line a path is on.

Four modes, then:

- **Exposure** — rank a whole repo's branch pairs by accumulated semantic risk. Cheap, no reasoning, runs over everything.
- **Analysis** — trace contracts and dependents for one pair or one merge. Disjoint paths. Expensive, and worth spending only where exposure says to.
- **Order** (`--order`) — for a queue of branches, report what depends on what so the same conflict isn't resolved four times. Uses path intersection.
- **Pre-land** — before a branch lands, bring up every standing decision it runs into — its own, a live peer's, or one from landed work — for a call. Uses both.

## Invocation

```
/semantic-scan --exposure               # rank every live pair; no deep analysis
/semantic-scan                          # analyze the most recent merge commit
/semantic-scan 4a1f9c2                  # a specific merge
/semantic-scan branch-a branch-b        # a pair that hasn't merged yet
/semantic-scan feature/billing-v2       # that branch against its integration target
/semantic-scan --order a b hotfix/c     # order a queue by what depends on what
/semantic-scan --pre-land               # what standing decisions does landing this run into?
```

The two-branch and single-branch forms run *before* the merge, when the finding is still cheap. The default form runs after, which is when people think to ask.

`--pre-land` is what the operating protocol runs before every landing — it finds the standing decisions the merge runs into (§ *Pre-land* below) and is a `propose` gate: at automation level `assisted` every one goes to a person, at `full` the agent settles the ones it can defend and stops only where it can't tell, the two sides contradict, or verification fails.

Before a release cut, use `--exposure` rather than walking every merge in the range. Scanning thirty merges to find the two that mattered is the cost the exposure ranking exists to avoid.

## Exposure — risk at scale

Analysis costs too much to run over a repo. Exposure is the triage layer that decides where to spend it, and it is the mode that matters in a long-lived-branch workflow: gitflow's six-week `feature/billing-v2` has accumulated semantic risk against `develop` continuously, and nothing has ever looked.

Every input is one git command and none require reading a diff:

```bash
git rev-list --left-right --count "origin/$A...origin/$B"   # divergence, both directions
git log -1 --format=%ct $(git merge-base "origin/$A" "origin/$B")   # age of the fork point
git diff --name-only "$BASE..origin/$A"                     # surface
git diff -U0 "$BASE..origin/$A" | grep '^@@'                # symbols touched
```

Score each pair on:

- **Divergence** — commits on each side since the merge base. More change, more chances.
- **Age** — days since the fork point. Time is what lets contracts drift out from under callers.
- **Disjoint surface** — files each side touches that the other doesn't. This is the population at risk, and unlike `collision-scan` a *large* disjoint surface raises the score rather than lowering it.
- **Interface weight** — does either side touch exported symbols, public signatures, schemas, migrations. A branch editing only test fixtures scores near zero however old it is.
- **Centrality** — how many other files import the touched ones, from the baseline cache at `$(git rev-parse --git-common-dir)/intent/`. Quote that cache's `Generated at:` SHA in the exposure report: centrality drives the ranking, nobody can inspect a file inside `.git/`, and a score computed from a stale import graph is wrong in a way that reads as authoritative.
- **Staleness of the last check** — the tip SHAs at which this pair was last analyzed, if ever. Never-checked outranks checked-at-the-current-tips at equal risk. A pair analyzed yesterday whose side has moved since is stale, and a timestamp cannot tell you that.

Record what you examined back into the cache, keyed on the tips you saw, so a later run ranks a pair it has already checked below one it hasn't. This is triage you run when you're about to spend on analysis, or to answer "which long-lived branch is riskiest" — not a monitor kept continuously current.

```
EXPOSURE — 12 live branches, 31 pairs sharing an integration target

  87  feature/billing-v2 × develop
      184/23 commits, forked 61 days ago, 40 disjoint files
      touches Charge.validate(), 3 migrations — never analyzed
  61  feature/billing-v2 × feature/tax-rules
      both change models/charge.py's contract surface, no shared file
  44  feature/webhooks × develop
      forked 12 days ago, 9 disjoint files, one exported signature
  ...
  <8  22 pairs — short-lived, no interface surface, not listed

Analyzed the top 3. Run /semantic-scan <a> <b> for any other pair.
```

The scores are ordinal, not physical. They exist to sort, and the report should say what drove each one rather than presenting the number alone — a reader who can't see *why* billing-v2 scored 87 has no way to disagree with it.

Exposure never reports a break. It reports where a break would be expensive and unexamined. Saying "high exposure" where analysis then finds nothing is a correct outcome, not a false positive.

## Analysis

### 1. Establish the two sides

```bash
git log --merges -1 --format='%H %P'          # the merge commit and its parents
MERGE=<sha>; P1=<parent1>; P2=<parent2>
git diff --name-only $P1..$MERGE
git diff --name-only $P2..$MERGE
```

For an unmerged pair, use the merge base:

```bash
BASE=$(git merge-base branch-a branch-b)
git diff --name-only $BASE..branch-a
git diff --name-only $BASE..branch-b
```

Keep the set where those two lists **don't** intersect. Overlapping files already conflicted, or are `collision-scan`'s.

### 2. Extract contract changes from side A

A contract change is anything altering what callers can rely on, whether or not the signature moved:

- Signature: parameters added, removed, reordered, retyped; defaults changed
- Return: type, shape, nullability, or the meaning of a sentinel value
- Errors: what's raised, what's swallowed, what's now raised that wasn't
- Side effects: something that used to write, lock, retry, or cache, and now doesn't — or now does
- Invariants: ordering, idempotency, thread safety, whether a collection is sorted
- Semantics of unchanged signatures: a validator that starts rejecting empty strings, a limit that starts counting retries

The last category is where the real damage lives. A changed signature breaks the build and gets found; a function that keeps its shape and changes its meaning does not.

```bash
git diff $BASE..branch-a -- <changed files>
git diff -U0 $BASE..branch-a | grep '^@@'
git show branch-a:.branch-notes/branch-a.md 2>/dev/null
```

The note lives on the branch it describes, so read it through the ref. After landing it moves to `.branch-notes/_archive/<branch>.md` on the integration branch — check there too. Its *Must survive* line often names the contract directly, which beats inferring it from the diff.

Its `assert` entries point you straight at where the author's standing decisions live — read those and their `why:` before spending effort inferring contracts from diffs. The anchor only tells you the side changed the flagged code; whether that broke the property is still yours to reason about. But a standing decision the author wrote down is the strongest thing you have to reason from: it's the person who made the change telling you, in writing, what it must not undo — far better than guessing what a caller might depend on.

### 3. Find dependents introduced by side B

```bash
git grep -n 'dispatch(' $P2 -- '*.py'
git diff $BASE..branch-b -- $(git grep -l 'dispatch(' $P2)
```

Two categories, and the second is easy to miss:

- **New callers** — side B added code calling the changed symbol.
- **Modified callers** — side B changed existing call sites in ways that assume the old behavior. These look fine in isolation because they were fine when written.

Indirect dependents count. If side B's new code calls something that calls the changed function, the dependency is real even though it won't appear in a grep for the symbol.

### 4. Report findings with confidence

Every finding needs both sides shown, or it isn't checkable:

```
Scanned merge 4a1f9c2 — refactor/payments-v2 + feature/rate-limit
14 files from each side, no overlap. 3 contract changes examined.
Exposure at time of scan: 61.

LIKELY BROKEN
  dispatch() no longer retries internally (client.py:L61, from payments-v2)
    Retry moved up into PaymentDispatcher.send().
  feature/rate-limit added a limiter inside dispatch (client.py:L88)
    assuming retries pass through it. They no longer do.
    Effect: retries bypass the rate limiter entirely. Passes both suites —
    neither covers retry-under-limit.

WORTH CHECKING
  validate_charge() now rejects empty metadata (models.py:L204)
    csv-import constructs charges with metadata={} in two places
    (importer.py:L77, L112). May be intentional; may not.

NOT DETERMINABLE
  Config loading order changed on both sides. Whether the composed order is
  correct depends on deployment behavior that isn't in the repo.

COVERAGE
  Dynamic dispatch not analyzed: 3 call sites go through getattr() in
  handlers.py. Anything reached that way was not checked.
```

The last two sections matter as much as the first. A silent false negative is this skill's characteristic failure — the whole premise is that dangerous things leave no trace — so what *wasn't* examined has to be visible. Reflection, dynamic dispatch, string-keyed registries, serialized call graphs, and anything crossing a network boundary are outside what static reading sees, and a report omitting that implies a completeness it doesn't have.

Write the pair and the two tip SHAs you analyzed back to the cache, so the next exposure run can rank never-checked ahead of checked-at-these-tips:

```
checked: feature/billing-v2@8e8a927 develop@e094dde
```

SHAs rather than a timestamp, because the question at ranking time is whether *this* state was examined, not whether some earlier state was. Compare the recorded pair against `git rev-parse` on both refs; unequal means re-analyze.

## Pre-land — bringing up the standing decisions

Run before a branch lands. Analysis asks "did these break each other?"; this asks the sharper, cheaper question "is this landing about to run into a decision someone already made?" — a standing decision, the `assert` entry on a note (see `capture-diff`). It is the check that makes parallel work safe: two agents in two worktrees can't quietly undo each other, and a branch landing today can't quietly undo one that landed last month.

Find every standing decision whose anchor sits on a path this landing touches — from three places:

```bash
# the landing branch's own note
git show "$BRANCH:.branch-notes/$BRANCH.md" 2>/dev/null

# live peers — branches and worktrees still in flight that share a path
git worktree list --porcelain
git for-each-ref --format='%(refname:short)' refs/remotes/origin

# everything already landed on the integration branch
find .branch-notes/_archive -name '*.md' 2>/dev/null
```

Take the **live** entries from all three (one named by another's `supersedes:` was replaced, so skip it). For each, check only whether its anchor sits in code this landing changed:

```bash
git grep -qn '\bdispatch\b' -- src/client.py || echo "a1: anchor moved — re-point it"
git diff "$P1..$MERGE" -- src/client.py | grep -q . && echo "a1: landing touches the anchored code — bring it up"
```

Scope by path intersection — the cache already holds each branch's path set, so this is a set operation, not a rescan. A decision whose anchor the landing doesn't touch can't be run into by it. And the grep never decides whether the property held — it only says the landing is in the same code someone flagged.

For each decision the landing runs into, bring it up with its `why:` line, for one of three calls: it still holds, this change replaces it, or it no longer applies.

```
PRE-LAND — feature/rate-limit → develop
  own      a1  the limiter must wrap retries, not just first attempts
               landing doesn't touch dispatch — nothing to decide
  peer     b2  (refactor/payments-v2, wt-payments) anchor moved:
               dispatch → transport.py — re-point b2, not a block
  landed   c7  (feature/billing-v2, landed 3wk ago) charges must carry an
               idempotency key — this landing changes the retry path that
               builds them. Does c7 still hold?  →  a call is needed

Level: assisted — the c7 question goes to a person before landing.
```

Who makes the call is the automation level. `assisted` brings every one to a person. `full` lets the agent settle the ones it can defend — it can show the property still holds, or a test covers it — and stops for a person only where it genuinely can't tell, where the two sides contradict, or where verification fails. A landed decision only ends one way: a deliberate, dated `supersedes:` in the landing branch's note (that's `capture-diff`'s job), never this check waving it through.

## Order — a queue by dependency (`--order`)

Merging a queue in arrival order means every branch rebases onto every earlier branch's surprises; landing the structural change first means everything rebases onto it once. `--order` reports **what depends on what, and why** — a dependency is a fact about the code that survives being ignored, where a numbered sequence dies the moment an approved PR sits at the bottom of it.

It reuses the exposure substrate. Only pairs whose paths **intersect** can carry an ordering constraint, so cut to those first — a set operation over the path lists the cache already holds, not another pass over git:

```bash
comm -12 <(sort "$paths_a") <(sort "$paths_b") | head -1   # do they share a path at all?
```

Report how many pairs survived the cut ("18 of 45 pairs share a file") — it tells the reader why the answer came back mostly empty. For each surviving pair, a directed order is real in only two cases:

- B edits a symbol A relocates → **A first**, or B's edit replays onto a location that doesn't exist yet.
- B calls an interface A changes → **A first**, or B merges green against a signature about to vanish.
- Both append independently to the same file → no dependency, just a textual conflict either way.

Everything else is a preference; label it as one. A merge queue is a social fact git doesn't hold — which branches are approved, which are abandoned — so this is one of the few places in git-intent where asking "which are actually queued?" is right rather than a failure to derive. Above roughly a dozen branches the pair count grows quadratically; report it and ask which are queued rather than analyzing a fortnight of activity nobody intends to merge.

```
Queue: 5 branches into develop

DEPENDENCIES
  refactor/payments-v2 → feature/rate-limit
    v2 extracts dispatch() into PaymentDispatcher; rate-limit wraps dispatch().
    If rate-limit lands first, its limiter is relocated by hand in the second
    merge, and a version that only limits first attempts passes tests.

NO CONSTRAINT
  feature/csv-import   independent — no shared files
  chore/bump-deps      lockfile only; regenerate whichever lands second

Suggested: payments-v2 first (41 files, 3 weeks open — everything rebases across
it once), then rate-limit and timeout-handling either order. csv-import any time.
```

Recheck after each merge — every merge moves the target and stales the ordering. It's cheap; treat it as a per-merge check, not a plan for the week.

## Judgment

**Exposure sorts; analysis decides.** Never report an exposure score as a finding. "This pair is exposed" and "this pair is broken" are different claims, and conflating them turns the ranking into noise within two runs.

**Show both sides, always.** "This might be broken" without the two specific locations is unactionable, and after two of those the report stops being read.

**Rank by silence, not severity.** A break that fails loudly on the next test run costs an hour. A break that passes both suites and surfaces in production is the reason to run this.

**Deletions are the highest-yield input.** Reviewers skim deletions and git never conflicts a deletion against a distant caller. When one side removed something, check what the other side started depending on.

**Long-lived branches are the target case.** A branch alive for two months has had sixty days for its assumptions to rot. Exposure ranking exists so that branch surfaces before someone tries to land it on a Friday.

**Say when nothing was found.** "Three contract changes, no dependents introduced by the other side" is a real result. Manufacturing findings to justify the run is how the section gets skipped when it eventually matters.

**A finding is a question, not a fix.** Whether the new contract or the old caller is right is a decision about the requirement. Present it; don't resolve it.

**Pre-land looks at three sets, never one.** A pre-land run that considers only the landing branch's own standing decisions is theatre — the whole reason it exists is the peer and the landed branch it might undo. Checking your own promises and calling it safe is the failure this mode prevents.

**A dependency is a fact; an order is a preference.** `--order` reports the two cases where one branch *must* precede another and labels everything else a preference. Emitting a numbered sequence as though it were binding is how the output gets ignored the first time an approved PR is at the bottom of it.

## Next — close the loop

End the run naming the next action and any unused mode. The modes chain: exposure points at which pair to analyze; analysis and pre-land point at resolution or capture.

```
Next
  · /semantic-scan <a> <b>     analyze a specific high-exposure pair from the ranking
  · /resolve-conflicts         if landing this produces conflicts (--auto to apply, assisted to propose)
  · /capture-diff              if your change overturns a standing decision on purpose — append a dated supersedes: entry
  · --order                    if there's a queue, not just this pair
```

List only what applies: after a clean analysis, the useful next line is the pair to look at next or "nothing found"; after a decision you're overturning, it's supersede-or-stop.