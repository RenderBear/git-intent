---
name: bisect-report
description: Find the commit that introduced a regression and explain the mechanism — not just the hash, but what the change did and why it produced this failure. Use this when something worked before and doesn't now, when the user asks when a bug was introduced, asks to bisect, or has a failing test that used to pass. Requires a reproducible check and runs commands against the working tree.
---

# bisect-report

`git bisect` finds a hash. A hash is the start of the investigation, not the end — the commit is often large, often a merge, and often looks unrelated to the symptom.

The output worth producing is the mechanism: which change, in which hunk, caused this failure by what path. That's what makes the fix obvious and prevents a revert that takes three working things with it.

**This skill executes.** It checks out commits, runs a reproduction, and moves HEAD around — the only skill in git-intent that does, because bisecting cannot be done any other way. Confirm the working tree is clean and the user expects it before starting.

## Invocation

```
/bisect-report "pytest tests/test_client.py::test_retry_limit -x -q"
/bisect-report --good v2.3.0 --bad HEAD "<check command>"
/bisect-report --good v2.3.0 --bad HEAD --runs 5 "<check command>"   # flaky
```

**The check command is required and cannot be derived.** Everything else here has a default; this doesn't, because only the person seeing the bug knows what reproduces it. If it isn't supplied, ask for it before doing anything else — a bisect against a guessed test is an hour spent confidently blaming a random commit.

Defaults for the bounds: `--bad` is `HEAD`, `--good` is the most recent tag reachable from it, or roughly 50 commits back if the repo has no tags. Both are *proposals*, not assumptions — step 2 verifies them by running the check at each end, and an unverified `--good` is the single largest source of wrong bisect results.

`--runs N` treats any failure across N runs as bad. Reach for it the moment the reproduction is intermittent, and tell the user the run takes N times longer before starting rather than after.

## Workflow

### 1. Get a reliable reproduction first

Everything downstream depends on this. A flaky check produces a confident wrong answer, which is worse than no answer because nobody re-runs it.

The check must exit non-zero on failure, zero on success, and do the same thing twice:

```bash
pytest tests/test_client.py::test_retry_limit -x -q
```

Run it three times on the known-bad commit. If it isn't consistent, stop and say so — bisecting a flake wastes an hour and blames a random commit. Intermittent failures need a different approach: run the check N times per step and treat any failure as bad, and tell the user the run will take proportionally longer.

Note the setup a working reproduction needs — dependency install, migrations, fixtures, service start. Every bisect step will need it, and a step that fails to build must be distinguished from a step that fails the test, or it gets scored as bad and the search goes into the wrong half.

### 2. Establish the bounds

```bash
git status                                   # must be clean
git log --oneline -20
git checkout <suspected-good>; <run check>   # confirm it passes
git checkout <suspected-bad>;  <run check>   # confirm it fails
```

Verify both ends before starting. A "good" commit that was actually already broken sends the entire bisect into the wrong half, and the result will look plausible.

If the bug predates the known-good commit, widen and re-verify rather than accepting the first boundary offered.

### 3. Run it

Where the check is a single command with no setup, pass it directly — no script needed:

```bash
git bisect start <bad> <good>
git bisect run pytest tests/test_client.py::test_retry_limit -x -q
```

A wrapper is needed only when there's per-step setup, or when exit codes need handling. `git bisect run` interprets them strictly:

| exit | meaning |
|---|---|
| 0 | good |
| 1–124, 126, 127 | bad |
| 125 | cannot be tested — skip |
| 128–255 | **abort the bisect** |

That last row is why wrappers exist. A segfault exits 139 and kills the run instead of scoring the commit; an unbuildable middle commit exits non-zero and gets recorded as bad, sending the search into the wrong half.

**Write the wrapper outside the repository.** A script committed into the tree being bisected is checked out at every step — replaced by that commit's version, or absent entirely at commits predating it. Generate it per investigation to a temp path and pass it absolutely:

```bash
cat > /tmp/bisect-$$.sh <<'EOF'
#!/usr/bin/env bash
# setup — must succeed, or the commit is untestable rather than bad
pip install -qe . || exit 125
alembic upgrade head || exit 125

pytest tests/test_client.py::test_retry_limit -x -q
code=$?
[ $code -ge 128 ] && exit 1     # crash counts as bad, never as abort
exit $code
EOF
chmod +x /tmp/bisect-$$.sh

git bisect start <bad> <good>
git bisect run /tmp/bisect-$$.sh
```

For an intermittent failure, loop the check inside the wrapper and treat any failure across N runs as bad. Tell the user the run takes N times longer before starting.

Always finish with:

```bash
git bisect reset
```

Including on failure. Leaving someone's repo in a detached bisect state is a rude way to end.

### 4. Explain the mechanism

The hash alone isn't the deliverable. Read the commit and find the path from change to symptom:

```bash
git show <sha>
git show <sha> --stat
cat .branch-notes/_archive/<branch>.md 2>/dev/null    # if it came from a branch
```

If the culprit is a merge commit, the actual change is inside one of its parents — bisect the parent range rather than reporting the merge, which tells the reader nothing.

The branch note, if one exists, often states what the change was trying to do. A regression is usually a correct change with an unconsidered interaction, and knowing the original intent is what separates "revert it" from "this fix has to preserve X".

```
Regression: retries bypass the rate limiter
First bad commit: c81f0a2 — "extract dispatch into PaymentDispatcher"
Author: sam, 2026-07-29. Merged from refactor/payments-v2.

MECHANISM
  The limiter was inside dispatch() and counted every attempt, including
  retries, because retries re-entered dispatch (client.py:L88, before).
  This commit moved retry handling up into PaymentDispatcher.send(), so
  retries no longer pass through dispatch — and no longer through the
  limiter. Neither branch's tests cover retry-under-limit, so both suites
  passed.

  The branch note for refactor/payments-v2 doesn't mention the limiter;
  the extraction appears to have been done without awareness of it.

BOUNDS
  Good: a3f21c8 (2026-07-24), verified 3 runs
  Bad:  c81f0a2 (2026-07-29), verified 3 runs
  9 commits bisected, 1 skipped (b40e11f — build failure, unrelated)

FIX SHAPE
  Reverting restores limiting but loses the extraction, which several
  branches now depend on. Moving the limiter into PaymentDispatcher.send()
  preserves both. Either way, add a test for retry-under-limit — its
  absence is why this shipped.
```

The bounds section is there so the result can be doubted. A bisect that skipped four commits is a weaker claim than one that skipped none, and the reader should be able to see which they're getting.

## Judgment

**Verify both ends, every time.** More wrong bisect results come from an unverified "good" commit than from anything else.

**Never put the check script in the repo being bisected.** It gets checked out along with everything else. Generate it to a temp path, reference it absolutely, and delete it after.

**A merge commit is never the answer.** Report the change inside it.

**Say when the answer is soft.** Many skips, an intermittent reproduction, or a culprit whose diff doesn't obviously explain the symptom — all reasons to present the result as a lead rather than a conclusion.

**The missing test is part of the finding.** A regression that both test suites passed indicates a coverage gap, and naming it is the only thing here that prevents the same class of bug again.