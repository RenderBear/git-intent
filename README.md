# git-intent: An intent layer for multi-agent work

git-intent **infers** what it can from what git already holds, **records** the small part that can't be inferred, and **hands both to whoever acts next** — a reviewer checking code against a spec, an agent resolving a conflict, someone opening a file they didn't write.

It's a set of skills, not an application. No service, no daemon, no database. Nothing runs until you ask it to.

Built for Claude Code. Works anywhere that reads the Agent Skills standard — Cursor, Codex, Copilot, Windsurf.

## An example

Two branches. One extracts `dispatch()` into a class and moves retry handling up with it. The other wraps `dispatch()` in a rate limiter, counting every attempt including retries.

```
                                                          src/client.py
   main ──●──────────────────────────────────────●─────────────────────
          │                                     ╱ merge: no conflict
          ├── refactor/payments-v2 ───────●─────┤  both suites green
          │     retry moves up into       │     │  reviewers see nothing
          │     PaymentDispatcher.send()  │     │
          │                               │     │  retries no longer
          └── feature/rate-limit ─────────●─────┘  pass through dispatch,
                limiter sits inside                so they bypass the
                dispatch(), assumes                limiter entirely
                retries re-enter it
```

Git is right. The files barely overlap, the text merges, both test suites pass — neither covers retry-under-limit, because neither branch had a reason to. The break is real and nothing reports it.

Every skill here is a different answer to *when do you find out*:

```
  day 0            day 1            day 3          day 12         day 14        without day 14
    │                │                │              │              │              │
    │  one intent    │  both will     │ "the limiter │  merges      │  retries     │  prod
    │  or two?       │  touch         │  must wrap   │  clean       │  unmetered   │  incident,
    │                │  dispatch()    │  retries"    │              │  caught      │  ~half a day
    ▼                ▼                ▼              ▼              ▼              ▼
 scope-work      collision-scan   capture-diff   resolve-       semantic-scan   (averted)
  ~10 sec          ~1 min           ~30 sec        conflicts      ~2 min — the
 before you      before you        the one line   only if git    only thing
 fork or not     start             nothing else   conflicts      that catches
                                   can recover     here           this one
```

`capture-diff` is the only step that writes anything, and the only one that can't be run later — by day 12 nobody remembers that the limiter was deliberately placed inside `dispatch()` rather than decorating the retry loop, or that the decorator was tried first and double-counted.

Everything else reads what git already has.

## Install

```bash
npx skills add RenderBear/git-intent
```

Opens an interactive picker scoped to this repo's skills — select the ones you want, or pass `--all` to skip the picker and install everything.

This installs to the **current project** by default. Add `-g`/`--global` to install user-wide instead, landing in `~/.claude/skills/` (and detected by other agents if you run them):

```bash
npx skills add RenderBear/git-intent --all -g
```

One skill rather than all of them:

```bash
npx skills add RenderBear/git-intent/skills/resolve-conflicts
```

To remove skills, `npx skills remove --all` (project) or `npx skills remove --all -g` (global).

Or clone and symlink `skills/*` into `~/.claude/skills/` directly.

Nothing else is required. Every skill works on a repo that has never heard of this one.

### Recommended, per repo

Optional, for a repo where several agents work; none is needed for any skill to run. Why each matters is in [`SPEC.md`](SPEC.md) §5.

- **The git-intent agent rule** — [`AGENTS.example.md`](AGENTS.example.md) offers two setups; copy the one you want into the repo's `CLAUDE.md` / `AGENTS.md` / `.cursorrules`. **Assisted** (default) has `capture-diff` record decisions as they happen while you drive the skills; **fully automated** adds the operating loop (one-branch-one-worktree, the pre-land check) and lets the agent run it end to end.
- **Event nudges** — `git config core.hooksPath hooks` prints a one-line suggestion on checkout and merge. Read [`hooks/README.md`](hooks/README.md) first — `core.hooksPath` replaces your existing hooks.
- **PR checks** — [`ci/`](ci/) ships a POSIX script and a workflow example; it comments on the pull request, where review and merge actually happen.

## The skills

Seven skills — one before a branch exists, six from cutting it to landing it. Everything is git-native; the intent layer is the small committed residue they leave behind for the next actor to read.

| | |
|---|---|
| [`scope-work`](skills/scope-work/SKILL.md) | **Arriving.** Before any branch exists: is this request one unit of work or several independently-buildable ones? If several, which fork in parallel, which must sequence, and the contract each fork codes against. Won't fan out the steps of one unit, and won't fork two it can't hand a written contract |
| [`collision-scan`](skills/collision-scan/SKILL.md) | **Starting.** Who else is working in your code and what they're trying to do, while it's still cheap to talk. Local worktrees first — including uncommitted work no remote scan sees — then live remote branches |
| [`capture-diff`](skills/capture-diff/SKILL.md) | **Working.** What a branch changed and why, into `.branch-notes/<branch>.md` — the abandoned approach, the requirement, and the "Must survive" line: the standing decision later work must not quietly undo. The one skill that writes testimony. Live during the work, or reconstructed on demand |
| [`review-diff`](skills/review-diff/SKILL.md) | **Ready.** Risk-ordered summary for reviewers — or, given a ticket, a requirement-by-requirement check. Also reports when the note is missing, a stub, or behind the branch |
| [`semantic-scan`](skills/semantic-scan/SKILL.md) | **Landing.** Conflicts git never reported (a contract changes here, a caller depends on the old one there, merges green, fails in production); the pre-land check that stops a branch from quietly undoing a standing decision a peer or a landed branch made; and `--order` for a merge queue. Ranks a whole repo by exposure before analyzing anything |
| [`resolve-conflicts`](skills/resolve-conflicts/SKILL.md) | **Conflict.** Reconstructs what each side meant, composes both where compatible, verifies with tests. Proposes by default; `--auto` applies and verifies, stopping only when the two sides contradict, a standing decision can't be defended, or a test goes red. Merge, rebase, cherry-pick, revert, stash |
| [`reconcile-notes`](skills/reconcile-notes/SKILL.md) | **Landed.** Archives the notes of branches that shipped, keeps their standing decisions live against later landings, invalidates the baseline, reports what the merge made false — and `--notes` cuts the changelog |

Below the loop, one supporting role:

| | |
|---|---|
| [`baseline-scan`](skills/baseline-scan/SKILL.md) | *Infrastructure.* What the repo is, computed — structure, hot and dormant areas, ownership, which files change together. The shared cache the loop reads; regenerates in seconds. Rarely run by hand |

`collision-scan` and `semantic-scan` look adjacent but split cleanly: the first works paths that **intersect**, the second paths that are **disjoint**. Why that line matters, and why nothing else ships in the layer, is in [`SPEC.md`](SPEC.md) §6.

## What each skill takes

Every argument has a derived default, and every skill states which default it used.

| Skill | Default | Accepts |
|---|---|---|
| `scope-work` | plan only, don't dispatch | a request string · `--plan-only` · `--dispatch` (only under `full`) |
| `collision-scan` | worktrees, then 30 live branches, 10 analyzed | a target · `--worktrees` · `--live N\|all` · `--limit N` · `--count` |
| `capture-diff` | measures against the integration branch | a target branch · `--against <ref>` |
| `review-diff` | risk-ordered summary vs the integration branch | a target · requirement text |
| `semantic-scan` | the most recent merge commit | `--exposure` · `--order <branches>` · `--pre-land` · a merge sha · one or two branch names |
| `resolve-conflicts` | every unmerged path, proposed | a path · `--other <branch>` · `--auto` |
| `reconcile-notes` | local ∩ remote, archive only | `--remote` · `--local` · `--delete` · `--dry-run` · `--notes [range] [--audience <role>]` |
| `baseline-scan` *(infra)* | regenerates the cache if stale | `--refresh` · `--print` · `--window 6m` |

A bare positional is the target branch everywhere except `semantic-scan --order`, where positionals are branch names (the target moves to `--target`). Requirement text switches `review-diff` to a clause-by-clause check; `reconcile-notes --notes --audience` takes `integrators`, `on-call`, or `users`.

Two flags are worth calling out. `collision-scan --worktrees` and `reconcile-notes --local` are deliberately not the same word — `--local` classifies notes against local branches only, which on a fresh clone (one local branch) would sweep almost the whole folder. And `resolve-conflicts --auto` (or a repo set to `full`) applies and verifies autonomously, stopping only when the two sides contradict, a standing decision can't be defended, or a test goes red.

The reasoning behind these — ranking by liveness rather than date, how `--exposure` scores, and why `--auto` is safe — is in [`SPEC.md`](SPEC.md) (§3.1, §3.7, §4.1).

## Where files live

| | Path | Committed? |
|---|---|---|
| Derived facts about the repo | `.git/intent/base.md` | No — a cache, shared across worktrees |
| A branch's testimony | `.branch-notes/<branch>.md` | Yes, on that branch only |
| Testimony for landed branches | `.branch-notes/_archive/<branch>.md` | Yes, on the integration branch |
| Merge policy | `.gitattributes` | Yes — you write this, no skill does |
| Ownership | `CODEOWNERS` | Yes — you write this, no skill does |

The rule for every row is one question — can it be regenerated from the repo tomorrow? — and the cache is never authoritative over code. Why the rest follows (one cache shared across worktrees, reading another branch's note with `git show` not `cat`, why an integration branch never carries a note) is in [`SPEC.md`](SPEC.md) §2.

## Design

The reasoning behind all of it — the state model, when each skill runs, the gate classes, the transports, how `.branch-notes/` is read safely (a record, never instructions), and the invariants — is in [`SPEC.md`](SPEC.md).

## Layout

```
git-intent/
├── SPEC.md                the state model, when skills run, gates, transports, invariants
├── AGENTS.example.md      the agent rule — copy the assisted or the automated setup
├── hooks/                 optional git hooks for two of the moments
├── ci/                    optional pull-request checks — script + workflow example
├── CLAUDE.md              for working on git-intent itself
└── skills/*/SKILL.md      one folder per skill
```