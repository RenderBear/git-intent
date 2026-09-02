---
name: intent-brief
description: Compile a small read-only working envelope from routes, contracts, decisions, live claims, and the requested change. Unrouted work remains directly executable unless it creates a critical durable boundary.
---

# intent-brief

Use at goal intake, material scope expansion, and landing. It never writes tracked intent or
coordination state. Digest compilation may cache a disposable governing snapshot under
`intent-work/observations/` so a later stale brief can explain exactly what changed.

## Compile

1. Infer the narrow intended paths, interfaces, and scopes from the request. Report material inferences.
2. Run `scripts/resolve-config.sh` once and retain its resolved integration target for this goal. Then run `scripts/brief-support.sh reach --paths <paths...>` at intake or `reach <base>` for an implemented diff.
3. Resolve the posture:
   - **governed** — one or more routes or contracts apply;
   - **observed** — no durable contract applies; the request, repository checks, and consequence gate bound this goal;
   - **contract-first** — the goal creates or changes a critical shared boundary that must constrain dependent work.
4. Run `rows <scope...>` and `digest <scope...>`. Emit only rows that affect an outcome, design exclusion, verifier, missing authority, or live scheduling collision.
5. Continue directly by default. `intent-coordinate` activates separately only when execution has a useful concurrent or independently owned frontier.

`REACH` measures semantic governance:

- `local` — no declared contract reliance intersects;
- `bounded` — contract surfaces intersect and their verifiers can measure preservation;
- `open` — defining material or verifier strength changed;
- `gated` — an existing contract record changed breakingly.

Boundary count and unrouted spread are topology facts, never governance escalation.

If no route matches, report `UNROUTED` and use the derived identifiers. Do not initialize the repository, seed routes, or ask a question merely because governance is absent.

## Contract-first trigger

Use contract-first only when the work introduces or materially changes a durable macro goal, public/shared interface, security or data boundary, compatibility promise, external protocol, or a rule that must constrain independent workers.

Invoke `intent-audit scope` for that touched area. After authority resolution, use `intent-record` to establish accepted intent before dependent implementations diverge. Ordinary local work proceeds observed.

## Lifetime

The brief persists until its governing digest changes or the scope materially expands. Use `observe <digest> <scope...>`; operational configuration and worker availability do not enter the digest.

On `STALE`, `observe --explain` identifies changed governance. Re-read self-authored rows and refresh the digest; foreign changes require recompilation.

## Landing handoff

Before landing:

- recompute reach from the actual diff;
- emit affected verifier locators with `verifiers <base>`;
- resolve authority for `open` or `gated` work;
- hand the goal, scopes, units, digest, and any repository checks to `intent-land`.

Only an explicit human request starts `intent-audit full`. The audit owns repository-wide discovery and remains read-only.
