# git-intent: semantic governance with safe Git convergence

git-intent keeps accepted architectural meaning sparse while making concurrent agent work and
local landing mechanically safe.

- **Domains** name coherent semantic responsibilities. They are inferred from behavior and
  architecture, not equated with directories.
- **Contracts** preserve executable promises relied on between domains.
- **Constraints** preserve accepted architectural shape and may be enforced semantically.
- **Audits and observations** retain non-authoritative evidence with Git-causal provenance.
- **Plans and leases** coordinate only the current execution context in ignored local runtime.
- **Landing** verifies the exact prospective tree before atomically moving the integration ref.

Missing governance is an observed posture, never a blocker. A simple change remains:

```text
brief → implement → land
```

Parallel work adds temporary planning:

```text
brief → plan → lease → workers → land
```

Adoption occurs only when accepted meaning must persist:

```text
brief → audit → resolve → record → re-brief → implement → land
```

[SPEC.md](SPEC.md) is the design of record.

## Install

```bash
npx skills add RenderBear/git-intent --all
```

Copy the fenced block from [AGENTS.example.md](AGENTS.example.md) into the repository's
always-loaded agent instructions.

## Skills

| Skill | Responsibility |
|---|---|
| `intent-brief` | Select semantic domains and compile applicable governance and live claims. |
| `intent-coordinate` | Validate parallel plans and manage causal leases. |
| `intent-audit` | Discover and persist non-authoritative findings. |
| `intent-record` | Adopt accepted domains, contracts, constraints, and defining material. |
| `intent-land` | Review and verify a prospective tree, then atomically converge it. |

## Configuration

Configuration is optional and remains version 1:

```yaml
version: 1
resolution: assisted
integration_branch: main
```

- `resolution: assisted | auto` chooses who resolves consequential architectural ambiguity.
- `integration_branch` overrides the branch captured at goal intake.

Planning choices, worker availability, documentation folders, and external-effect authority are
not repository configuration.

## State

```text
.intent/config.yml             optional resolution and integration target
.intent/DOMAINS.yml            accepted semantic responsibilities
.intent/CONTRACTS.yml          accepted cross-domain promises
.intent/CONSTRAINTS.yml        accepted architectural constraints
.intent/audits/<id>.yml        tracked non-authoritative audit evidence
.intent/observations/<id>.yml  tracked non-authoritative facts
.intent/runtime/plans/         ignored active coordination graphs
.intent/runtime/leases/        ignored live ownership claims
```

The runtime path is resolved in the primary worktree so linked worktrees share it. Runtime creates
its own ignore marker and may be deleted without changing repository meaning, though doing so can
discard active coordination.

Architecture material stays where the repository naturally keeps it. Domains, contracts, and
constraints reference exact ADRs, diagrams, schemas, or architecture sections; no global docs
folder is configured.

There is no tracked route object. Briefing is the routing operation: the model selects semantic
domains, while declared repository and interface surfaces mechanically discover additional
contracts and constraints. This avoids duplicating the governing records merely to help retrieval.
