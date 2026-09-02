# intent-review — independent review input

Give a reviewer only:

1. the narrow unit goal and diff;
2. the compiled intent brief, maximum eight rows;
3. the exact optional `.intent/exceptions/<unit>.yml` and runtime check results;
4. the unit's proposal files only when work is genuinely concurrent.

Ask the reviewer to refute each routed contract and active decision affected by the diff. Domain
direction is checked against its source; architecture is checked against the linked section,
opened only after a concrete concern.

Challenge every active exception and any governing pointer the change moves. Commands and results
come from the runtime review packet and are never persisted.

Do not attach the full route or decision set, unrelated exceptions, history, unrelated ADRs,
leases for other scopes, or commit logs. Retrieve a named source only when needed. Rejected
approaches are retrieved only when the change recreates a specific known failure.

The reviewer writes findings, not intent state. A finding that creates a durable non-testable
decision goes through `intent-record` with explicit provenance after authority resolution.
