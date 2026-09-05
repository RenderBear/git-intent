# Invariant

Invariant preserves accepted architectural meaning while people and agents change a Git repository.
It is a standalone Python CLI: Codex, another agent, CI, or a person can invoke the same local
command contract.

- **Semantics** carries prose judgment: requested meaning, relevant domains, discoveries, and
  architecture review.
- **Mechanics** derives exact repository facts: reach, digests, freshness, candidate trees, checks,
  and compare-and-swap ref updates.
- **Lifecycle** keeps the fixed brief → isolate → implement → verify → land flow resumable.

![A read-only brief leads to an isolated work branch, an exact candidate tree, and verification against that tree before a compare-and-swap advances the integration ref. Tracked governance sits inside Git and feeds both the brief and verification; the ignored planning runtime sits outside it.](.github/assets/lifecycle.svg)

The complete design is in [SPEC.md](SPEC.md).

## Install

For development:

```bash
uv sync
uv run invariant --version
```

Install the repository as an isolated command:

```bash
uv tool install .
```

Or install it into a Python environment:

```bash
python -m pip install .
```

After publication, the corresponding package command is `uv tool install invariant-cli`. The
distribution is named `invariant-cli`; the executable and import package are both named
`invariant`.

The repository also keeps `bin/invariant` as a source-tree launcher. Repository-local `intent-*`
shell scripts are deprecated compatibility adapters into the Python package; they are not included
in the installed wheel and no longer own mechanics.

## Use from Codex or a shell

Codex does not need a custom integration or an additional skill. Agent instructions can tell it to
invoke the CLI, use normal editing tools on the returned work branch, and provide semantic decisions
when requested. Applications should select JSON output:

```bash
invariant --format json task begin retry-handling \
  --goal "Add retry handling to document processing" \
  --posture local \
  --boundary no-record \
  --path src/processing
```

Humans may use the same command with text output. `task begin` creates a disposable Git-local
receipt and enters a generated `intent/work/...` branch. After committing the implementation,
prepare an assessment:

```yaml
version: 1
goal_digest: <digest returned by task begin>
paths: [src/processing]
interfaces: []
domains: []
boundary:
  disposition: no-record
governance: []
architecture_reviews: []
checks: []
```

Then finish the fixed lifecycle:

```bash
invariant task finish retry-handling --assessment /tmp/retry-handling.yml
```

Invariant reconstructs the prospective integration tree, recomputes reach, performs required
semantic gates, runs checks against that tree, atomically advances the local integration ref, and
cleans the completed task. It never pushes.

## Optional semantic bookends

The core lifecycle always preserves durable repository intent. Two optional flags add task-specific
precision before and after it without changing the middle:

```yaml
version: 1
resolution: assisted
execution: auto
integration_branch: main
lifecycle:
  intent_expansion: false
  outcome_review: false
```

- `intent_expansion` requires a versioned prose record with stable outcome, acceptance, and
  constraint IDs before implementation. Pass it to `task begin --intent <file>`.
- `outcome_review` requires the finish assessment to map those acceptance IDs to `satisfied`,
  `not-satisfied`, or `unresolved` against the exact candidate tree.

Both default off. They are semantic bookends, not replacements for briefing, durable-meaning
review, verification, or landing. Run `invariant task guidance <task-id>` to compile the free-form
brief, semantic-reasoning, repository-archaeology, discovery, coordination, and landing guidance
relevant to the current stage.

The compiled context deliberately keeps prose first-class. Stable IDs, paths, and domains are
retrieval coordinates; they do not replace interpretation. For the active task, the CLI includes
the full expanded intent when enabled, the exact selected architecture sections from the task's
accepted integration ground, and the observation and causal basis of relevant discoveries. The
reasoning guide then asks the host to distinguish requested meaning, accepted meaning, and observed
behavior; trace responsibility, reliance, state, time, and failure; triangulate code, tests,
schemas, configuration, documentation, history, and operations; and preserve contradictions or
meaningful absences as explicit discoveries.

This restores depth without coupling semantics to the lifecycle. Context selection and exact-tree
retrieval are deterministic mechanics. Interpretation remains free-form prose, and the lifecycle
only decides when that compiled context is presented.

## Progressive discovery

A discovery records an observation, its causal basis, its relevance, and its disposition:

```yaml
version: 1
id: missing-recovery-record
observation: No document explains ownership after process restart.
basis:
  ground: <commit>
  tree: <tree>
  searched: [docs, src/jobs]
  prose: Repository-wide search found behavior but no decision record.
relevance:
  domains: [jobs]
  paths: [src/jobs]
  related: [task:document-recovery]
disposition:
  state: open
```

Discoveries are evidence, never authority. A resolved discovery can point to a domain, contract,
architecture section, another discovery, a repository path, or follow-up task—or close with prose
and no new artifact. Missing ADRs, absent documentation, contradictions, implicit dependencies, and
meaningful absences are therefore representable without pretending every finding is a contract.

```bash
invariant evidence discovery capture missing-recovery-record \
  --observation "No document explains ownership after restart." \
  --searched docs --searched src/jobs --domain jobs

invariant evidence discovery resolve missing-recovery-record \
  --prose "Documentation work is tracked separately." \
  --output task:document-recovery
```

## Repository and package layout

```text
src/invariant/
  semantics/        prose models, discoveries, and stage guidance
  mechanics/        deterministic Git, state, cache, audit, and landing operations
  lifecycle/        fixed task state machine
  cli/              argument and output adapters

.invariant/
  config.yml        optional repository configuration
  DOMAINS.yml       accepted responsibilities and architecture/contract pointers
  CONTRACTS.yml     accepted executable cross-domain promises
  discoveries/      tracked non-authoritative discovery evidence
  audits/            tracked non-authoritative audit evidence
  runtime/           ignored active plans and leases
```

Architecture prose remains canonical in anchored Markdown. Receipts live under
`<git-common-dir>/invariant/briefs/`; they cache integrity and semantic scope but hold no authority.
An unrelated mergeable integration advance can refresh a receipt. Changed selected governance,
expanded scope, changed brief-dependency mechanics, or a conflict invalidates the affected reuse.
Edits to stage guidance, landing, coordination, or output formatting do not evict the semantic
envelope; those concerns reload or recompute independently. Candidate verification always binds to
the exact tree being landed.

## Development

```bash
for test_file in tests/test-*.sh; do sh "$test_file" || exit; done
uv run pytest
uv build
```

Copy [AGENTS.example.md](AGENTS.example.md) into a consuming repository's always-loaded agent
instructions to bind Codex or another coding agent to the lifecycle.
