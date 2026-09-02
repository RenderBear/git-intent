---
name: intent-record
description: Record accepted durable intent by adopting, amending, retiring, or capturing routes, contracts, decisions, and exceptions. Use only when authority is explicit or already resolved; use intent-audit for discovery.
---

# intent-record

This is the only writer of tracked intent state. It records authority; it does not discover,
infer, or grant authority.

## Operations

```text
intent-record adopt     add accepted routes or contracts
intent-record amend     change accepted durable intent
intent-record retire    supersede or remove obsolete intent
intent-record capture   record a rare durable decision or exception
```

Input normally comes from an accepted `intent-audit` candidate. A complete direct user
instruction may be recorded without an audit when it already identifies the assertion, authority,
scope or surfaces, and verification needed for the record.

If the proposal still requires repository discovery, return it to `intent-audit`. If authority is
missing or incompatible, resolve it according to `escalation: human | agent` before writing.

## Write protocol

1. Identify the exact accepted candidate and its authority.
2. Classify the operation as adopt, amend, retire, or capture.
3. Change only the smallest durable rows that express the accepted result.
4. Run `../intent-brief/scripts/validate-state.sh` and every new or affected contract verifier.
5. Leave changes unstaged unless the invoking task explicitly owns staging.
6. Recompile the brief before dependent implementations diverge.

Routes record pointers, not meaning. Code and history may support an audit finding, but they never
become authority merely because they exist.

## Contract admission

Create a contract only when all are true:

- it is a durable normative promise;
- another component, actor, or workflow relies on it;
- changing it could change accepted behavior;
- authority is inspectable;
- affected surfaces are identifiable;
- preservation has executable evidence.

Prefer `command:<repo-relative-executable>` verifiers. A known-critical assertion without a verifier may be routed as a governing direction, but it is not an active operational contract until verifier work lands.

A route does not imply a contract. Most derived boundaries should remain ungoverned or route-only.

## Amendments and retirement

Purely additive contracts, surfaces, and verifier strengthening may be established under delegated authority. Moving path anchors along a real rename preserves meaning. Weakening, removing, or contradicting existing governance requires exact authority; `escalation: agent` is not permission to redraw a user-defined envelope.

When one executor introduces an explicitly authorized contract and its implementation, they may land atomically together. When independent consumers need the contract, land the contract-setting unit first.

## Durable decisions and exceptions

Record a decision only when it would materially change future behavior, cannot be adequately enforced, could be re-derived incorrectly, must survive the current goal, is cheaper to carry than rediscover, and has inspectable authority.

Exceptions require an accepted requirement, temporary substitute, authority, and inspectable exit. Never store progress, commands, results, acknowledgements, plans, or ordinary implementation choices.

For concurrent candidates only, read
[references/reconciliation.md](references/reconciliation.md) before recording the accepted result.
