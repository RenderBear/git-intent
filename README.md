# git-intent: an intent layer for agentic work

git-intent adds an intent layer to agentic work over Git. It separates durable semantic
governance from temporary execution coordination.

- **Governed intent** records a sparse set of accepted macro directions, critical contracts,
  architecture pointers, decisions, and exceptions.
- **Routes** connect a semantic scope to those authorities. Routes carry no authority of their
  own.
- **Workboards and leases** coordinate live parallel work. They may be redrawn, become stale,
  and disappear without changing repository meaning.
- **Atomic landing** verifies the exact prospective tree before advancing the integration ref.

Missing governance is an operating posture, not an error. Unrouted work proceeds under the
current request, repository checks, live claims, and the consequence gate unless it creates a
critical durable boundary that must be established first.

[SPEC.md](SPEC.md) is the design of record.

## Install

```bash
npx skills add RenderBear/git-intent --all
```

Copy the fenced block from [AGENTS.example.md](AGENTS.example.md) into the repository's
always-loaded agent instructions.

## Skills

| Skill | Role |
|---|---|
| `intent-brief` | Read-only routing and posture compilation. |
| `intent-audit` | Read-only scoped discovery and explicitly human-requested full repository audits. |
| `intent-coordinate` | Ephemeral workboards, claims, dispatch, and leases when useful concurrency exists. |
| `intent-land` | Prospective-tree verification and atomic local landing. |
| `intent-record` | The sole writer of accepted routes, contracts, decisions, and exceptions. |

The routine lifecycle is:

```text
intent-brief → implement → intent-land
```

Coordination activates only for genuinely concurrent, independently owned, or handoff-sensitive
work:

```text
intent-brief → intent-coordinate → workers → intent-land
```

Intent is established only when the current work introduces or changes a critical durable
boundary:

```text
intent-audit scope → resolve authority → intent-record adopt → re-brief
```

A whole-repository audit starts only from an explicit human request. It may run autonomously or
pause for assistance, but remains read-only; accepted candidate batches flow to `intent-record`.

## Configuration

Configuration remains version 1 and is optional:

```yaml
version: 1
escalation: human
integration_branch: main
```

Both fields are optional.

- `escalation: human | agent` decides who resolves consequential semantic ambiguity.
  `agent` delegates judgment within already accepted intent; it does not authorize
  weakening user-defined contracts, incompatible authoritative goals, high-consequence effects,
  or external mutations.
- `integration_branch` is an optional local target override. Without it, the branch current at
  goal intake becomes the integration target and is carried through workboards and leases. A
  configured branch must exist, except for the current unborn branch before the first commit;
  detached HEAD without an explicit target is an error.

Worker availability, question timing, adoption preference, push permission, and mechanical
latitude are not tracked configuration.

## Intent state

The durable surface is deliberately small:

```text
.intent/config.yml                       optional resolver authority and target
.intent/ROUTES.yml                       sparse scope-to-authority pointers
.intent/CONTRACTS.yml                    accepted critical assertions and verifiers
.intent/decisions/<scope-root>/<id>.yml  rare active non-testable choices
.intent/exceptions/<unit>.yml            accepted temporary underdelivery
```

Runtime state lives in one visible, ignored workspace in the primary worktree. Every linked
worktree resolves the same location:

```text
intent-work/boards/         ephemeral coordination graphs
intent-work/leases/         live path/interface reservations
intent-work/observations/   disposable governing digest snapshots
intent-work/receipts/       disposable verification receipts
```

`intent-coordinate status` makes the contents and derived fresh/stale lifecycle visible. Cleanup
is dry-run by default; `clean --apply` removes completed boards, dead or quiescent leases, and
disposable caches while retaining live leases and incomplete boards. Atomic landing already
releases landed leases and removes completed boards.

## Establishing intent

A repository needs no bootstrap or inventory pass. Intent is discovered progressively as ordinary
work reaches critical durable boundaries: scoped audit, authority resolution, record, then
re-brief. A human may instead request a full autonomous or assisted audit; it remains read-only
and produces bounded candidates for `intent-record`.


