---
name: intent-coordinate
description: Create and operate the ephemeral leaseboard used only for genuinely concurrent, independently owned, or handoff-sensitive work. Owns workboards, claims, dispatch leases, and their causal lifecycle.
---

# intent-coordinate

Coordination is a runtime capability, not a semantic reach level and not repository configuration.

```text
intent-coordinate status          inspect boards, fresh/stale leases, and caches
intent-coordinate clean           preview safe runtime cleanup
intent-coordinate clean --apply   apply the reported cleanup
```

## Activation

Activate only when at least one condition holds:

- two or more independently verifiable units can execute concurrently;
- different workers need protected claims;
- a contract-setting unit must land before several consumers;
- work must survive an owner handoff or long interruption.

Do not activate for several directories, sequential steps, a single executor, or a one-unit contract change.

## Workboard

Run `scripts/runtime-support.sh ensure`, then write one ephemeral board at
`<primary-worktree>/intent-work/boards/<id>.yml`:

```yaml
version: 1
id: checkout
goal: Introduce checkout and update its consumers.
integration_target: main
units:
  - id: contract
    objective: Establish the shared checkout API.
    dependencies: []
    surfaces: [services/checkout/schema]
    verifies: [command:scripts/verify-checkout]
  - id: web
    objective: Update the web consumer.
    dependencies: [contract]
    relies_on: [checkout.api]
    surfaces: [apps/web]
```

A board is the temporary task board. Unclaimed entries are freely redrawable. Once a unit is leased or landed, its id and claim are pinned. It contains no status fields: `scripts/workboard-status.sh <id>` derives status from dependency edges, live leases, and `Intent-Unit` trailers.

The model proposes objectives and dependency edges. Validate these invariants mechanically:

- unordered units have disjoint path and interface claims;
- every dependency names a unit;
- shared contract setters precede their consumers;
- each unit has meaningful verification;
- the board captures the integration target chosen at intake.

Run `scripts/workboard-support.sh validate <id>` before dispatch.

## Dispatch

Discover worker availability from the active harness. Never read it from tracked configuration.

For each ready disjoint unit:

1. Create its branch and linked worktree just in time.
2. Mint a lease with `scripts/lease-support.sh create`, passing `--integration-target` from the board.
3. Give the worker only its objective, claim, dependencies, governing rows, digest, and checks.
4. Before accepting further work, run `lease-support.sh fresh <unit>`. A stale lease must be released and reacquired against the new ground.

Expiry only schedules liveness inspection. Reaping ends a reservation, never deletes the worker's branch or work.

## Visibility and cleanup

`intent-work/` is a visible, self-ignored workspace shared by every linked worktree. Run
`scripts/runtime-support.sh status` to inspect boards, fresh or stale leases, and cache counts. Run
`scripts/runtime-support.sh clean` for a dry-run cleanup report and add `--apply` to remove
completed boards, dead or quiescent leases, and disposable observation and receipt caches. Live
leases and incomplete boards are retained.

## Completion

Hand completed units to `intent-land` in dependency order. Atomic landing releases their leases. Delete the board automatically when all its units are landed. A branch containing verified work is ready, not complete.
