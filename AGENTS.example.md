# git-intent — agent instructions to copy

Append this block to the repository's always-loaded agent instructions.

```markdown
## Intent workflow

Begin with read-only `intent-brief`, then create `intent/work/<uuid>` before the first repository
mutation and finish through `intent-land merge`. Use a linked worktree when useful; leases remain
specific to coordinated work. `intent-land direct` is only for the first commit on an unborn
integration branch. A clean branch may be reused for the same goal only when its prior landing is
still the integration head; fast-forward it to that head first. Otherwise create a fresh branch.

Missing governance is an observed posture, not a blocker or initialization trigger. Infer semantic
domains from the goal, behavior, and architecture; never equate directories with domains.

Accepted governance lives in `.intent/`: domains name semantic responsibilities, contracts protect
executable promises between domains, and constraints preserve architectural shape with optional
checks. Tracked audits and observations are non-authoritative evidence and do not enter governing
digests. Architecture material stays in repository-native ADRs, diagrams, schemas, and design docs,
referenced directly by governing records.

Use `intent-coordinate` only for genuinely parallel, independently owned, or handoff-sensitive
work. Its ignored `.intent/runtime/` plan and leases are shared across linked worktrees. Validate
dependency order, provides/relies edges, checks, and unordered path/interface/governance claims.
Expiry schedules liveness inspection; Git ancestry and causal facts determine state.

At briefing and again before landing, ask whether a future change could be locally reasonable but
systemically wrong without preserving a decision introduced or changed here. This includes durable
responsibilities, relied-on interfaces or formats, authoritative-state ownership, persistence,
transaction, failure, recovery, migration, compatibility, rollout, and architectural restrictions.
Change size and directory shape do not answer the question. Preserve the answer at landing as
`no-record`, a fresh conclusive scoped audit, or accepted governance references.

Use `intent-audit scope` when that durable meaning is uncertain or discovery is explicitly requested;
clear authority may flow directly to `intent-record`. A full audit requires an explicit
repository-wide request. Audit writes causal, tracked, non-authoritative evidence. Accepted findings
flow to `intent-record`, which updates defining material and the smallest existing or new domains,
contracts, or constraints before re-briefing. Missing verification is `VERIFIER REQUIRED`, never a
reason to omit a required contract.

Configuration is version 1. `resolution: assisted | auto` selects who resolves consequential
semantic ambiguity. `integration_branch` is optional; otherwise capture the current branch at
intake. No configuration authorizes external effects.

Use `intent-land` to build and inspect the exact prospective tree. Treat new mechanical topology as
a boundary-review signal, not inferred governance. Require the boundary disposition, review every
affected semantic constraint, run all affected verifiers and repository checks, authenticate
coordinated leases, validate trailers, and only then compare-and-swap the integration ref. Failure
leaves the target unchanged. Push, deploy, publication, destructive cleanup, and other external
effects require explicit request authority.
```
