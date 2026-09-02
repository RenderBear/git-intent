# Full repository audit

A full audit is an explicit, read-only examination of one repository snapshot. It looks for
important missing or inconsistent intent, not maximal route coverage.

## Invocation boundary

The current human request must explicitly authorize a full repository audit. A scoped finding may
recommend one but cannot start it. `--autonomous` and `--assisted` describe how the authorized
audit proceeds; neither changes semantic authority or belongs in `.intent/config.yml`.

## Evidence pass

Run `../scripts/audit-support.sh full --autonomous` or `--assisted`. Use its fixed facts to form
bounded inspection batches:

- derived architectural boundaries and declared package seams;
- existing route anchors, contracts, decisions, and exceptions;
- public schemas, protocols, and cross-boundary consumers;
- contract verifier declarations and repository check sources;
- stable architecture documents, ADRs, accepted specifications, and ownership evidence;
- recurrent unrouted boundaries from completed first-parent landings.

Validate existing intent and execute declared verifiers when safe and locally available. A failed
or missing verifier is a finding, never permission to rewrite the contract.

## Semantic pass

For each batch, distinguish:

- accepted intent that is correctly recorded;
- stale, contradictory, orphaned, or unverifiable recorded intent;
- a critical relied-on promise with inspectable authority that may deserve a contract;
- a stable boundary that may benefit from a route to existing authority;
- observed implementation with no normative standing.

Do not create candidates merely because a boundary is unrouted. Existing behavior and history
show structure and reliance, not authority.

## Report

Return:

```text
AUDIT SNAPSHOT
EXISTING INTENT
FINDINGS
CANDIDATE BATCHES
AUTHORITY QUESTIONS
NO-ACTION AREAS
```

Each candidate identifies its evidence, proposed scope and anchors, governing source, affected
consumers, and executable verifier when it is a contract. Autonomous mode leaves unresolved
authority as questions. Assisted mode may pause between batches when clarification changes the
candidate set. Neither mode writes `.intent/`; accepted candidates pass to `intent-record`.
