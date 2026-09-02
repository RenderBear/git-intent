# git-intent — agent instructions to copy

Append this block to the repository's always-loaded agent instructions.

```markdown
## Intent workflow

Treat git-intent as two separate layers: sparse durable governance in `.intent/`, and
ephemeral coordination in the visible, ignored `intent-work/` workspace. Missing governance
is an observed posture, not a blocker and not a reason to create more ceremony.

Run `intent-brief` at goal intake, material scope expansion, and landing. Compile only the
matching routes, contracts, decisions, checks, and live claims. Its digest covers governing
content, not worker availability or operational configuration. `REACH` measures semantic
governance: local, bounded, open, or gated. Boundary count and unrouted spread never increase
reach. Work proceeds directly unless live execution has a useful concurrent, independently
owned, or handoff-sensitive frontier.

Use `intent-coordinate` only for that frontier. It writes an ephemeral statusless workboard
and mints one lease per dispatched worker, carrying the integration target captured at intake.
Create branches and worktrees just in time. Unclaimed entries may be redrawn; leased or landed
claims are pinned. Derive state from dependencies, leases, ancestry, and `Intent-Unit`
trailers. Use runtime status to inspect the workspace. Cleanup is dry-run by default and retains
live leases and incomplete boards; landing releases completed runtime state automatically.

Use `intent-audit scope` when explicitly requested or when current work creates or changes a
critical durable boundary. A full repository audit requires an explicit human request and may
then run autonomously or with human assistance. Audit is always read-only. It discovers candidate
routes and contracts from inspectable evidence, never from filenames or historical behavior
alone. Most boundaries remain unrouted or route-only.

Use `intent-record` as the only writer of tracked intent. Record only an accepted candidate or a
complete direct user instruction. A contract requires a durable relied-on assertion, identified
surfaces, accepted authority, and executable verification.

Configuration is version 1. `escalation: human | agent` determines who resolves a
consequential semantic ambiguity; agent resolution stays within already accepted intent.
`integration_branch` is optional; otherwise capture the current branch at intake. A
configured branch must exist unless it is the current unborn branch before the first landing.
No configuration authorizes external effects.

Use `intent-land` for completion. It constructs and validates the prospective commit, runs
affected contract verifiers and repository checks against that exact tree, validates scope
trailers, and only then compare-and-swaps the integration ref. A failed preflight leaves the
target unchanged. Pass `--allow-open` only after authority for an open or breaking boundary
has been resolved. Push, deploy, publish, destructive cleanup, and other external mutations
require explicit request authority.

The normal path is `brief → implement → land`. Adoption never reopens a completed landing,
and coordination never becomes durable governance.
```
