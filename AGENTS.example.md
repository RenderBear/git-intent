# git-intent — agent instructions to copy

Append this block to the repository's always-loaded agent instructions.

```markdown
## Intent workflow

Use the smallest lifecycle: `intent-brief → implement → intent-land`. Missing governance is an
observed posture, not a blocker or initialization trigger. Infer semantic domains from the goal,
behavior, and architecture; never equate directories with domains.

Accepted governance lives in `.intent/`: domains name semantic responsibilities, contracts protect
executable promises between domains, and constraints preserve architectural shape with optional
checks. Tracked audits and observations are non-authoritative evidence and do not enter governing
digests. Architecture material stays in repository-native ADRs, diagrams, schemas, and design docs,
referenced directly by governing records.

Use `intent-coordinate` only for genuinely parallel, independently owned, or handoff-sensitive
work. Its ignored `.intent/runtime/` plan and leases are shared across linked worktrees. Validate
dependency order, provides/relies edges, checks, and unordered path/interface/governance claims.
Expiry schedules liveness inspection; Git ancestry and causal facts determine state.

Use `intent-audit scope` for a consequential touched boundary or an explicit discovery request. A
full audit requires an explicit repository-wide request. Audit writes a causal, tracked,
non-authoritative report and ends with no record, record ready, resolution required, or verifier
required. Accepted findings flow to `intent-record`, which updates defining material and the
smallest domains, contracts, or constraints before re-briefing.

Configuration is version 1. `resolution: assisted | auto` selects who resolves consequential
semantic ambiguity. `integration_branch` is optional; otherwise capture the current branch at
intake. No configuration authorizes external effects.

Use `intent-land` to build and inspect the exact prospective tree. Review every affected semantic
constraint, run all affected verifiers and repository checks, authenticate coordinated leases,
validate trailers, and only then compare-and-swap the integration ref. Failure leaves the target
unchanged. Push, deploy, publication, destructive cleanup, and other external effects require
explicit request authority.
```
