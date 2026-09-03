---
name: intent-brief
description: Compile the smallest applicable domain, contract, constraint, and live-claim context before repository work or landing. Use at intake and when scope or governing content changes; ordinary ungoverned work still uses an isolated work branch but needs no governance adoption.
---

# intent-brief

Compile a read-only working envelope. Domains are semantic clusters inferred from the request,
code, and referenced material; never infer domain membership mechanically from a directory.

## Compile

1. Identify the requested outcomes and intended paths or interfaces.
2. Select only semantic domains that materially apply. For an ordinary local edit, selecting no
   domain is correct.
3. Run `scripts/resolve-config.sh` once and retain the integration target. Use
   `scripts/brief-support.sh reach --paths ... [--domain <id>]...` at intake.
4. Read `rows <domain...>` and retain `digest <domain...>` when domains apply. Audits and
   observations are evidence and never enter this digest.
5. Apply the durable-meaning test below. Adopt only meaning future work must preserve; use a scoped
   audit when the answer is uncertain.
6. Before the first repository mutation, create `intent/work/<uuid>` from the captured integration
   head. Use `intent-coordinate` only when useful independent work requires it.

Posture is:

- `local` — no accepted binding record intersects;
- `bounded` — accepted contracts or constraints apply;
- `open` — defining material, verification, or additive governance changes;
- `gated` — accepted governance is removed or rewritten.

Contracts supply executable verification. Constraints always require semantic compliance review
and may additionally supply commands. `resolution: assisted` asks only for a consequential
unresolved meaning; routine compliance remains agent work. Read
[references/intent-interview.md](references/intent-interview.md) only for such a resolution.

## Durable meaning and work isolation

Ask whether a future change could be locally reasonable but systemically wrong unless it knew and
preserved a decision introduced or changed by this work. A positive answer includes a stable new
responsibility; a relied-on interface, schema, wire, configuration, or storage promise; authoritative
state ownership; persistence, transaction, failure, recovery, migration, rollout, or compatibility
behavior; or an architectural restriction. Size and directory layout do not decide it.

Use `no-record` when all durable promises and operational properties remain unchanged. Use a fresh
scoped audit when discovery is needed. When authority and meaning are already explicit, proceed to
`intent-record` without manufacturing an audit. Missing contract verification is a blocker to
adoption, not a reason to omit the contract.

Branch creation is independent of this result. Every mutation uses a generated work branch and
normal landing uses merge. Direct landing is reserved for an unborn integration branch. Reuse a
clean branch only for the same active goal, when its previous landing is still the integration head,
and fast-forward it to that head before editing; otherwise create a fresh UUID branch.

## Lifetime and landing

A brief remains usable until its domain-governance digest changes or its semantic scope expands.
Use `observe <digest> <domain...>` for freshness. Git supplies causal order; no timestamp decides
freshness.

Before landing, recompute reach from the exact diff, review every emitted constraint against the
prospective tree, collect affected verifiers, and pass scopes, domains, checks, and reviewed
constraint ids to `intent-land`. Also pass exactly one boundary disposition: `no-record`,
`audit:<id>`, or `recorded` with each owning governance reference supplied through `--governance`.

Use [references/intent-review.md](references/intent-review.md) only when an independent semantic
review is useful.
