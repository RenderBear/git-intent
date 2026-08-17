# git-intent

Git workflow skills for agents — context-aware actions across the integration lifecycle, not just reading history.

## Project

This repo is a collection of agent skills, not an application. Each skill lives under `skills/<name>/` as a `SKILL.md` file with optional `references/` support material.

[`SPEC.md`](SPEC.md) is the design of record: the state model, when each skill runs, the three gate classes, the transports, and the invariants. Read it before changing how skills interact — the individual `SKILL.md` files implement it and shouldn't contradict it.

The split is deliberate. `README.md` is for someone deciding whether to install this and how to use it — payoff, install, skills, arguments, paths. `SPEC.md` is for someone changing how it works — the state taxonomy, the gates, the invariants, the decisions and what would reopen them. Design reasoning that drifts into the README pushes the payoff below the fold; practical usage that drifts into the SPEC makes it a second README. Keep them apart.

Seven core skills — one before a branch exists, six across a branch's life — plus infrastructure and two optional utilities.

| Skill | Purpose |
|---|---|
| `scope-work` | Arriving: scope an incoming request into independently-buildable units, decide what forks in parallel vs sequences, freeze the contract at each cut. Moment 0, before any branch |
| `collision-scan` | Starting: find in-flight branches and worktrees (incl. uncommitted) working in the same code |
| `capture-diff` | Working: author-side capture into `.branch-notes/<branch>.md` — what changed, why, and the invariant that must survive later work |
| `review-diff` | Ready: PR/branch summaries for reviewers — risk-ordered or against a ticket; reports note drift and evaluates invariants |
| `semantic-scan` | Landing: clean merges that broke behavior; `--order` for a queue; the `--pre-land` invariant gate |
| `resolve-conflicts` | Conflict: merge/rebase/cherry-pick/revert — reconstruct intent, compose, verify. Proposes; `--auto` applies |
| `reconcile-notes` | Landed: archive landed notes (invariants stay live), invalidate the baseline, report what the merge made false; `--notes` for the changelog |
| `baseline-scan` | *Infrastructure* — compute what the repo is into `.git/intent/base.md`; the shared cache the loop reads |

`semantic-scan` absorbed the former `merge-order` (`--order`) and the pre-land invariant gate; `reconcile-notes` absorbed the former `release-notes` (`--notes`). Both folds are because the absorbed skill ran at the same moment on the same substrate as its host — see [`SPEC.md`](SPEC.md) §6.

## Layout

```
skills/<name>/
├── SKILL.md              # required
└── references/           # optional — git commands, scripts, templates

hooks/                    # optional transport: post-checkout, post-merge
ci/                       # optional transport: check-notes.sh + a workflow example
SPEC.md                   # state model, when skills run, gates, transports, invariants
AGENTS.example.md         # the block users copy into their own repo
```

## Conventions

- Skill names: lowercase, hyphens, max 64 chars. **Two words, not one** — every skill in the set is a compound (`capture-diff`, `collision-scan`, `reconcile-notes`). Single generic words like `baseline` or `reconcile` collide in the flat skill namespace, and worse, they collide on *description matching*: "reconcile" is the standard word for Kubernetes controllers, accounting, and data pipelines, so a bare name pulls this skill into conversations that have nothing to do with git.
- Every `SKILL.md` needs YAML frontmatter with `name` and `description`, and an `## Invocation` block listing its arguments and their defaults.
- Descriptions are third person, specific, and include trigger terms (when to use the skill).
- Keep skills concise. The agent already knows git; add only what it wouldn't infer.
- Optional reference files belong in `references/`, not inline in `SKILL.md`.

## State model

Four kinds, sorted by **what deleting them costs**. Getting this wrong is the most common way a change here goes bad. [`SPEC.md`](SPEC.md) §2 is the full version; this is the working summary.

| Kind | Location | Deleting it costs | Rule |
|---|---|---|---|
| Cache | `.git/intent/` (uncommitted) | time | Freely rewritten. Never authoritative over code |
| Testimony | `.branch-notes/<branch>.md` (committed) | the reasoning, permanently | Append-only, dated, branch-local |
| Record | `.branch-notes/_archive/` (committed) | the same, plus everyone downstream | Frozen on archive, never rewritten |
| Policy | `.gitattributes`, `CODEOWNERS` | git stops enforcing | Skills read it, never write it |

Two earlier versions of this table sorted by *who could produce* each item and then by *regenerability*. Both are wrong and both are still quotable from old commits — an archived note defeats the first, and the exposure layer's record of what it has already analyzed defeats the second. Cost of deletion is also two rules, not one: **cost decides the kind, audience decides the location.** Cache a human is meant to read gets committed with `-merge`, because nobody browses `.git/`.

Reasoning about *why* — constraints, deliberate oddities, decisions — belongs in `README.md`, `ARCHITECTURE.md`, or `docs/adr/`. Skills point at those and never restate them.

## Git idioms these skills must use

Most of these were bugs before they were conventions.

- **`git rev-parse --git-common-dir`**, never a literal `.git`. In a linked worktree `.git` is a file, and `--git-dir` is per-worktree while `--git-common-dir` is shared. The cache belongs to the repository, not the checkout.
- **`git show <ref>:<path>`** to read another branch's note. `.branch-notes/<branch>.md` exists only on that branch — a `cat` returns nothing, silently, and the skill proceeds on inference while believing it read testimony.
- **Never trust `refs/remotes/origin/HEAD` to exist.** `git clone` writes it; `git remote add` + `fetch` does not, which covers most CI checkouts. Fall back through `main`, `master`, `trunk`, `develop`; report which answered; offer `git remote set-head origin -a`; ask if none exist:

  ```bash
  TARGET="$1"
  [ -z "$TARGET" ] && TARGET=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
  [ -z "$TARGET" ] && for c in main master trunk develop; do
    git show-ref -q --verify "refs/remotes/origin/$c" && { TARGET=$c; break; }
  done
  ```

- **`git check-attr merge -- <path>`** to ask whether a file may be hand-merged, rather than parsing `.gitattributes` by hand.
- **`ours`/`theirs` are operation-dependent.** During a rebase they're inverted relative to a merge: `ours` is the upstream, `theirs` is your own commit being replayed. Any skill touching conflicts states which operation it's in before naming a side.
- **`git status --porcelain`, not `git diff --name-only HEAD`**, to see what a worktree is doing right now. A file an agent created and never `git add`ed is untracked, and a diff against `HEAD` does not list it — which is most of what a few minutes of agent work looks like. The diff form silently reports a busy worktree as clean.
- Prefer `git ls-files` over `find` — it respects `.gitignore` for free.
- BSD `sed` (macOS) has no `\b`. Use `perl -pe` for word-boundary replacements in tooling, or the substitution silently does nothing. **`git grep` does support `\b`** on macOS — verified — which is what the §7.1 assertion predicates rely on.
- **Assertions evaluate anchor-first.** Resolve the anchor, *then* the predicate. Anchor gone means `unresolvable`, never `violated` (I13) — every legitimate refactor moves an anchor, and a rename reported as a failure gets the whole check switched off (I16).

## Arguments

Every skill has an `## Invocation` block near the top listing what it accepts, and every argument has a derived default — including `scope-work`, which reads the incoming request from the session if none is passed. No skill requires an argument to start.

The rule is not "derive silently" but **derive, then say what you derived**. A default that's wrong and unreported is worse than a question, because the output looks completely normal. `README.md` has the consolidated table and the six cases where a default can be wrong.

## Commands

No build or test suite. To install a skill for Cursor:

```bash
ln -s "$(pwd)/skills/<name>" ~/.cursor/skills/<name>
```

To enable the optional hooks in a repo:

```bash
git config core.hooksPath hooks
```

## Editing

When changing a skill, read the existing `SKILL.md` first and match its tone and structure. Update `README.md`, `SPEC.md`, and this file if you add, remove, or rename skills.

Shell in a `SKILL.md` gets run by an agent against a real repo. Test it against this repo before committing it — every command in `baseline-scan` was verified that way, and one of them (the coupling `awk`) was wrong in a way that only showed up when run.
