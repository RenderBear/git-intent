---
name: intent-audit
description: Discover candidate intent and diagnose existing intent without writing repository state. Use scoped audits when current work exposes a critical durable boundary; run a full repository audit only when a human explicitly requests it.
---

# intent-audit

Audit is the only discovery path. It produces inspectable candidate packets; it never writes
`.intent/` or decides that a candidate has authority.

## Operations

```text
intent-audit scope [--paths ...]   inspect one planned or touched boundary
intent-audit full --autonomous     inspect the repository after one human authorization
intent-audit full --assisted       inspect with human clarification between uncertain batches
intent-audit recurrence            report recurrent unrouted derived boundaries
```

Use `scripts/audit-support.sh` for the deterministic map and candidate evidence.

## Scoped audit

A scoped audit may begin organically when `intent-brief` classifies current work as
contract-first, or when the user explicitly asks for discovery. Inspect only intended paths,
immediate consumers, schemas, public interfaces, executable checks, and stable governing sources.

Read [references/discovery.md](references/discovery.md) for fresh- and mature-repository handling.
When entering an unfamiliar repository, read
[references/orientation.md](references/orientation.md) and keep orientation derived and compact.

## Full audit

Run `full` only when the current human request explicitly asks for a whole-repository audit.
An agent, missing route coverage, recurrence report, or prior recommendation cannot authorize it.
The mode controls execution after authorization:

- `--autonomous` completes all bounded batches without pausing and lists unresolved authority;
- `--assisted` asks only when an answer would materially change a candidate batch.

Read [references/full-audit.md](references/full-audit.md) before running a full audit.

## Output boundary

Report the audited snapshot, evidence, contradictions, critical reliance seams, candidate batches,
and unresolved authority. Do not score route coverage, propose governance for every derived
boundary, or treat code and history as normative. Send accepted candidates to `intent-record`;
the audit itself never mutates durable state.
