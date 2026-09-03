# git-intent: Intent layer for Agentic Work

git-intent gives coding agents a persistent, reviewable understanding of architectural intent,
along with local coordination and safe Git convergence. It can be adopted incrementally; a
repository does not need an upfront inventory or complete architecture model.

Work isolation and governance adoption are separate. Every repository mutation happens on a
generated work branch, while durable governance is added only when future work must preserve a
responsibility, relied-on promise, authoritative-state choice, operational behavior, or architectural
restriction. A large internal refactor may need no record; a one-line compatibility change may.

![Durable governance and temporary planning remain separate, then converge through prospective landing into Git.](.github/assets/domains-and-contracts.svg)

Domains, contracts, and constraints retain the small amount of architectural meaning agents must
not lose. The complete model is documented in [SPEC.md](SPEC.md).

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

Configuration is optional:

```yaml
version: 1
resolution: assisted
integration_branch: main
```

`resolution` controls who resolves consequential architectural ambiguity:

| Mode | Behavior |
|---|---|
| `assisted` | The agent handles routine work within recorded intent, but asks the user before resolving an ambiguous architectural change, compatibility promise, or consequential side effect. |
| `auto` | The agent may resolve those questions itself when the current request and recorded authority provide enough evidence. It still reports the resolution and records durable consequences when needed. |

Both modes enforce recorded contracts and constraints. Neither mode grants permission to contradict
explicit requirements or perform external actions such as pushing, deploying, publishing, or
destructive cleanup.

`integration_branch` optionally fixes the local convergence target. Without it, git-intent captures
the current branch when work begins.

## Repository state

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

Runtime is shared by linked worktrees through the primary worktree. It may be removed without
changing repository meaning, although doing so discards active coordination state.
