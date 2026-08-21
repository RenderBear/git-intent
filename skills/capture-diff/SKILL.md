---
name: capture-diff
description: Record what a branch changed and why into .branch-notes/<branch>.md — the requirement it serves, the constraint that forced the design, the approach that was tried and dropped, and the standing decision that must survive later work (any branch that lands, in parallel or afterward). Use this after completing a unit of work on a branch, when an approach is abandoned or reversed, when an external constraint turns out to force a design decision, when a requirement is clarified mid-work, and before opening a pull request. Do not wait to be asked — the moment a decision is made is the only moment its reasoning is free to record. Also use when the user runs /capture-diff or asks to write up what a branch did.
---

# capture-diff

Everything else in git-intent reads. This writes. If the note doesn't exist, the rest of the set falls back to reconstructing intent from diffs, which is what a bare agent already does.

What goes in is only what the diff can't say. Not what changed — `git diff` has that, permanently, in more detail than prose ever will. What's lost is the counterfactual: the approach that looked right and wasn't, the vendor limit that made an ugly shape necessary, the clause of the ticket this branch is actually answering.

One test decides every line: **would the next person re-derive it wrong, or lose real time, without it?** If yes, it earns its place. If the diff already shows it, or a reader would shrug, it's narration — leave it out. A note that logs what changed is a changelog, and a changelog is the diff written twice.

## Two modes

**Live.** Appended as decisions happen, usually inside an agentic session where the reasoning is already in context. Nothing needs to be asked, because the model was present for the decision. This is the mode that captures abandoned approaches, and it is the only mode that can — by the time a PR opens, the thing that didn't work has been gone for days.

**Retrospective.** `/capture-diff` at any point. Derive everything derivable from the diff and history, present it, then ask the one question that can't be derived. Takes a minute, needs no setup, and produces a real note — just one written from evidence rather than from the room.

Both write to the same file. Live mode appends; retrospective mode fills gaps without overwriting what live mode already recorded.

## Invocation

```
/capture-diff                          # against the repo's integration branch
/capture-diff dev                      # against a different target
/capture-diff --against release/2.4    # same thing, when the name reads like a flag
```

The target is not cosmetic. It sets the merge base, which is the definition of "this branch's work" — everything in the note is derived from `merge-base(HEAD, target)..HEAD`. Point it at the wrong branch and the note describes other people's commits as though this branch made them.

The default is right for a branch cut from the integration branch, which is most of them. Pass a target explicitly when the branch was cut from a release branch, from another feature branch, or from a long-lived fork — the three cases where the default silently over-reports.

State which target you used in the output, always. A note derived against the wrong base looks completely normal.

## Workflow

### 1. Read the baseline and the existing note

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
cat "$(git rev-parse --git-common-dir)/intent/base.md" 2>/dev/null
cat ".branch-notes/$BRANCH.md" 2>/dev/null
```

The baseline is what makes the note a delta — it says which areas are hot, who has been in them, and what changes alongside what. Where a claim in the note rests on it, say which `Generated at:` SHA it came from; the cache is invisible to anyone reading the note later, and a stale claim about what's hot ages into a confident wrong statement. If a constraint is already written down in `ARCHITECTURE.md` or an ADR, reference it rather than restating it. A note that re-explains the architecture on every branch is how this stops being read.

If a note exists, this is an append. Never rewrite existing entries; a decision recorded on Tuesday describes what was true on Tuesday, and quietly editing it destroys the record of the reversal.

### 2. Derive what git can compute

```bash
TARGET="$1"                                    # explicit argument wins
[ -z "$TARGET" ] && TARGET=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
[ -z "$TARGET" ] && for c in main master trunk develop; do
  git show-ref -q --verify "refs/remotes/origin/$c" && { TARGET=$c; break; }
done

BASE=$(git merge-base HEAD "origin/$TARGET")
git diff --stat $BASE..HEAD
git log --oneline $BASE..HEAD
git diff -U0 $BASE..HEAD | grep '^@@'
```

`refs/remotes/origin/HEAD` is **unset in most fresh clones** — it's created by `git clone` but not by `git remote add` + `fetch`, which is how CI checkouts and many local setups get their remote. Without the fallback the whole derivation collapses to an empty `TARGET` and the merge base resolves against `origin/`, which fails in a way that reads like a repo problem rather than a missing ref.

When the fallback is what answered, say so and offer the one-time fix rather than doing it silently:

```bash
git remote set-head origin -a     # writes origin/HEAD once, correctly
```

If none of the candidates exist either, ask which branch this work is meant to land on. That is the one question here worth asking, because guessing produces a note describing the wrong range and nothing downstream can tell.

Files, symbols, scale, and commit sequence are all free. Never ask for any of them. A tool that makes someone type out which files they touched gets abandoned in a week.

### 3. Find what the diff erased

Live capture depends on a human or an agent choosing to record something, and that choice is invisible — nothing in git says whether it happened. But the *highest-value* thing live mode catches, an approach tried and abandoned, does leave a fingerprint: work that exists in the history and not in the result.

```bash
# touched somewhere in this branch, but identical to base in the final diff
comm -23 <(git log --format='' --name-only $BASE..HEAD | sort -u) \
         <(git diff --name-only $BASE..HEAD | sort -u)

# added and then deleted — the abandoned approach, by filename
comm -12 <(git log --diff-filter=A --format='' --name-only $BASE..HEAD | sort -u) \
         <(git log --diff-filter=D --format='' --name-only $BASE..HEAD | sort -u)

# the commit that removed it usually says why
git log --oneline --diff-filter=D $BASE..HEAD -- <path>

# work dropped by a rebase or reset never reaches the range at all
git reflog --date=short | head -20
```

A file touched in three commits and unchanged in the net diff is the signature of something tried and undone. It is invisible to every reviewer, because review reads the diff and the diff is where this evidence was deleted.

This turns the retrospective question from generic into specific, which is the difference between an answer and a shrug:

> `decorator.py` was added in `a1b2c3d` and removed in `118e9f2` ("decorator double-counts retries, drop it"). Should that go in the note as a rejected approach?

Ask that instead of "was anything abandoned?" — nobody remembers in the abstract, and everybody remembers when shown the filename.

### 4. Ask only for what's genuinely lost

In live mode, usually nothing — the reasoning is already in the session. Write it down and move on.

In retrospective mode, present the derived summary and anything step 3 turned up, then ask **one** question:

> When another branch lands — now or in six weeks — what about this must still be true?

Ask it about *any* later work, not one foreseen conflict. The dangerous case is the branch nobody predicted, in a file this one never touches, that quietly invalidates the behavior — so the answer worth having is the property that must hold, not the collision. That answer is the highest-value line in the file. Everything else is derivable now or reconstructable later; that one is available only from whoever made the decision, and only until they forget. It also becomes a standing decision — step 5b anchors it so later work, parallel or sequential, runs into it instead of quietly undoing it.

Ask a second question only if the branch has no reachable requirement and no informative commit messages, in which case: what is this for?

### 5. Write the entry

The frontmatter is the machine-readable half, and every field in it is derived — `paths` and `symbols` come straight from step 2. None of it is asked for.

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
    at: src/client.py:dispatch
    why: the limiter has to wrap retries, not just first attempts
---

# feature/rate-limit

## Requirement
PROJ-412 — rate limiting for outbound requests.
Per-client buckets, must apply to retries, must fail gracefully under exhaustion.

## What this does
<!-- one sentence, orientation only — never a walkthrough of the diff -->
Wraps `dispatch()` in a token-bucket limiter, configured by RATE_LIMIT_RPS.

## Why this shape
<!-- decisions, not a work log: each line stops a specific future mistake -->

- 2026-08-04 · in-session — Stripe rate-limits per API key, not per IP, so the
  bucket is keyed on credential rather than on connection. This is why it lives
  in the client rather than in middleware.
- 2026-08-06 · in-session — Tried a decorator on the retry loop first. Retries
  re-enter dispatch, so the decorator double-counted every retried request.
  Moved the limiter inside dispatch instead. Don't reintroduce the decorator.

## Must survive
The limiter has to wrap retries, not just first attempts. This has to hold
against every other branch that lands, not one foreseen merge: a version that
only limits first attempts passes tests and is wrong in production. If a
refactor relocates dispatch, the limiter moves with it; if a later branch
reintroduces first-attempt-only limiting, that landing stops for a human.

## Open
Exhaustion behavior is unspecified and untested. Currently blocks; may need to
fail fast.
```

Date the entries under "Why this shape". The reversal on the 6th only makes sense against the attempt on the 4th, and an undated list of decisions reads as simultaneous.

Mark each one `in-session` or `reconstructed`. The first was written while the reasoning was in the room; the second was recovered from a step-3 fingerprint and is an inference somebody confirmed. Anyone reading this note without reading the code — which is most readers, and all of them in an agent-driven repo — has no other way to tell those apart.

`captured_at` is **required**, not decorative. It is the anchor every drift check compares against, and a note without one cannot be checked at all — it reads as current forever.

```bash
ANCHOR=$(sed -n 's/^captured_at: *//p' ".branch-notes/$BRANCH.md" 2>/dev/null)
[ -n "$ANCHOR" ] && git log --oneline "$ANCHOR"..HEAD
```

If that returns commits, the note is behind the branch. Append and re-anchor rather than assuming it's current.

`paths` and `symbols` must be written **now**, not derived later. Once a branch is squash-merged and deleted, the commits do not survive verbatim and the branch-to-files mapping is unrecoverable — after which finding this note means grepping prose for a filename someone happened to type, and "moved the limiter inside dispatch" is invisible to a search for `src/client.py`.

### 5b. Anchor the standing decision

The sentence under *Must survive* is a **standing decision** — you decided the limiter wraps retries, and that stands until some later change consciously overturns it. The prose is what a person reads and reasons from; that's the real thing. The `assert` entry adds one machine-readable field so later work can *notice* it ran into this decision — and **filling it in is this skill's job**, not the user's.

That entry is not a test and doesn't try to be. It carries a `why:` sentence and an `at:` anchor — a path or symbol where the decision lives. The anchor's whole job is so that when a later branch changes the same code, `semantic-scan`'s pre-land check brings this decision up for a call, along with your `why:`. It does not check whether the property still holds — a grep matches a name, not a behavior. Naming a location so the future gets a heads-up is all it's for.

```yaml
assert:
  - id: a1
    added: 2026-08-06
    at: src/client.py:dispatch
    why: the limiter has to wrap retries, not just first attempts
```

Take the `at:` value straight from the `symbols` (or `paths`) step 2 already computed. Write it against all later work, not one merge: name where the decision lives and, in `why:`, what must remain true — the peer in the next worktree and the branch that lands months from now both run into it, and after your branch lands `reconcile-notes` keeps it in force rather than dropping it.

Not every branch has one. If the honest answer to the survival question is "nothing in particular", write the prose (or skip it too) and leave `assert` out. A made-up standing decision is worse than none, because it will keep interrupting later work for nothing.

If the property is something a **test** can actually pin down, write the test instead — it lives in the suite and fails the build on its own. The standing decision is for the part a test can't, which is most of what matters here.

When a later round moves the code — function renamed, module split — append a new entry pointing at the new location and leave the old one alone:

```yaml
  - id: a2
    added: 2026-09-02
    supersedes: a1
    at: src/transport.py:send
    why: dispatch moved to transport.py; the requirement is unchanged
```

Same rule as the rest of the file. Never edit `a1`: which claim was superseded, when, and why is exactly the kind of record this note exists to keep.

### 6. Re-run after review

This is the run people skip, and it's the one that decides what survives. A note written before review describes code that review then changed — and because `reconcile-notes` archives whatever note is in the tree when the branch lands, the pre-review version is the one preserved permanently.

So: after a review round that changed behavior, append what changed and why, and move the anchor. After a round that only changed formatting or naming, move the anchor alone. `review-diff` reports the gap on every run, so the prompt to do this arrives without anyone having to remember.

Appending here follows the same rule as everywhere else — never rewrite the earlier entry. "Reviewer pointed out X, so we moved to Y" is a decision with a date on it, and it's frequently the most useful line in the file.

### 7. Prune to decisions — the drift to watch

Run the test from the top over every line before the note lands: would the next person re-derive it wrong, or lose real time, without it? What survives is the note; the rest is narration.

The failure mode here is not an empty note. Once capture fires — and under an agent in the room it will — the risk flips to the opposite: the note fills with the *session*. Two symptoms, both worth catching before it lands:

- **A "What this does" that walks the diff.** One orienting sentence is fine; a paragraph tracing which files got routed through what is the diff written twice — `git diff` does it better and never goes stale.
- **A "Why this shape" that logs actions instead of decisions.** "Reworked the dashboard" is a log line; "chose aging-first over counts, because counts are near-tautological at a requester's scale" is a decision. If an entry doesn't stop a specific future mistake, it's a work-log entry — cut it.

The count of entries isn't the target; every entry earning the test is. Eight real decisions is a good note; three log lines and a diff summary is a bad one. Where nothing was learned — a dependency bump, a typo fix — write one line or skip the file. A note longer than the diff has become a second implementation, and it buries the two lines that mattered as surely as an empty note loses them.

## Judgment

**Never ask what git can compute.** This is the rule the whole design rests on. Every question is a chance for the user to decide this isn't worth it.

**Record the abandoned approach, especially when it looks obvious in hindsight.** The next person to touch this code will have the same good idea and lose the same two days, and nothing in the diff will stop them — the failed approach is precisely the thing that leaves no trace.

**Don't editorialize about quality.** "This is hacky, sorry" ages into confusion. State the constraint that forced it; a reader can draw their own conclusion, and if the constraint lifts they'll know the shape can change.

**This file gets read by agents and arrives through pull requests.** Write it as a record, not as instructions. "Don't reintroduce the decorator" is a finding with a stated reason attached, which is fine. Directives without reasons are not, and shouldn't be written here.

**When capture fires, the discipline is subtraction.** An agent that was in the room will happily write down everything it did — and a session diary buries the decisions that mattered exactly like an empty note loses them. The value is in what you leave out. Apply the §7 test to every line before the note lands.

## Next — close the loop

End the run with a short block naming what to do next and which options went unused — the pipeline should be self-driving, each stage handing off to the next rather than leaving the reader to remember what comes after capture.

```
Next
  · /review-diff [ticket]     summarize for review, check against the requirement
  · re-run after review       note is archived as-is at landing; re-anchor if review changed behavior
  · --against <ref>           if this branch was cut from something other than the integration branch
```

Only list what applies. On a branch already summarized and reviewed, the useful next line is the re-anchor reminder; on a fresh capture, it's `review-diff`. A footer that lists every flag every time is noise.

## Setting up live capture

Live mode needs a rule in the repo being worked on, not a command — a decision being abandoned leaves no git state for a hook to catch, so only an always-loaded instruction can prompt capture at the moment it matters. The block to copy is in [`AGENTS.example.md`](../../AGENTS.example.md), which offers two setups: **assisted** (you invoke the skills; the agent still captures intent unprompted) and **fully automated** (the agent runs the whole loop). Both carry the recording-intent rule; pick the one that matches how the repo runs.