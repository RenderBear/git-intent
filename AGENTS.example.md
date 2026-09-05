# Invariant — managed agent workflow

`invariant init` installs this block in the repository's selected agent instruction files. It is
included here as a portable reference for other harnesses.

```markdown
## Invariant lifecycle

If `invariant init` left its configuration and instruction files uncommitted, commit that one-time
bootstrap before beginning the first managed task.

Use the `invariant` CLI for every repository mutation. Do not invoke Invariant's internal scripts
or reproduce its branch, receipt, verification, or landing mechanics yourself.

Before the first mutation, interpret the requested outcome and select any relevant semantic
domains. If the durable-meaning boundary is already grounded, include it; otherwise let it remain
unresolved until candidate review. Then run:

`invariant --format json task begin <task-id> --goal <text> [--boundary <no-record|recorded|unresolved|audit:id>] [--path <path>]... [--interface <name>]... [--domain <id>]...`

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

For a full audit, investigate the repository without interrupting the human for code-level details,
then present one consolidated semantic proposal. The audit itself is read-only. `resolution`
controls approval of its adoption; `execution` controls the branch, verification, and landing of
the approved repository changes.

When repository work exposes a potential discovery, assemble its paths, searched scope, evidence,
and relevance without asking the human for code-level details. Under `resolution: assisted`, the
first capture or resolution attempt returns an approval proposal without mutating tracked state.
Present the human with the observation and the decision it needs—not the internal fields—and rerun
the same transition with `--apply` only after approval. Under `resolution: auto`, proceed when the
request and accepted authority are sufficient.

`resolution: assisted | auto` controls who resolves semantic ambiguity. `execution: auto | assisted`
controls lifecycle pauses; both preserve the same stages and checks. Neither setting authorizes
deployment, artifact publication, destructive cleanup, or other external effects.

Remote Git publication is a separate repository policy. It defaults to `push_remote: off`. When the
accepted configuration and the verified candidate both keep it `on`, a successful landing pushes
the exact landed commit only to the integration branch's existing upstream. Never choose or
configure an upstream automatically, and never run `git push` outside Invariant's landing flow. If
the remote rejects the update, preserve and report the completed local landing.

Repositories may independently enable `lifecycle.intent_expansion` and
`lifecycle.outcome_review`. Expansion adds stable task-local outcome, acceptance, and constraint IDs
before implementation. Outcome review assesses those IDs against the exact prospective tree. When
disabled, neither bookend is required; the durable-intent lifecycle remains unchanged.
```
