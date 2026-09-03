---
name: intent-coordinate
description: Build and operate the ignored runtime plan and leases for genuinely parallel, independently owned, or handoff-sensitive repository work. Do not use for a single uncoordinated unit.
---

# intent-coordinate

Coordination is the short-lived planning plane under the primary worktree's ignored
`.intent/runtime/`. It never creates governance.

Activate only when at least two independently verifiable units can run concurrently, distinct
owners need claims, a governance-setting unit precedes consumers, or a handoff needs durable local
ownership. Several files or sequential steps are insufficient.

## Plan

Write `.intent/runtime/plans/<id>.yml`:

```yaml
version: 1
id: ocr-bundle
goal: Add external OCR and update orchestration.
integration_target: main
integration_ground: <commit>
domains: [ocr.orchestrator, ocr.engine.external]
governing_digest: <digest>
units:
  - id: protocol
    objective: Adopt the engine protocol.
    dependencies: []
    paths: [.intent/CONTRACTS.yml, docs/architecture.md]
    governance: [contract:ocr.engine-protocol]
    provides: [contract:ocr.engine-protocol]
    verifies: [command:scripts/verify-ocr-protocol]
  - id: external
    objective: Implement the external engine.
    dependencies: [protocol]
    paths: [src/ocr/external]
    interfaces: [OcrEngine]
    relies_on: [contract:ocr.engine-protocol]
    verifies: [command:scripts/test-external-ocr]
```

Run `scripts/workboard-support.sh validate <id>`. It enforces target and ground validity, current
domain-governance digest, a DAG, verification declarations, provider-before-consumer order, and
disjoint unordered path, interface, and governance claims. Sharing a semantic domain alone never
creates a collision.

## Dispatch

Create generated `intent/work/<uuid>` branches and linked worktrees just in time. Mint one lease per dispatched unit with its
paths, interfaces, governance, domains, governing digest, branch, and captured target. Give the
worker only that unit's objective, dependencies, relevant governing rows, and checks.

Run `lease-support.sh fresh <unit>` before accepting more work. An intersecting integration
landing makes the lease stale; release and reacquire it against the new ground. Expiry only
schedules the causal liveness check.

Use `runtime-support.sh status` for visibility and `clean [--apply]` for bounded cleanup. Landing
authenticates every coordinated lease, releases landed units, and removes a completed plan.
