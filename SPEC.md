# git-intent — an intent layer for agentic work

git-intent adds an intent layer to agentic work over Git. It maintains a sparse governed layer
over a repository and a separate ephemeral coordination layer for live work. The system routes a
goal to accepted authority, lets agents work freely inside that envelope, prevents concurrent
writers from colliding, and verifies the exact prospective tree before advancing an integration
ref.

Git remains the source of truth for implementation, causal order, and landed state.

## 1. Design boundary

The system answers five questions:

1. What accepted direction or architecture applies to this goal?
2. Which critical semantic promises must survive?
3. Is this goal governed, merely observed, or contract-first?
4. Does live execution need coordination between independent owners?
5. Can the prospective tree land without violating governance, claims, or verification?

It does not store task memory, progress, command logs, test output, generic reasoning, or a
repository inventory.

The core rule is:

> Governance is sparse and authoritative. Coordination is temporary and opportunistic. Missing
> governance reduces guarantees; it never increases ceremony.

## 2. Layers and authority

| Layer | Artifacts | Lifetime | Standing |
|---|---|---|---|
| Governed intent | routes, contracts, decisions, exceptions | durable | accepted authority |
| Routing | stable scope and matcher pointers | durable | no authority of its own |
| Coordination | workboards, claims, leases | one execution window | scheduling only |
| Implementation | Git trees and commits | repository history | observed fact |
| Verification | commands and content-hash receipts | one prospective tree | measured evidence |

Routes and coordination share semantic identifiers, but durable route rows never point at
ephemeral files. A resolver joins a scope to any currently live claims at runtime.

## 3. State

Tracked intent state:

```text
.intent/config.yml                       optional authority and target resolution
.intent/ROUTES.yml                       sparse governed routing overlay
.intent/CONTRACTS.yml                    accepted critical contracts
.intent/decisions/<scope-root>/<id>.yml  rare active durable choices
.intent/exceptions/<unit>.yml            accepted temporary underdelivery
.intent/proposals/<unit>/<id>.yml        genuinely concurrent unresolved candidates
.intent/history/<scope-root>.yml         cold superseded records
```

Ephemeral state in the primary worktree's visible, ignored `intent-work/` directory:

```text
intent-work/boards/<id>.yml       temporary objectives, dependencies, and claims
intent-work/leases/<unit>.yml     live ownership reservations
intent-work/observations/<digest> governing-content snapshots
intent-work/receipts/<tree>/<id>  successful verification receipts
```

The primary worktree is derived from `git worktree list`; every linked worktree therefore shares
one visible runtime location. The directory self-ignores and is never committed. Deleting it
cannot change repository meaning, though deleting live leases or incomplete boards discards
active coordination.

## 4. Configuration

Configuration remains schema version 1:

```yaml
version: 1
escalation: human
integration_branch: main
```

Both fields after `version` are optional.

### 4.1 Escalation

`escalation` chooses the resolver of a consequential semantic ambiguity:

- `human` — a human resolves critical missing authority or incompatible governing direction.
- `agent` — the agent may exercise delegated judgment within already accepted intent.

Agent resolution may choose a reversible, verifiable implementation, establish unambiguous
additive governance from the current request, and compose compatible constraints. It may not
silently weaken a user-defined contract, choose between incompatible authoritative domain goals,
or authorize security, permissions, money, production data, irreversible effects, or external
mutations. Those require exact request authority in every mode.

Escalation is not question timing. A harness with no available human naturally holds a required
question. The resolution is later admitted or rejected for durable capture by `intent-record`;
capture does not decide who had authority to resolve it.

Absence defaults to `human`.

### 4.2 Integration target

When `integration_branch` is present, it must name an existing local branch or the current
unborn branch before the first commit. When absent, the
branch current at goal intake becomes the target. The resolved name and head are captured once
and carried through workboards and leases; a worker's feature branch must never become the
integration target merely because it is current in that worktree.

Detached HEAD without an explicit target is an error. A configured but missing branch is an
error rather than a silent fallback.

Worker availability, maximum concurrency, question timing, adoption preference, push authority,
and mechanical latitude are not tracked configuration.

Operational configuration does not enter the governing digest. Changing a target ref changes
the tree against which landing recompiles and verifies; it does not change contract meaning.

## 5. Address space

One dotted namespace joins routes, contracts, trailers, workboard units, and leases.

### 5.1 Derived boundaries

The derived map is a pure function of the Git tree:

- top-level visible directories become `area.<slug>`;
- declared package roots may become `pkg.<slug>`;
- root files and top-level hidden directories belong to `area.root`;
- a hidden file inside a visible directory inherits that directory boundary;
- canonical test directories attach to the code boundary they exercise;
- `.intent/` is outside the address space.

Derived identifiers make all work addressable, including work in repositories with no intent
state. They organize and coordinate but carry no semantic authority.

### 5.2 Governed routes

`.intent/ROUTES.yml` is a sparse overlay:

```yaml
version: 1
routes:
  - scope: payments.checkout
    paths: [services/payments]
    interfaces: [CheckoutAPI]
    domain: [user:task:checkout-direction#turn-4]
    architecture: [architecture:repo:docs/architecture.md#checkout]
    contracts: [contract:payments.checkout-api]
    owners: [codeowners:.github/CODEOWNERS#payments]
```

A route requires a path or interface matcher and at least one governing pointer. Paths identify
stable boundary anchors, not every implementation file. Planned paths are allowed before
implementation when the current goal owns them; they must exist at landing.

Routes point to accepted authority. They never manufacture it.

## 6. Contracts

A contract is an authorized durable assertion on which another component, actor, or workflow
relies:

```yaml
version: 1
contracts:
  - id: payments.checkout-api
    assertion: A payment key produces at most one captured payment.
    authority: user:task:checkout-direction#turn-4
    scope: payments.checkout
    surfaces: [repo:services/payments, repo:schemas/checkout.json]
    material: [architecture:docs/architecture.md#checkout]
    verifies: [command:scripts/verify-checkout-contract]
```

Admission requires all of:

- a durable normative promise;
- real reliance beyond a one-off implementation;
- accepted behavior would change if the assertion changed;
- inspectable authority;
- identifiable affected surfaces;
- meaningful executable evidence.

Prefer `command:<repo-relative-executable>` verifiers. `test:` and `schema:` locators remain
valid when atomic landing can execute them directly; otherwise provide a command wrapper.
`contract:<id>` may compose contracts but must ultimately resolve to executable evidence.

A route does not imply a contract. Lacking reliance, the item is documentation. Lacking
authority, it is a candidate. Lacking executable verification, it is a governing direction or
verifier-authoring task, not an active operational contract.

Contract record changes classify mechanically:

- **extension** — purely additive contract, surface, material, or verifier;
- **move** — path anchors follow the diff's real rename map without semantic change;
- **breaking** — an assertion, authority, surface, verifier, or compatibility promise is
  weakened, removed, or rewritten.

Extensions and moves may proceed with suitable delegated authority and green verification.
Breaking changes require exact authority after foreign reliance exists.

## 7. Adoption

Seeding is promotion, not inventory. The derived boundary map makes every ordinary path
addressable without tracked state. Adoption promotes only selected boundaries into durable routes
or contracts.

### 7.1 Fresh repository algorithm

```text
brief first goal
  → explicit intent setup or critical shared boundary needed now?
      → no: work observed; implement and land
      → yes: capture the smallest user charter
          → intent-audit scope on planned touch areas
          → propose routes and verifiable contracts
          → resolve authority
          → intent-record accepted rows
          → validate and atomically land intent
          → recompile brief
          → implement
```

The charter may name macro goals and non-goals, planned critical interfaces or protocols, and
communication or integration constraints. It is not a speculative repository taxonomy. A blank
repository does not trigger seeding merely because it is blank. The first intent landing may also
be the repository's root commit.

### 7.2 Mature repository algorithm

```text
brief current goal
  → route found: use accepted intent
  → no route: observed by default
      → touched boundary is critical or recurrent?
          → no: implement and land
          → yes: intent-audit scope on touched area and immediate reliance
              → propose minimal candidates
              → resolve authority
              → governing now? intent-record before dependent work
              → advisory only? suggest after landing
```

Existing code, tests, documents, and history supply evidence. They do not grant authority or make
accidental behavior normative. Repository-wide adoption requires an explicit request and proceeds
in bounded batches.

### 7.3 Audit and discovery

`intent-audit` is the only discovery path and never writes tracked intent. A scoped audit may
activate when current work becomes contract-first. It examines only:

- the intended touch paths;
- their immediate imports and consumers;
- schemas and public interfaces;
- existing executable checks;
- stable architecture documents, ADRs, or accepted specifications;
- the derived top-level boundary map.

It proposes a stable scope, minimal anchors, governing sources, critical assertions, consumers,
and verifier commands.

A full repository audit requires an explicit request from the human. Missing coverage,
recurrence, or agent judgment may recommend one but cannot start it. After authorization,
`--autonomous` completes bounded batches without interruption and leaves unresolved authority as
questions; `--assisted` asks only when clarification would materially change a candidate. Both
modes are read-only, inspect a declared snapshot, and avoid route-coverage scoring.

### 7.4 Establishment

With `escalation: human`, a human accepts, edits, or rejects one bounded batch. With
`escalation: agent`, the agent may accept only unambiguous additive governance supported by the
current request or an already accepted source.

Accepted rows are written through `intent-record`, mechanically validated, and their new
verifiers executed. The brief is then recompiled.

`intent-record` is the sole tracked-state writer. It accepts resolved audit candidates or a
complete direct user instruction; it never discovers or grants authority.

For one executor, an explicitly authorized new contract and its first implementation may share
one atomic landing. When independent consumers must rely on the contract, the contract-setting
unit lands before they diverge.

### 7.5 Scope of adoption

A fresh repository starts from user goals and planned critical boundaries, not an empty
filesystem inventory. A mature repository defaults to touched-area adoption. A missing verifier
produces a route or verifier-authoring task, not an active operational contract.

Existing code and history are evidence of structure and reliance, never normative authority.

Recurrence across completed landings may produce a post-landing adoption suggestion. It never
blocks, reopens, or amends the completed landing.

## 8. Brief compilation

A brief is read-only and contains the smallest governing context that changes execution.

Inputs are the goal and intended paths, interfaces, and scopes. The compiler reads matching
routes, referenced contracts, active decisions, and intersecting live leases.

Posture:

- **governed** — applicable routes or contracts exist;
- **observed** — no durable contract applies; the request and repository evidence bound this
  goal;
- **contract-first** — a critical durable boundary must be established before dependent work.

Reach is semantic:

- `local` — no contract reliance intersects;
- `bounded` — contract surfaces intersect and verifiers can measure preservation;
- `open` — defining material or verifier strength changed;
- `gated` — an existing contract record changed breakingly.

Boundary count, derived spread, worker availability, and execution complexity do not increase
reach. They may inform optional coordination after briefing.

The digest is content identity over matched routes, contracts, and active decisions. It excludes
operational configuration and Git ancestry. A brief stays valid until that content changes or
scope materially expands.

## 9. Coordination

Coordination activates only for:

- two or more independently verifiable units that can execute concurrently;
- independently owned claims;
- one contract-setting unit followed by several consumers;
- a handoff or interruption requiring resumable ownership.

Multiple paths, directories, scopes, or sequential steps are insufficient.

### 9.1 Workboard

A workboard contains an id, goal, captured integration target, and units with objectives,
dependencies, claims, relied-on contracts, and verification. It contains no progress fields.

Unclaimed entries are fluid. A leased or landed unit is pinned. Status is derived:

- landed from first-parent `Intent-Unit` trailers;
- active from a live lease;
- waiting or dispatchable from dependency edges.

Unordered units require disjoint claims. The model proposes topology; tooling validates
references, overlap, and pinning.

### 9.2 Leases

A lease is minted just in time for every dispatched worker and records its owner, branch,
worktree, task, path/interface claim, captured integration target and ground, causal tip, and
expiry.

A landing that intersects the claim makes the lease stale. The holder releases and reacquires it
against the new ground. Expiry only schedules a liveness check:

- merged branch, or branch and worktree gone → dead;
- tip advanced → renew;
- expired and unmoved → quiescent; reaping ends the reservation, not the work.

Leases are a local substrate shared across linked worktrees.

### 9.3 Runtime lifecycle

Runtime status lists boards with derived unit state, lease lifecycle, and disposable cache counts.
Cleanup reports before mutating. Applied cleanup removes only completed boards, dead or quiescent
leases, governing snapshots, and verification receipts; live leases and incomplete boards remain.
Atomic landing releases each landed lease and removes a board once all of its units have landed.

## 10. Consequence resolution

Proceed autonomously when work is reversible, governing contracts are known or the goal is
honestly observed, authoritative directions compose, relevant verification can run before
landing, and external effects are absent or explicitly authorized.

Implementation uncertainty triggers investigation or a narrower experiment, not a human
question.

A consequential resolution packet identifies the conflicting properties, their authority,
irreversible or underdelivered consequence, concrete options, and one recommendation. The
resolver is selected by `escalation`, subject to the hard gates in §4.1.

After resolution, `intent-record` captures the answer only if it is durable, non-testable,
likely to be re-derived incorrectly, needed beyond the current goal, cheaper to carry, and
backed by inspectable authority. Most implementation choices correctly remain uncaptured.

## 11. Atomic landing

Landing verifies a prospective tree before advancing the integration ref.

For a direct unit:

1. Capture the integration head.
2. Build a temporary index from that head.
3. Apply only the explicitly selected working paths.
4. Write a tree and dangling candidate commit with tool-generated trailers.

On an unborn current branch, the temporary index begins from the empty tree and the candidate is
a root commit. No bootstrap commit or branch is created.

For a coordinated branch:

1. Capture the integration head.
2. Use Git's merge-tree machinery to construct the prospective merge tree.
3. Create a dangling two-parent candidate commit.

For either shape:

1. Check out the candidate in a detached temporary worktree.
2. Recompute reach from its exact diff.
3. Resolve authority for open or gated transitions.
4. Validate the complete intent state.
5. Validate every changed path against its `Intent-Scope` claims. Dotfiles inherit their
   parent boundary; `.intent/` requires no scope claim.
6. Execute all affected contract verifiers and repository checks.
7. Cache successful receipts by candidate tree and check identity.
8. Compare-and-swap the integration ref from the captured old head to the candidate.
9. Update the integration worktree, release landed leases, and remove a completed workboard.

Any failure before step 8 leaves the integration ref unchanged. If another landing advances the
target during verification, compare-and-swap fails rather than overwriting it.

A landed unit carries:

```text
Intent-Unit: <id>
Intent-Scope: <scope>
```

A coordinated convergence may also carry:

```text
Intent-Board: <id>
Intent-Board-Digest: <content identity>
```

The trailers provide binding and coordination closure, not proof that an agent read prose.

A verified feature branch is ready, not landed. Local landing is part of an implementation
request. Push, deploy, publication, destructive cleanup, and other external mutations require
explicit request authority.

## 12. Validation

Mechanical validation owns:

- configuration schema and branch existence;
- route shape, pointer resolution, and anchor limits;
- contract authority, surface, material, and verifier shape;
- decision and exception schemas;
- derived boundary and dotfile classification;
- record extension/move/breaking classification;
- workboard dependency and overlap invariants;
- lease freshness and liveness;
- message generation and trailer containment;
- prospective-tree construction and atomic ref updates.

Model judgment owns:

- interpreting the requested outcome;
- distinguishing descriptive evidence from accepted authority;
- deciding whether a boundary deserves durable governance;
- proposing useful concurrent units;
- composing architectural and domain constraints;
- classifying a failed verifier as a bug or intended transition;
- explaining a consequential unresolved choice.

Scripts report facts and enforce invariants. They do not invent normative meaning.

## 13. Design rules

- Normal work reads many intent rows and writes none.
- Unrouted work remains executable.
- Governance and coordination never activate one another.
- One coherent outcome lands once.
- Plans are the fluid unclaimed region of a workboard, not a durable artifact.
- Leases reserve live ownership, not semantic authority.
- Contracts are few, critical, accepted, and executable.
- Operational configuration never changes governance freshness.
- The integration ref moves only after the exact prospective tree passes verification.
- Adoption is separate from completion unless the current request explicitly establishes the
  contract being implemented.
- The smallest useful lifecycle is always preferred: brief, work, land.
