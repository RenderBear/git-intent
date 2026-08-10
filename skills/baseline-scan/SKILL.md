---
name: baseline-scan
description: Compute what a repository is from git alone — structure, which areas are hot and which are dormant, who knows what, which files change together, and where the merge and ownership policy lives — into a regenerable cache other skills read. Use this when setting up git-intent in a repo, when joining an unfamiliar codebase, when another skill reports the baseline is stale or missing, or when the user asks for an overview of a repo, what's actively changing, or who to ask about an area. Derives everything and asks nothing.
---

# baseline-scan

Every other skill needs the same background: what this repo is, which parts are moving, who
to ask. Deriving it per invocation is wasteful; writing it down by hand produces the stale
architecture doc — authoritative-looking, quietly wrong, and inherited as truth by everything
computed against it.

So this computes it, and computes only what can be recomputed. Nothing here is authored. If a
claim could not be regenerated tomorrow from the same history, it does not belong in this file
— it belongs in `README.md`, `ARCHITECTURE.md`, or `docs/adr/`, which are reviewed, versioned,
and already have owners.

That single constraint is what makes the staleness problem disappear. A hand-written baseline
needs a human to re-verify it. A derived one needs `git log`.

## Invocation

```
/baseline-scan                  # regenerate if stale, otherwise reuse the cache
/baseline-scan --refresh        # regenerate unconditionally
/baseline-scan --print          # show what's cached, compute nothing
/baseline-scan --window 6m      # change the activity window (default: 3m hot, 12m dormant)
```

The window is the only argument that changes the answer rather than the effort. Three months
is right for a repo with steady traffic; on a quiet repo it reports everything as dormant, and
on a very busy one it reports everything as hot. If the hot list comes back empty or contains
every directory, widen or narrow it and say that you did — a window that produced no signal is
a fact about the window, not about the repo.

## The cache is not committed

```bash
INTENT="$(git rev-parse --git-common-dir)/intent"
mkdir -p "$INTENT"
```

`--git-common-dir`, not `--git-dir`. In a linked worktree the two differ, and the common dir is
shared across every worktree of the repo — so a tool that spins up five worktrees for five
parallel branches computes this once rather than five times. The cache follows the repository,
not the checkout.

Uncommitted, because a reproducible artifact in a diff buys nothing and costs three things:
churn on every landing, an authority the file has not earned, and a reviewer's attention spent
on generated content. A fresh clone has no baseline until someone runs this, which takes a few
seconds and no questions.

## Workflow

### 1. Decide whether to regenerate

```bash
BASE="$INTENT/base.md"
ANCHOR=$(sed -n 's/^Generated at: \([0-9a-f]*\).*/\1/p' "$BASE" 2>/dev/null)
[ -n "$ANCHOR" ] && git diff --name-only "$ANCHOR"..HEAD \
  | grep -E '^[^/]+/$|package\.json|pyproject\.toml|go\.mod|Cargo\.toml|\.github/|Makefile|\.gitattributes|CODEOWNERS'
```

Non-empty means a structural input moved. Regenerate. When the answer is unclear, regenerate
anyway — this is cheap, and reasoning about whether a cache is stale costs more than rebuilding
it. There is no partial refresh and no drift report, because there is nothing here a human
authored that a regeneration could destroy.

### 2. Structure

```bash
git ls-files | awk -F/ 'NF>1 {print $1"/"$2}' | sort | uniq -c | sort -rn | head -30
```

`git ls-files` rather than `find` — it respects `.gitignore`, so `node_modules` and build output
never appear. Directory purpose comes from the names and the files inside them; where it isn't
obvious, say what the directory contains rather than inventing a responsibility for it.

### 3. Hot and dormant

This is the section that justifies the file. A module rewritten three times this quarter and
one untouched for two years demand opposite caution, and nothing in a directory listing says
which is which.

```bash
# hot — churn by area over the recent window
git log --format='' --name-only --since='3 months ago' \
  | awk -F/ 'NF>1 {print $1"/"$2}' | sort | uniq -c | sort -rn | head -15

# dormant — tracked areas absent from a year of history
comm -23 \
  <(git ls-files | awk -F/ 'NF>1 {print $1"/"$2}' | sort -u) \
  <(git log --format='' --name-only --since='12 months ago' | awk -F/ 'NF>1 {print $1"/"$2}' | sort -u)
```

The `comm` is a set difference, which is why it stays cheap on a large repo — no per-file
`git log`, which is the obvious implementation and is unusably slow past a few thousand files.

Dormant is not the same as dead. Flag whether dormant code is still reachable from an entry
point when that's cheap to check; a dormant module still in the request path is the interesting
case, and reporting it as merely "inactive" understates it.

### 4. Ownership

```bash
git log --format='%an' --since='12 months ago' -- <area> | sort | uniq -c | sort -rn | head -3
```

Report the top authors per area and, where one person holds most of it, say so plainly — a bus
factor of one is a fact about risk, not an accusation.

Two honesty constraints. Commit counts proxy for knowledge, not for availability or current
ownership; if the dominant author's last commit was eighteen months ago, that belongs in the
output. And `CODEOWNERS`, where it exists, states who owns an area *by agreement*, which
outranks what the log implies. Report both when they disagree — the disagreement is the finding.

### 5. Coupling

Files that change together are coupled whether or not anything in the code says so, and that
prediction is what makes a reviewer look at the second file.

```bash
git log --format='@%H' --name-only --since='6 months ago' | awk '
  function flush(   i, j) {
    if (n > 1 && n <= 20)
      for (i = 0; i < n; i++) for (j = i+1; j < n; j++)
        print (f[i] < f[j] ? f[i]" "f[j] : f[j]" "f[i])
    n = 0
  }
  /^@/ { flush(); next }
  NF   { f[n++] = $0 }
  END  { flush() }
' | sort | uniq -c | sort -rn | head -15
```

The `END { flush() }` is not optional. Without it the last commit's files are still sitting in
the buffer when input ends and are never emitted — which silently drops the most recent commit,
the one most likely to matter. The bug is invisible on a large repo and obvious on a small one.

The `n <= 20` guard is load-bearing twice over. It keeps the pair expansion from exploding on a
commit that touched four hundred files, and it discards exactly the commits whose co-occurrence
means nothing — a formatting sweep couples every file to every other and would otherwise
dominate the ranking.

Drop the obvious pairs. `client.py ↔ test_client.py` is not a finding.

### 6. Read the policy, never write it

```bash
cat .gitattributes 2>/dev/null | grep -E 'merge|diff|binary'
cat CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS 2>/dev/null
```

Merge policy is `.gitattributes`. Sign-off policy is `CODEOWNERS`. Both are git-native, both are
honored by tooling rather than by an agent's goodwill, and both already get reviewed as
infrastructure. Record what they say and where they are. Never restate a rule in your own words
here, and never write to either file — that is a human's deliberate act, in its own commit.

If neither exists and the repo clearly needs one — a vendored directory being hand-merged, a
migrations folder with no owner — say so as a suggestion in the output, not as a rule in the file.

### 7. Commands, verbatim

```bash
ls .github/workflows/ Makefile justfile Taskfile.yml 2>/dev/null
```

Pull test, lint, and build commands out of CI config exactly as written, and record which file
they came from. A guessed test command that doesn't work is worse than no test command, because
the next skill will try it, get an error, and report the merge unverified for the wrong reason.

### 8. Point at the prose, don't absorb it

```bash
ls README.md ARCHITECTURE.md CONTRIBUTING.md CHANGELOG.md docs/adr docs/decisions 2>/dev/null
```

Record that they exist and what they cover. Do not summarize them. Two documents describing the
same system disagree within a month, and the generated one will be the one that's wrong while
looking freshest.

### 9. Write it

```markdown
# Baseline — payments-service
Generated at: a3f21c8 · 2026-08-10
<!-- Derived from git. Regenerate with /baseline-scan. Do not edit; edits are lost. -->

## Reasoning lives here, not in this file
ARCHITECTURE.md · docs/adr/ (14 records) · CHANGELOG.md

## Structure
  src/api/          HTTP handlers, request validation      hot      sam 61%
  src/payments/     provider adapters, dispatch            hot      sam 74%  ← bus factor 1
  src/models/       SQLAlchemy models and migrations       steady   dana 40%
  src/vendor/       generated client code                  —        see policy
  src/legacy/       —                                      dormant 2y, still imported by src/api/

## Changes together
  src/payments/client.py ↔ src/api/handlers.py        19 commits
  src/models/charge.py   ↔ db/migrations/             14 commits

## Policy
  .gitattributes    src/vendor/** -merge · *.lock -merge · db/migrations/* merge=ours
  CODEOWNERS        db/migrations/ → @data-eng · src/api/ → @platform

## Commands
  Tests   pytest -q             .github/workflows/ci.yml
  Lint    ruff check .          .github/workflows/ci.yml
  Build   make dist             Makefile

## Suggested
  src/vendor/ is hand-edited in 4 of the last 20 commits touching it, and has
  no .gitattributes entry. A `-merge` attribute would stop that at merge time.
```

Every line carries its provenance — an area, a number, a source file. A reader can check any
of it against the repo in one command, which is the property that keeps a generated file
trustworthy.

Omit empty sections. If the output runs past a page, it has started describing the code rather
than the repo.

## Judgment

**Ask nothing.** There is no interview. The moment this needs a human to answer a question, it
has become the document it was built to replace — and the questions land before anyone has seen
value from the system, which is where adoption dies.

**Never authoritative over code.** On disagreement the code is right and this file is stale.
Downstream skills treat it as a hint that saves work, never as a fact that overrides what they
read in the diff.

**No prose about why.** A constraint, a deliberate oddity, an in-flight migration — all real,
all valuable, none of them derivable, none of them belong here. They go to `ARCHITECTURE.md` or
an ADR, where a human maintains them and reviewers see them change.

**Suggestions are not rules.** The `Suggested` section proposes things a human might do to
`.gitattributes` or `CODEOWNERS`. Nothing acts on it. A generated file that could quietly create
merge policy would be the single most dangerous thing in this repo.

**In-flight migrations show up as coupling and churn, not as a section.** Two patterns coexisting
appear as one area growing while another goes dormant. That's a real signal and it's derived;
naming which one is "correct" is not, and is exactly what an ADR is for.
