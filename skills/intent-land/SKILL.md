---
name: intent-land
description: Construct, review, verify, and atomically land the exact prospective Git tree while authenticating coordinated leases and preserving accepted contracts and constraints.
---

# intent-land

Landing is one convergence operation. It does not invent governance.

Recompute reach against the exact candidate. Run all emitted contract and constraint verifiers.
Semantically review every affected constraint against the candidate and pass its
`--reviewed constraint:<id>` acknowledgement. Under `resolution: assisted`, ask only when the
candidate conflicts with or changes accepted meaning; under `auto`, resolve within request
authority. Removing or rewriting accepted governance remains gated.

Use `scripts/land-support.sh direct|merge`. Pass every unit, derived scope, selected semantic
domain, explicitly claimed governance item, repository check, and runtime plan id. A coordinated
landing must have matching fresh leases; the script validates their branch, target, and combined
path/domain/governance coverage.

The script constructs a dangling candidate, validates intent and trailers in a detached worktree,
runs checks against that exact tree, and compare-and-swaps the integration ref. Conflict, failed
verification, missing semantic review, stale or mismatched lease, changed target, or unresolved
governance leaves the ref unchanged.

Use [references/conflict-resolution.md](references/conflict-resolution.md) for actual Git conflicts.
Local landing follows from an implementation request. Push, deployment, publication, destructive
cleanup, and other external effects require explicit request authority.
