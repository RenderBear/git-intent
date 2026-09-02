---
name: intent-land
description: Verify the exact prospective integration tree and atomically land it with honest scope metadata. The integration ref never moves on a failed preflight.
---

# intent-land

Landing is one convergence operation. It owns commits and local integration; it does not invent governance.

## Resolve authority

Recompute reach against the actual candidate diff.

- `local` — run repository checks and land.
- `bounded` — run every affected contract verifier; green lands.
- `open` — run all verifiers and resolve the semantic transition.
- `gated` — require accepted authority for the breaking contract transition.

With `escalation: human`, a consequential unresolved transition goes to the human. With `escalation: agent`, the agent may resolve it only within already accepted intent. Weakening user-defined contracts, incompatible authoritative goals, security, money, production data, irreversibility, and unauthorized external effects remain hard gates.

Pass `--allow-open` to the landing script only after that authority has been resolved. `intent-record` captures a resolution only when it is durable; it does not decide who resolves it.

## Atomic landing

Use `scripts/land-support.sh`:

```text
land-support.sh direct <subject>
  --unit <id>... --scope <scope>...
  --paths <path>...
  [--check command:<executable>]...
  [--allow-open]

land-support.sh merge <branch> <subject>
  --unit <id>... --scope <scope>...
  [--board <id>]
  [--check command:<executable>]...
  [--allow-open]
```

The script:

1. captures the current integration head;
2. constructs a candidate tree and commit without moving the target;
3. validates intent state and trailer containment against that commit;
4. executes affected contract verifiers and repository checks in a detached worktree of the exact candidate;
5. caches successful receipts by tree and check identity;
6. compare-and-swaps the integration ref;
7. updates the integration worktree and releases completed leases.

A failed verifier, conflict, invalid claim, stale target, or unresolved gate leaves the integration ref unchanged.

Run landing from the integration worktree. A configured `integration_branch` must exist unless it is the current unborn branch before the root landing. Without one, the branch current at intake is the target; coordination carries that captured target into every lease.

## Boundaries

Local Git landing is authorized by an implementation request. Push, deploy, publish, destructive cleanup, and other external effects require explicit request authority.

After success, report the target, commit, units, scopes, checks, and any remaining coordination. Recurrent unrouted areas may be suggested for later adoption, but adoption never reopens the completed landing.
