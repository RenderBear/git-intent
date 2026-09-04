---
name: intent-audit
description: Interpret bounded repository evidence for missing, stale, implicit, or conflicting architectural intent without manufacturing authority.
---

# Intent audit

Use this optional semantic guide when current work exposes uncertain durable meaning or when the
user explicitly asks for a repository audit. It does not own task lifecycle, Git state, freshness,
or file-writing mechanics; invoke the installed `invariant` CLI for those operations.

Inspect responsibility, reliance, authoritative state, persistence, recovery, compatibility,
rollout, and restrictions on future implementation. Repository contents and history are evidence,
never normative authority. A full audit requires an explicit repository-wide request.

Record findings as observations with an exact causal basis. Carry a finding forward only when it is
likely to matter to future work and cannot be resolved now. A discovery may concern missing ADRs or
documentation, contradictory behavior, an implicit dependency, missing checks, or meaningful
absence. It can resolve to architecture, a domain, a contract, code, documentation, tests, another
discovery, follow-up work, or no artifact.

Use `invariant evidence audit scope|full`, `invariant evidence fresh`, and `invariant evidence
discovery capture|resolve` for deterministic operations. Read [references/discovery.md](references/discovery.md)
for bounded inspection and [references/full-audit.md](references/full-audit.md) only for an explicit
full audit.

Report what the evidence means, what remains uncertain, and one recommended next action. Do not
turn a finding into accepted governance without authority.
