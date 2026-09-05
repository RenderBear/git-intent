# Invariant CLI basics

Invariant is normally driven by a coding agent or harness. Humans can initialize a repository,
inspect its status, and change configuration without learning the full agent protocol.

## What is a task ID?

A task ID is a caller-chosen, repository-local name for one managed change. It connects the task's
goal, disposable receipt, generated work branch, verification, and final landing.

Use a short descriptive value such as `fix-job-recovery` or `PROJ-142`. It must begin with a letter
or number and may contain letters, numbers, `.`, `_`, and `-`. The same ID is passed to each command
for that task. It is not a Git commit or filename, and it does not need to match an external issue
unless that convention is useful to the repository.

For example, in this command `fix-job-recovery` is the task ID:

```bash
invariant task begin fix-job-recovery --goal "Restore active jobs after restart"
```

## Commands a human may use

Initialize the current repository:

```bash
invariant init
```

See repository health and active task IDs:

```bash
invariant status
```

Inspect one active task:

```bash
invariant status fix-job-recovery
```

Inspect the effective configuration:

```bash
invariant config show
```

With `execution: assisted`, Invariant may ask for an explicit local lifecycle continuation:

```bash
invariant task continue fix-job-recovery --apply
```

The coding agent should explain the proposed branch or landing action before asking a human to run
or approve that command.

## A typical agent-managed change

The following is an illustrative sequence. A coding agent or harness usually supplies the detailed
scope and runs these commands.

```bash
# Open the managed task and work branch.
invariant --format json task begin fix-job-recovery \
  --goal "Restore active jobs after restart" \
  --path src/jobs.py

# After implementation is committed, generate the candidate-bound assessment.
invariant --format json task assessment prepare fix-job-recovery

# After completing any reported semantic decisions, verify and land the task.
invariant --format json task finish fix-job-recovery
```

`task assessment prepare` stores its editable draft in Git-local runtime rather than the repository
worktree. `task finish` uses that draft by default. A failed finish preserves the task receipt and
work branch so the same task ID can be inspected and resumed.

## Initial governance

Initial governance is one resumable session with distinct audit, adoption, and verification phases:

```bash
invariant initial-governance begin initial-governance
invariant initial-governance audit-save initial-governance baseline --input findings.yml
```

With agent authority, the agent continues through ready findings without a routine approval stop.
With human authority, it summarizes the saved audit and offers deeper investigation, adoption of
all ready findings, adoption of selected findings, or deferral.

```bash
invariant initial-governance adopt initial-governance --all-ready
invariant initial-governance adopt initial-governance --finding recovery-ownership
invariant initial-governance defer initial-governance
```

## Agent and harness interfaces

The remaining command groups are primarily integration surfaces:

| Group | Purpose |
|---|---|
| `task` | Manage the fixed brief, branch, assessment, verification, and landing lifecycle. |
| `initial-governance` | Coordinate the first audit and adoption through that lifecycle. |
| `context` | Retrieve affected domains, architecture, contracts, reach, and digests. |
| `evidence` | Frame and save audits or capture progressive discoveries. |
| `coordinate` | Manage temporary plans and causal leases for concurrent work. |
| `candidate` | Expose exact-candidate verification and landing mechanics. |
| `state` | Validate tracked Invariant configuration, governance, and evidence. |

Use `--help` at any level for command syntax. Audit and assessment inputs are self-describing:

```bash
invariant evidence audit schema
invariant evidence audit example
invariant task assessment schema
invariant task assessment example
```

For automation, `--format json` emits the compact protocol envelope. Add `--verbose` only when the
full human-readable rendering is also needed.
