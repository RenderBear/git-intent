# Invariant — agent instructions to copy

Append this block to the repository's always-loaded agent instructions.

```markdown
## Invariant lifecycle

Use the `invariant` CLI for every repository mutation. Do not invoke Invariant's internal scripts
or reproduce its branch, receipt, verification, or landing mechanics yourself.

Before the first mutation, interpret the requested outcome, select any relevant semantic domains,
and decide the current posture and durable-meaning boundary. Then run:

`invariant --format json task begin <task-id> --goal <text> --posture <local|bounded|open|gated> --boundary <no-record|recorded|unresolved|audit:id> [--path <path>]... [--interface <name>]... [--domain <id>]...`

Implement and commit the requested change on the generated branch returned by the command. The CLI
owns the fixed lifecycle and its Git state; the agent owns implementation and semantic judgment.
Use `invariant --format json task status <task-id>` and `task check` to resume existing work.
Use `invariant task guidance <task-id>` when model context has been compacted; it compiles the
free-form brief, discovery, coordination, and landing guidance applicable to the current stage.

Before finishing, review the exact candidate against every applicable architecture decision and
prepare a version-1 assessment containing the returned goal digest, candidate paths, selected
interfaces and domains, one boundary disposition, governance references, architecture review
acknowledgements, and checks. Run:

`invariant --format json task finish <task-id> --assessment <file>`

Finishing recomputes reach, constructs and verifies the exact prospective tree, runs affected
verifiers, compare-and-swaps the local integration ref, restores the integration branch, and cleans
the task receipt and generated branch. A failure leaves the work branch recoverable.

`.invariant/` contains tracked governance and evidence plus ignored coordination runtime. Domains
name semantic responsibilities, not directories. Architecture Markdown is canonical; contracts
are executable cross-domain promises. Audits and discoveries are evidence, never authority. A
discovery records observation, causal basis, relevance, and disposition; it may resolve to
architecture, governance, implementation, documentation, tests, follow-up work, or no artifact.

`resolution: assisted | auto` controls who resolves semantic ambiguity. `execution: auto | assisted`
controls lifecycle pauses; both preserve the same stages and checks. Neither setting authorizes
push, deployment, publication, destructive cleanup, or other external effects.

Repositories may independently enable `lifecycle.intent_expansion` and
`lifecycle.outcome_review`. Expansion adds stable task-local outcome, acceptance, and constraint IDs
before implementation. Outcome review assesses those IDs against the exact prospective tree. When
disabled, neither bookend is required; the durable-intent lifecycle remains unchanged.
```
