# CLAUDE.md

## Repository purpose

git-intent combines sparse semantic governance with short-lived planning and prospective-tree Git
landing. Read [SPEC.md](SPEC.md) for the design of record.

## Core invariants

- Brief read-only, then create `intent/work/<uuid>` before every repository mutation and merge-land
  it; direct landing exists only for an unborn integration branch.
- Branch isolation and governance adoption are independent decisions.
- Missing governance never initializes state or blocks ordinary work.
- Domains are semantic responsibility clusters, not filesystem boundaries.
- Contracts are relied-on cross-domain promises with executable verification.
- Constraints are accepted permitted-shape assertions; verification is optional and semantic
  review is always required when they apply.
- Audits and observations are tracked evidence, not authority, and never enter governing digests.
- Runtime contains only ignored plans and leases shared through the primary worktree.
- Plans validate DAG, reliance order, checks, and unordered claim disjointness mechanically.
- Leases use Git ancestry and intersection for freshness; time only schedules liveness checks.
- Landing validates the exact prospective tree and compare-and-swaps the target ref.
- Landing requires an explicit durable-boundary disposition; new topology is only a review signal.
- Failed landing never moves the target.
- Push and other external effects require explicit request authority.

## Write ownership

| Component | Writes |
|---|---|
| `intent-brief` | nothing |
| `intent-coordinate` | ignored `.intent/runtime/` plans and leases |
| `intent-audit` | tracked `.intent/audits/` and durable non-authoritative observations |
| `intent-record` | domains, contracts, constraints, and defining architecture material |
| `intent-land` | local commits, integration refs, and completed runtime cleanup |

## Configuration

Schema version remains `1`:

```yaml
version: 1
resolution: assisted
integration_branch: main
```

Both fields after `version` are optional. Do not add planning autonomy, worker capability,
question timing, docs roots, push authority, or adoption preference to configuration.

## Verification

Run every shell test:

```bash
for test_file in tests/test-*.sh; do sh "$test_file" || exit; done
```

Use POSIX shell for scripts and test deterministic mechanics rather than policy wording.
