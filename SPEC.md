# git-intent — design of record

git-intent maintains sparse accepted architecture over a Git repository, a separate short-lived
planning plane for live work, and an atomic local convergence boundary. Git remains the causal
clock and source of implementation truth.

## 1. Operating boundary

The system answers:

1. Which semantic domains matter to this request?
2. Which accepted cross-domain promises and architectural constraints apply?
3. Is adoption required before dependent work diverges?
4. Can useful independent units run concurrently without claim collision?
5. Does the exact prospective tree preserve accepted meaning and pass verification?

It does not inventory a repository, persist ordinary reasoning, equate paths with domains, or add
ceremony merely because governance is absent.

Repository mutation and governance adoption are independent decisions. Every mutation is isolated
on a work branch even when it needs no durable governance. Conversely, a very small implementation
change can require adoption when it changes meaning that future work must preserve.

## 2. Planes and standing

| Plane | Objects | Lifetime | Standing |
|---|---|---|---|
| Governance | domains, contracts, constraints, defining material | durable | accepted authority |
| Evidence | audits, observations | durable | observed, non-authoritative |
| Planning | plans, claims, leases | one active context | coordination only |
| Implementation | Git trees and commits | repository history | causal fact |
| Verification | commands and prospective review | one candidate tree | measured evidence |

Governance and planning may reference the same semantic identifiers but never grant each other
authority. Audits and observations can motivate adoption but cannot bind work.

## 3. State

```text
.intent/config.yml
.intent/DOMAINS.yml
.intent/CONTRACTS.yml
.intent/CONSTRAINTS.yml
.intent/audits/<id>.yml
.intent/observations/<id>.yml
.intent/runtime/plans/<id>.yml
.intent/runtime/leases/<unit>.yml
```

Runtime is ignored and anchored in the primary worktree so all linked worktrees see the same live
claims. Deleting it cannot change repository meaning, though it can discard active coordination.

## 4. Configuration

```yaml
version: 1
resolution: assisted
integration_branch: main
```

Both fields after `version` are optional. Absence means `resolution: assisted` and the branch
current at goal intake.

- `assisted` lets the agent plan and implement normally but sends consequential unresolved
  architecture, compatibility, side-effect, or governance changes to the human.
- `auto` lets the agent resolve those choices within the current request and accepted authority.

Neither mode authorizes incompatible explicit goals, security or money effects, production data,
irreversibility, push, deployment, publication, or other external mutations without exact request
authority. Planning policy, worker availability, and documentation roots are runtime or repository
facts, not configuration.

## 5. Addressing and domains

Every ordinary path has a mechanically derived coordination scope:

- visible top-level directories become `area.<slug>`;
- declared package roots may add `pkg.<slug>`;
- root files and hidden top-level paths belong to `area.root`;
- `.intent/` is outside implementation scope claims.

Derived scopes organize claims and validate commit trailers. They carry no semantics or authority.

There is no tracked route record. Routing is the brief-time operation that selects semantic
domains and mechanically intersects declared surfaces. A separate pointer layer would repeat
governance without adding authority.

A domain is a coherent cluster of responsibility, behavior, and change. It need not be a service,
directory, bounded context, or public interface. Domain selection is semantic model work based on
the request, implementation, observations, and architecture material.

```yaml
version: 1
domains:
  - id: ocr.orchestrator
    description: Selects OCR engines and distributes work.
    authority: user:task:ocr-architecture#turn-4
    parent: ocr
    material: [architecture:docs/architecture.md#ocr-orchestration]
```

Validation checks identifiers, authority and material locators, parent references, and cycles. It
never tries to prove domain membership from paths.

## 6. Contracts

A contract is an accepted durable promise on which another semantic domain relies.

```yaml
version: 1
contracts:
  - id: ocr.engine-protocol.v1
    assertion: Every engine accepts OcrRequest and returns OcrResult.
    authority: user:task:ocr-architecture#turn-4
    between: [ocr.orchestrator, ocr.engine.external]
    surfaces: [interface:OcrEngine, repo:schemas/ocr-engine.json]
    material: [architecture:docs/architecture.md#ocr-engine-protocol]
    verifies: [command:scripts/verify-ocr-engine-protocol]
```

Admission requires accepted authority, at least two domains, identifiable surfaces, defining
material, real reliance, and executable verification. API, event, job, schema, and configuration
contracts use the same shape; their verifier owns format-specific mechanics.

## 7. Constraints

A constraint is an accepted assertion about permitted architecture or behavior within one or more
domains.

```yaml
version: 1
constraints:
  - id: ocr.provider-isolation
    assertion: Provider-specific behavior remains inside its engine domain.
    authority: user:task:ocr-architecture#turn-4
    applies_to: [ocr.orchestrator, ocr.engine.external]
    surfaces: [repo:src/ocr]
    material: [architecture:docs/architecture.md#ocr-engine-isolation]
    verifies: [command:scripts/check-ocr-dependencies]
```

`surfaces` and `verifies` are optional. Constraint applicability and compliance may be semantic.
When a constraint applies, landing requires an explicit prospective-tree review acknowledgement and
runs its verifier when present. Assisted resolution asks only when compliance is ambiguous or the
accepted constraint would change.

ADRs contain rationale. There is no separate decision object: binding consequences become domains,
contracts, or constraints; nonbinding durable facts become observations; Git retains superseded
content.

## 8. Material, audits, and observations

Architecture material may live anywhere in the repository. Governing records reference exact ADRs,
diagrams, specifications, schemas, or sections. A global docs folder is neither configured nor
assumed.

An audit is a tracked report over a declared commit and exact tree. It contains scope, evidence,
bounded findings, and whether record, authority, verifier work, or no action follows. Audit is
non-authoritative even though it is committed.

```yaml
version: 1
id: audit-2026-09-02-ocr
ground: 8a3e7d2
tree: e1c52f0
mode: scope
domains: [ocr.orchestrator, ocr.engine.external]
paths: [src/ocr, schemas/ocr.json]
findings:
  - id: engine-boundary
    summary: Both engines already depend on a shared request and result shape.
    evidence: [repo:schemas/ocr.json, interface:OcrEngine]
    proposed: contract
    disposition: adoptable
    authority: user:task:ocr-architecture#turn-4
```

`proposed` is `domain`, `contract`, `constraint`, `observation`, or `none`. `disposition` is
`adoptable`, `needs-authority`, `needs-verifier`, `observation-only`, or `no-action`. Finding ids
are stable handles within the audit; adoption may name one when several findings exist, but the
normal in-context flow is simply `intent-record adopt`.

An observation is a tracked fact relevant to a semantic boundary but not binding. It records a
statement, evidence, related governance identifiers, and a ground commit. Audit and observation
freshness derives from ancestry and intersecting evidence changes. Neither enters governing digests
or gates landing.

```yaml
version: 1
id: ocr-provider-layout
ground: 8a3e7d2
statement: Provider implementations currently live below src/ocr/providers.
evidence: [repo:src/ocr/providers]
relates_to: [domain:ocr.engine.external]
```

## 9. Adoption

Adoption is promotion, not seeding or inventory.

At briefing and again against the prospective tree, ask:

> Could a future change be locally reasonable but systemically wrong unless it knew and preserved
> this decision?

The answer is yes when current work creates or changes a responsibility that needs stable identity;
a relied-on interface, schema, wire, configuration, or storage promise; the owner of authoritative
state; persistence, transaction, consistency, failure, recovery, or migration behavior; rollout or
compatibility ordering; or an architectural restriction on future implementations. Change size and
path layout do not decide this question.

Behavior-preserving implementation substitutions, local refactors, tests, documentation, and
one-consumer details need no new record when every existing promise and operational property remains
unchanged. When durable meaning already has an accepted owner, amend the existing record rather than
creating a parallel one.

```text
brief current work
  → durable-meaning test is negative: record no-record disposition, implement, and land
  → durable meaning and authority are explicit: record minimal governance, re-brief, implement
  → durable meaning is uncertain: scoped audit
      → no record needed: record audit disposition, implement, and land
      → authority or verifier missing: resolve bounded issue before dependent work diverges
      → accepted: record material plus minimal governance, re-brief, implement
```

`intent-audit` writes tracked evidence. `intent-record` is the only writer of accepted domains,
contracts, constraints, and their defining material. A full audit requires an explicit human
request and uses `--assisted` or `--auto` only after that authorization.

Choose the artifact from the meaning, not the technology: a domain gives a responsibility stable
identity; a contract protects an executable promise relied on by another domain; a constraint binds
permitted architecture or operational behavior; an observation preserves a relevant nonbinding
fact; and an ADR or other defining material holds rationale. A missing contract verifier is a
`VERIFIER REQUIRED` result, not permission to silently omit the contract.

## 10. Briefing

A brief selects semantic domains, then compiles their domains, contracts, constraints, and live
claims. Contracts may also be reached mechanically through declared surfaces. Constraints with
declared surfaces can be found mechanically, but domain selection remains semantic.

Reach is:

- `local` — no accepted binding record intersects;
- `bounded` — applicable accepted records remain unchanged;
- `open` — defining material, verification, or additive governance changes;
- `gated` — accepted governance is removed or rewritten.

The digest covers only selected domain, contract, and constraint content. Configuration, audits,
observations, worker availability, Git ancestry, and runtime never enter it.

## 11. Work branches, parallel planning, and leases

After read-only briefing and before the first repository mutation, create a generated work branch
from the captured integration head. The normal namespace is `intent/work/<uuid>`; names carry no
semantic authority, so feature-versus-fix classification is unnecessary. Governance, documentation,
fixes, refactors, and features all follow the same rule. A linked worktree is recommended for keeping
the integration worktree clean but is not required for an uncoordinated unit. A lease remains specific
to coordinated work.

An uncoordinated work branch may be reused only for the same active goal when its prior landing is
still the integration head and the branch worktree is clean. Fast-forward the branch to that landing
before the next edit. If another integration commit intervened, or the goal changed, start a fresh
branch from the current integration head. This is causal continuity, not UI-session identity.

One prompt may contain several outcomes. The model decomposes them into units; tooling validates:

- an existing captured target and causal integration ground;
- selected semantic domains and their exact governing digest;
- an acyclic dependency graph;
- meaningful verification for every unit;
- provider-before-consumer `provides` and `relies_on` edges;
- disjoint unordered path, interface, and governance claims.

Sharing a domain does not by itself cause a collision. Plans contain no progress fields. Landed
state derives from first-parent `Intent-Unit` trailers, active from leases, and readiness from the
dependency graph.

A lease records unit, owner, branch, worktree, task, paths, interfaces, claimed governance,
selected domains, governing digest, integration target and ground, causal tip, and expiry. Landings
that intersect path, interface, or governance claims make it stale. Expiry only schedules a
liveness check; ancestry, ref/worktree existence, and tip movement determine dead, renewing, or
quiescent state.

## 12. Prospective landing

Landing captures the integration head, constructs a direct or merge candidate without moving the
target, and checks it out detached. Against that exact tree it:

1. recomputes semantic reach from actual paths and selected domains;
2. reports newly introduced mechanical topology as a review signal, never as inferred governance;
3. requires an explicit boundary disposition: `no-record`, a fresh scoped audit that concludes no
   adoption, or accepted governance references;
4. resolves open or gated authority;
5. validates all tracked intent;
6. validates derived scope and semantic domain trailers;
7. runs affected contract and constraint verifiers plus repository checks;
8. requires acknowledgement of every affected semantic constraint review;
9. authenticates coordinated leases and their combined claims;
10. compare-and-swaps the integration ref from the captured head;
11. releases landed leases and removes a completed plan.

Normal landing merges a work branch. Direct landing is permitted only to create the first commit on
an unborn integration branch, where no branch can yet be based on a commit. A naked acknowledgement
is not a boundary disposition: the caller must state that the durable-meaning test was negative,
identify the concluding audit, or name the accepted governance that owns the meaning. Landing
preserves that result in `Intent-Boundary` and `Intent-Governance` commit trailers.

Any failure before the ref update leaves the target unchanged. If another landing wins the race,
compare-and-swap fails rather than overwriting it.

## 13. Mechanical and semantic ownership

Mechanics owns schemas, reference integrity, derived scopes, plan DAGs, reliance order, claim
overlap, causal freshness, governing digests, affected verifier selection, exact-tree construction,
trailer checks, boundary-disposition shape and references, lease authentication, and atomic ref
updates.

Model judgment owns outcome decomposition, domain selection, distinguishing contracts from
constraints, interpreting evidence, authoring accepted assertions and material, reviewing semantic
constraint compliance, the durable-meaning decision, and resolving incompatible meaning under
configured authority.

The governing rule remains: isolate every mutation, then use the smallest governance and
coordination lifecycle that safely completes the request.
