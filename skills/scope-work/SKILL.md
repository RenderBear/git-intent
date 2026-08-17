---
name: scope-work
description: Scope an incoming request before any branch exists — decide whether it is one unit of work or several independently-buildable ones, map the dependencies between them, and decide what can be built in parallel, what must be sequenced, and the contract each parallel fork codes against. Use this at the very start, when a request or ticket arrives that may contain several unrelated changes, when the user asks how to approach or parallelize a piece of work, or before spinning up multiple worktrees. It produces a plan and the setup for each unit; it does not spawn the agents itself. Do not fan out the steps of a single unit, and when two units can't be handed a written contract, sequence them rather than racing them.
---

# scope-work

This runs before anything else — before a branch, before a diff, at the moment a request arrives. It scopes the request: is this one unit of work or several, and if several, how do they get built without breaking each other on the way back together? A single unit is the common, correct answer, and reaching it is the skill doing its job — the point is to *decide the shape of the work*, not to split for the sake of it.

**The unit of work is the independently-buildable change, not the list item.** A request numbered "1, 2, 3" is not three parallel tasks; three sentences describing one change are not three tasks either. What decides is whether two pieces can be built against a fixed interface without seeing each other — a judgment about contracts, not about how the request was phrased.

Getting this wrong is expensive in a specific way. Two units that secretly share a contract, forked to two agents, produce disjoint diffs that merge clean, pass their own tests, and are wrong in production — the exact failure `semantic-scan` exists to catch after the fact. This skill's job is to not create that situation in the first place.

## What this skill is not

- **It does not spawn agents.** It scopes and plans; the runtime (a sub-agent-capable agent, a harness, or a human) executes any fork. The skill emits the branches, worktrees, contracts, and per-unit briefs — the dispatch is a separate, gated step.
- **It does not break one unit into parallel steps.** "Add rate limiting" needs a model, a route, and a test, but those are one unit with an order, not three forks. Fanning out the steps of a single change is how you get three agents contending for one file.
- **It is upstream of `collision-scan`.** Collision-scan compares work that has already started; this runs before it exists, on *predicted* surface. Once each unit has a branch, the normal loop takes over (see *Next*).

## Invocation

```
/scope-work "add per-client rate limiting, and fix the timezone bug in #412"
/scope-work                         # read the request from the current session/task
/scope-work --plan-only             # never dispatch; emit the plan and stop (default under `assisted`)
/scope-work --dispatch              # under `full`: hand the plan to the runtime to spawn forks
```

Default is `--plan-only`: produce the scope and the setup, let a human or the runtime start any forks. `--dispatch` is honored only at automation level `full` (see `AGENTS.md`), and even then a violated contract-cut (below) drops back to proposing.

## Workflow

### 1. Enumerate the units of work

The test for a separate unit: **could it land as its own pull request and be reverted without touching the others?** If yes, it's a unit. If reverting it would half-break another piece, they're one unit with internal steps.

Read the request and the baseline so the enumeration is grounded in what the repo actually is:

```bash
cat "$(git rev-parse --git-common-dir)/intent/base.md" 2>/dev/null
```

List the units plainly. Two or three is the common useful case; a request that decomposes into ten "units" is usually one unit over-split, and saying so is the right output.

### 2. Predict each unit's surface

No diff exists yet, so this is inference, not measurement — say so. For each unit, predict the paths and symbols it would touch, using the baseline's structure and coupling. The prediction doesn't need to be exact; it needs to be right about **overlap** and **contracts**, which is all step 3 reads.

### 3. Build the dependency graph

For every pair of units, one of three relationships holds:

- **Independent** — disjoint predicted surface, no shared contract. **Fork in parallel.**
- **Shared surface** — both predicted to touch the same files. Running them at once races the same code; **sequence them**, or if the overlap is incidental, fork and let the normal `collision-scan` handle it — but flag it, don't assume.
- **Producer/consumer** — one unit creates or changes an interface the other depends on (a DB whose connection details `start.sh` consumes; a schema a caller reads). This is a **directed edge**: the producer lands first, *or* the contract is frozen first (step 5) and both fork against it.

The graph, not the count, is the plan. Its width at each level is how many agents run at once.

### 4. The contract-cut rule

This is the one rule that makes parallel safe, and it is a hard gate:

> **You may fork two units in parallel only if you can write down the contract between them now.** If you can't state the interface they must agree on, they are not independent — sequence them.

The failure this prevents is two agents independently inventing the two halves of a contract that doesn't exist yet, each internally consistent, disagreeing with each other. If the contract is statable, freeze it (step 5) and fork safely. If it isn't — because it depends on a decision only made while building — the units are entangled, and no amount of after-the-fact scanning recovers a contract that was never agreed. Sequence.

### 5. Freeze the shared contracts

For any parallel fork that shares a to-be-built interface, the contract has to become a real artifact **before** the fork, on the base branch both forks are cut from — so each codes against a fixed thing rather than against a moving sibling. Three forms:

- an interface stub or type signature,
- a short spec file, or
- an invariant registered with `capture-diff` on the base, so the pre-land gate can check neither fork drifted from it.

This skill **proposes** the artifact; it does not author tracked source itself (that is I1, and it holds here as everywhere). The source stub or spec is emitted as part of the plan for a gated step to commit; the invariant form goes through `capture-diff`, which is the one skill allowed to write. Either way the artifact lands on the base *before* dispatch — that ordering is the point. And if you can't produce the artifact, step 4 already told you not to fork; this step is only where "statable" becomes "stated."

### 6. Emit the plan

Per unit: a branch name, a worktree path, the frozen contracts it codes against, and a one-paragraph brief. Plus the parallel/sequential structure and the merge order — which is `semantic-scan --order`'s input, handed over rather than recomputed.

```
SCOPE — "add rate limiting, and fix the timezone bug in #412"
baseline: a3f21c8

2 units, independent — disjoint surface, no shared contract.

PARALLEL
  unit-a  feature/rate-limit    ../wt/rate-limit
    src/client.py — token-bucket limiter around dispatch(). No shared contract
    with unit-b. Brief: PROJ-412, per-client, must apply to retries.
  unit-b  fix/tz-412            ../wt/tz-412
    src/time.py — ISO offset parsing. Disjoint from unit-a.

Setup:
  git worktree add ../wt/rate-limit -b feature/rate-limit
  git worktree add ../wt/tz-412     -b fix/tz-412

Each fork then runs the normal loop: collision-scan → capture-diff → pre-land.
Merge order: independent, either first. (/semantic-scan --order to confirm.)
```

Contrast — the same skill on a request that must **not** fork:

```
SCOPE — "add a start.sh, and a dockerized DB"
2 units, but PRODUCER/CONSUMER — start.sh consumes the DB's connection
contract (service name, port, credentials, healthcheck).

Contract IS statable → freeze it first, then fork:
  1. write docker/db.env + compose service (name=db, port=5432) on the base
  2. THEN fork: unit-a implements the container, unit-b writes start.sh,
     both against docker/db.env.
Without the freeze: SEQUENCE (db first, start.sh second). Do not race them —
disjoint files, clean merge, start.sh waits on a container that isn't there.
```

### 7. The single-unit case

Most requests are one unit. When that's the answer, say it in a line and stop — no worktrees, no fork, no ceremony:

```
SCOPE — "add per-client rate limiting with a test"
1 unit. Model + route + test are steps of one change, not parallel work.
No fan-out. Start it on a single branch.
```

Manufacturing units to justify a fan-out is this skill's characteristic failure. A confident "this is one thing" is a real and useful result.

## Judgment

**When unsure, sequence.** Over-parallelizing costs a silent production break; over-sequencing costs a little wall-clock. The trade is not symmetric, so the default leans hard toward sequential.

**Don't inflate.** If there's one unit, say so and stop. A skill that forks everything to look useful trains people to ignore the plan, and then the one request that genuinely should parallelize gets started on a single branch anyway.

**The contract-cut rule is not advisory.** No statable contract, no parallel fork. This is the whole safety argument; a plan that forks units it can't give a contract has just scheduled a `semantic-scan` finding for next week.

**Prediction is prediction.** The surface and overlap here are inferred from the request and the baseline, before any code exists. Say so, and say that the real `collision-scan` and pre-land checks run once each fork has a diff — this skill sets up the fork, the loop keeps it honest.

**Parallel work is only as safe as its isolation.** Each unit gets its own worktree and branch, never a shared checkout. The cache is shared across worktrees automatically; the working trees are not.

## Next — close the loop

End by naming what each fork does next — this is moment 0, so the footer points into the loop it just set up.

```
Next
  · per fork: /collision-scan   confirm the predicted surface against what's really in flight
  · per fork: /capture-diff     record intent + the invariant, coding against the frozen contract
  · /semantic-scan --order      confirm the merge order before landing the set
  · --dispatch                  under `full`, hand the plan to the runtime to spawn the forks
```

On a single-unit result, the only next line is "start it on one branch" — the loop begins at `collision-scan`, not here.
