---
name: intent-audit
description: Inspect a task scope or explicitly requested repository for missing, stale, or conflicting domains, contracts, constraints, and durable observations, then write a tracked non-authoritative audit report.
---

# intent-audit

Audit discovers evidence and writes `.intent/audits/<id>.yml`; it never grants authority or changes
accepted governance. Use a scoped audit when the durable meaning exposed by current work is
uncertain or the user requests discovery. Clear accepted meaning may proceed directly to
`intent-record`; do not manufacture an audit merely to add a record. A full audit requires an
explicit repository-wide request.

Run `scripts/audit-support.sh scope --paths ...`, or after full-audit authorization run
`full --assisted|--auto`. Read [references/discovery.md](references/discovery.md) for scoped work,
[references/full-audit.md](references/full-audit.md) for full work, and
[references/orientation.md](references/orientation.md) only in an unfamiliar repository.

Write the inspected `ground` commit and exact `tree`, semantic scope, paths, evidence, and bounded
findings. Classify each finding for the reader as adoptable, needing authority, needing a verifier,
observation-only, or no action. Existing implementation and history are evidence, never normative
authority.

End with one explicit transition:

- `NO RECORD NEEDED`;
- `RECORD READY — intent-record adopt`;
- `RESOLUTION REQUIRED`;
- `VERIFIER REQUIRED`.

`NO RECORD NEEDED` means future work remains correct without preserving a new responsibility,
relied-on promise, authoritative-state choice, operational property, or architectural restriction.
It is a conclusive boundary disposition, not a synonym for missing governance.

`scripts/audit-support.sh fresh <audit>` derives freshness from ancestry and intersecting evidence,
never timestamps. Accepted findings flow naturally to `intent-record`; no `candidate` selector is
required for the current audit context.
