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
  day 1              day 3            day 12           day 14         + 3 days
    │                  │                │                │                │
    │  both will       │  "the limiter  │  merges        │  retries       │  incident
    │  touch           │   must wrap    │  clean         │  unmetered     │
    │  dispatch()      │   retries"     │                │  in prod       │
    ▼                  ▼                ▼                ▼                ▼
 collision-scan   capture-diff    resolve-conflicts  semantic-scan     bisect-report
    ~1 min          ~30 sec          only if git       ~2 min           half a day,
  before you      the one line       conflicts —      the only thing    after someone
  start           nothing else       it didn't        that catches      notices
                  can recover        here             this one
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

A few things are worth turning on in a repo where several agents are working. All are opt-in and none is needed for any skill to function.

**Live capture.** Copy the block from [`AGENTS.example.md`](AGENTS.example.md) into that repo's `CLAUDE.md`, `AGENTS.md`, or `.cursorrules`. This is what makes `capture-diff` record the approach you abandoned at 11am instead of losing it by Thursday — a decision being dropped leaves no git state, so no hook can catch it and no command can be scheduled for it. Only something already in the session can.

**The parallel operating block.** The same [`AGENTS.example.md`](AGENTS.example.md) carries a heavier block for repos running agents in worktrees: one branch = one worktree, collision-scan before you write, the pre-land invariant gate before you land, reconcile after. It's what makes agents operate like careful integrators rather than trampling each other — and it's where you set the automation level (`assisted` by default, `full` once the invariants and tests are trustworthy enough to be the backstop).

**Event nudges.** [`hooks/`](hooks/) ships `post-checkout` and `post-merge`, which print a one-line suggestion when a branch is created or work lands:

```bash
git config core.hooksPath hooks
```

They print to stderr and exit 0 — a hook can't run an agent, so these detect the moment and tell you which skill handles it. Read [`hooks/README.md`](hooks/README.md) first: `core.hooksPath` replaces your existing hooks wholesale, and there's a symlink alternative if you already have some.

**Checks on the pull request.** [`ci/`](ci/) ships a POSIX script and a workflow example. Review and merge happen in a browser tab, which is the one place no agent session reaches, so this is the transport that puts findings where the decision is actually made — a note that has gone stale, or a claim its author said had to survive that no longer holds. Only a broken claim fails the build; a renamed function is a question, not a failure, because otherwise the checks get switched off in a week.

## The skills

Seven skills — one before a branch exists, six from cutting it to landing it. Everything is git-native; the intent layer is the small committed residue they leave behind for the next actor to read.

| | |
|---|---|
| [`scope-work`](skills/scope-work/SKILL.md) | **Arriving.** Before any branch exists: is this request one unit of work or several independently-buildable ones? If several, which fork in parallel, which must sequence, and the contract each fork codes against. Won't fan out the steps of one unit, and won't fork two it can't hand a written contract |
| [`collision-scan`](skills/collision-scan/SKILL.md) | **Starting.** Who else is working in your code and what they're trying to do, while it's still cheap to talk. Local worktrees first — including uncommitted work no remote scan sees — then live remote branches |
| [`capture-diff`](skills/capture-diff/SKILL.md) | **Working.** What a branch changed and why, into `.branch-notes/<branch>.md` — the abandoned approach, the requirement, and the invariant that must survive later work. The one skill that writes testimony. Live during the work, or reconstructed on demand |
| [`review-diff`](skills/review-diff/SKILL.md) | **Ready.** Risk-ordered summary for reviewers — or, given a ticket, a requirement-by-requirement check. Also reports when the note is missing, a stub, or behind the branch |
| [`semantic-scan`](skills/semantic-scan/SKILL.md) | **Landing.** Conflicts git never reported (a contract changes here, a caller depends on the old one there, merges green, fails in production); the pre-land gate that stops a branch from silently undoing a peer's or a landed branch's invariant; and `--order` for a merge queue. Ranks a whole repo by exposure before analyzing anything |
| [`resolve-conflicts`](skills/resolve-conflicts/SKILL.md) | **Conflict.** Reconstructs what each side meant, composes both where compatible, verifies with tests. Proposes by default; `--auto` applies and verifies, stopping only on a contradiction, a broken invariant, or a red test. Merge, rebase, cherry-pick, revert, stash |
| [`reconcile-notes`](skills/reconcile-notes/SKILL.md) | **Landed.** Archives the notes of branches that shipped, keeps their invariants live against later landings, invalidates the baseline, reports what the merge made false — and `--notes` cuts the changelog |

Below the loop, two supporting roles:

| | |
|---|---|
| [`baseline-scan`](skills/baseline-scan/SKILL.md) | *Infrastructure.* What the repo is, computed — structure, hot and dormant areas, ownership, which files change together. The shared cache the six read; regenerates in seconds. Rarely run by hand |
| [`onboard-file`](skills/onboard-file/SKILL.md) · [`bisect-report`](skills/bisect-report/SKILL.md) | *Optional, off-loop.* Why a file is shaped like this and who to ask; and the commit behind a regression with its mechanism. Useful, but not part of branch → landing — install if you want them |

`collision-scan` and `semantic-scan`'s analysis look like neighbours and aren't. The first compares work whose paths **intersect** — will these collide when they land. The second's analysis compares work whose paths are **disjoint** — did they break each other without colliding. Each hands off by name when it sees the other's population. (`semantic-scan`'s `--order` and pre-land gate sit above that line and use both — see its SKILL.)

## What each skill takes

Every argument has a derived default, and every skill states which default it used. Deriving silently isn't the goal — a wrong default that goes unreported produces output that looks completely normal, which is worse than having asked.

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
| `onboard-file` *(optional)* | asks for a path | a path · `:88` · `:88-104` · a symbol |
| `bisect-report` *(optional)* | asks for a check command | a check command · `--good` · `--bad` · `--runs N` |

**Liveness, not recency.** `collision-scan` and `semantic-scan --order` both need "which branches count", and a date window is the wrong filter — it drops a nine-day-old branch that rewrites your function and keeps one that got a README typo fix this morning. Both rank instead, on commit recency, commits ahead, divergence behind, and whether the branch has already landed, then take the top `--live N`. The cut is a budget: what falls below it is counted, and anything below it that shares a path with you is named anyway.

**`--worktrees` and `--local` are different things** and deliberately not the same word. `collision-scan --worktrees` means parallel agents on this machine, including uncommitted work no remote scan can see. `reconcile-notes --local` means classify notes against local branches only — which is the dangerous mode, since a fresh clone has one local branch and would sweep almost everything.

**`semantic-scan --exposure`** ranks every live branch pair by accumulated risk — divergence, fork-point age, disjoint surface, interface weight, and how long since that pair was last checked — without reading a diff. It's what makes the skill usable on a repo with a six-week feature branch and thirty open PRs: rank in seconds, analyze the top three.

**Two skills can't start on their own**, and asking is right rather than a gap. `bisect-report` needs a reproduction because only the person seeing the bug knows what reproduces it, and a bisect against a guessed test spends an hour confidently blaming a random commit. `onboard-file` needs a path because its output is shaped around one file's decisions, and averaging that over a directory produces nothing actionable.

A bare positional is the target branch everywhere except `semantic-scan --order`, where positionals are branch names and the target moves to `--target`. Passing requirement text to `review-diff` switches it from a risk-ordered summary to a clause-by-clause check. `reconcile-notes --notes --audience` takes `integrators`, `on-call`, or `users`, and changes what gets promoted rather than just the tone — a library changelog leads with breaking changes, an internal service's leads with what on-call needs at 3am.

**`resolve-conflicts --auto` and the automation level.** By default every conflict resolution and every invariant-violating landing stops for a human (`assisted`). A repo can set `full` in its agent rule, or a single call can opt in with `--auto` — either way the agent applies and verifies autonomously and stops only on three things: an intent contradiction, a broken invariant, or a failed test. Those three are what make full automation safe, so a repo with thin capture and no graduated tests shouldn't run it. See [`AGENTS.example.md`](AGENTS.example.md).

## Where files live

| | Path | Committed? |
|---|---|---|
| Derived facts about the repo | `.git/intent/base.md` | No — a cache, shared across worktrees |
| A branch's testimony | `.branch-notes/<branch>.md` | Yes, on that branch only |
| Testimony for landed branches | `.branch-notes/_archive/<branch>.md` | Yes, on the integration branch |
| Merge policy | `.gitattributes` | Yes — you write this, no skill does |
| Ownership | `CODEOWNERS` | Yes — you write this, no skill does |

One question sorts every row: **can this be regenerated from the repository tomorrow?** Yes means cache, and the cache is never authoritative — on disagreement the code is right. No means commit it. Already enforced by git means don't duplicate it.

Three consequences worth knowing before you run anything.

The baseline is keyed off `git rev-parse --git-common-dir`, so **five worktrees on five parallel branches share one cache** rather than computing five.

A branch's note lives only on that branch, which is what keeps notes free of self-conflict — but it also means reading someone else's takes `git show <ref>:<path>`, never `cat`. A `cat` returns nothing and doesn't error, so a skill that gets this wrong reconstructs from the diff while reporting that it read testimony.

**An integration branch has no note and never will.** `develop` isn't a unit of work; it's an accumulation of them. When a merge from `develop` conflicts, the incoming side's intent is the `_archive/` entries of the branches that landed since your fork point — usually one or two of fifteen actually touch the conflicted paths, and each was written by whoever made that specific change.

Reasoning about *why* at a scope larger than a branch — the standing constraint, the architectural decision — belongs in `README.md`, `ARCHITECTURE.md`, and `docs/adr/`. Those are reviewed, versioned, and owned. git-intent points at them and never restates them.

## Design

The reasoning behind all of this — the state model, when each skill runs, the gate classes, the transports, and the invariants — is in [`SPEC.md`](SPEC.md).

### What gets read

Skills read `.branch-notes/`, and those files arrive through pull requests like any other content. A note is a record of what someone decided, not instructions to follow. Anything that would change how a conflict is resolved — a rule that skips a file, defers to one side, or bypasses verification — gets confirmed by a person first, and a rule arriving in the same PR as the code it exempts is worth naming out loud.

Moving merge policy into `.gitattributes` closes most of this: it's a file reviewers already treat as infrastructure, and git enforces it rather than an agent choosing to.

## Layout

```
git-intent/
├── SPEC.md                the state model, when skills run, gates, transports, invariants
├── AGENTS.example.md      copy into your repo to enable live capture
├── hooks/                 optional git hooks for two of the moments
├── ci/                    optional pull-request checks — script + workflow example
├── CLAUDE.md              for working on git-intent itself
└── skills/*/SKILL.md      one folder per skill
```