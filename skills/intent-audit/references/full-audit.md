# Full repository audit

A full audit requires an explicit human request. `--assisted` and `--auto` control resolution while
the requested audit runs; they do not manufacture authority.

Inspect bounded batches of semantic responsibility and reliance:

- known domains and architecture material;
- public schemas, protocols, APIs, jobs, events, and cross-domain consumers;
- accepted architectural constraints and optional fitness checks;
- tracked observations and prior audits whose evidence may have changed;
- verifier and repository-check entrypoints.

Do not score filesystem coverage or propose a domain for every directory. Report accepted intent,
stale or contradictory records, unprotected critical reliance, missing architectural constraints,
durable observations, authority questions, and no-action areas.

Write one or more `.intent/audits/<id>.yml` reports with causal grounds. Run declared contract
verifiers when safe. A failure is evidence, never permission to rewrite the promise. End each batch
with the exact next transition to `intent-record`, resolution, verifier work, or no action.
