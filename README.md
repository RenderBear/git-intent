# Invariant

Invariant discovers and maintains durable architectural intent across long-running agentic work.

It connects four concerns that otherwise drift apart:

- **Governed autonomy** — stable architecture and executable contracts let agents act independently
  without weakening cross-domain promises.
- **Guided coordination** — temporary plans, dependencies, and ownership claims steer concurrent
  work through critical domains without becoming architecture.
- **Progressive or intensive discovery** — repositories can learn incrementally as work exposes
  missing context, or through a deliberate upfront audit. Findings remain evidence until resolved.
- **Git-grounded lifecycle** — isolated work, exact-candidate verification, and atomic local landing
  keep long-running changes stable and resumable.

Durable intent is the semantic counterpart to temporal coordination: architecture and contracts
remain after the work ends; plans, claims, and leases do not.

![A Git-grounded lifecycle carries a user goal through coordination, execution, verification, conflict resolution by an agent or human, and local landing. A durable semantic layer maps domains to architecture files and contracts to contract files and checks.](.github/assets/lifecycle.svg)

Invariant is a standalone Python CLI. Codex, another coding agent, CI, or a person can invoke the
same local command contract. It verifies the exact candidate that will be integrated, advances the
local integration branch only on success, and never pushes.

The complete design is in [SPEC.md](SPEC.md).

## Install

Install Invariant as an isolated command:

```bash
uv tool install invariant-cli
```

Or install it into a Python environment:

```bash
python -m pip install invariant-cli
```

Confirm the installation:

```bash
invariant --version
```

## Develop with Invariant

Ask Codex or another coding agent to use Invariant for a repository change. The agent identifies the
relevant paths and any existing domains, reads applicable architecture and contracts, works on an
isolated branch, verifies the resulting candidate, and lands it locally when every requirement
passes.

```text
You:
Add retry recovery to document processing. Use Invariant.

Codex:
1. Opens the task against the relevant paths and any applicable domains.
2. Reads the architecture, contracts, and discoveries that could affect the change.
3. Implements and commits the change on an isolated work branch.
4. Reviews the exact candidate and runs affected checks.
5. Lands the change locally when every requirement passes.
```

Codex does not need a custom integration or plugin. A consuming repository can copy
[AGENTS.example.md](AGENTS.example.md) into its always-loaded agent instructions to make this the
default development workflow.

## A complete task

Start with the user-visible goal and the paths currently known to be relevant:

```bash
invariant task begin retry-recovery \
  --goal "Recover interrupted document-processing jobs" \
```

Before finishing, describe the candidate in an assessment:

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

Then finish the task:

```bash
invariant task finish retry-recovery --assessment /tmp/retry-recovery.yml
```

Invariant reconstructs the prospective integration tree, recomputes its architectural reach, runs
the affected checks and reviews against that exact tree, and atomically advances the local
integration branch. If review or verification fails, the integration branch is untouched and the
work branch remains recoverable.

For applications and agent harnesses, add `--format json` to receive structured output.

## Optional intent clarification

Most tasks can begin from the user's prose. When a request needs sharper task-level agreement,
Invariant can preserve an expanded intent document containing outcomes, acceptance criteria, and
constraints before implementation. An optional outcome review then evaluates those acceptance IDs
against the exact candidate tree.

```yaml
version: 1
goal: Recover active jobs when the application restarts.
outcomes:
  - id: O1
    prose: Non-terminal jobs are visible after restart.
acceptance:
  - id: A1
    prose: Each non-terminal job is restored exactly once.
constraints:
  - id: C1
    prose: Session-only events are not restored.
```

Pass the document to `task begin --intent <file>`. Enable outcome review with
`--outcome-review`. Expanded task intent guides one change; it is not permanent repository
architecture.

## Discover an existing repository

Invariant does not require a complete architecture model up front. It supports two ways to learn an
existing codebase.

### Progressive by default

Begin with real work and inspect outward only while new evidence could change the implementation,
architectural judgment, or verification. This is the normal mode for feature work, maintenance,
unfamiliar code paths, and gradual adoption.

When work exposes an implicit decision, contradiction, undocumented dependency, or meaningful
absence, capture it as a discovery:

```bash
invariant evidence discovery capture missing-recovery-record \
  --observation "No document explains ownership after process restart." \
  --searched docs \
  --searched src/jobs \
  --path src/jobs
```

A discovery is evidence, not authority. Invariant does not automatically rewrite architecture from
a finding. Resolution can guide the smallest appropriate change to an existing domain,
architecture section, contract, implementation, test, documentation, follow-up task, or no artifact
at all. Only a normally reviewed, verified, and landed change becomes durable repository intent.

### Optional full audit

A full audit is an explicit broader investigation of the repository or a selected subsystem. It is
useful when introducing Invariant to an established repository, preparing a large migration, or
examining unclear ownership and risky integration boundaries.

```bash
invariant evidence audit full
```

An audit records what was inspected and what was found. Like a progressive discovery, it does not
manufacture architecture; its findings remain evidence until intentionally resolved.

## Files and terms

Invariant adds only the state a repository needs:

```text
your-repository/
├── .invariant/
│   ├── config.yml        optional repository configuration
│   ├── DOMAINS.yml       stable responsibilities and architecture pointers
│   ├── CONTRACTS.yml     executable promises between responsibilities
│   ├── discoveries/      non-authoritative evidence from ongoing work
│   └── audits/           non-authoritative broader investigations
└── docs/
    └── architecture.md   ordinary Markdown remains the source of truth
```

- **Domain:** a stable area of responsibility, not necessarily a directory.
- **Architecture:** Markdown that preserves ownership, rationale, state, failure behavior, and
  important restrictions.
- **Contract:** a promise one responsibility relies on from another, connected to executable
  verification.
- **Discovery:** non-authoritative evidence about something missing, contradictory, or not yet
  understood.
- **Audit:** a causally grounded record of what was inspected and found.
- **Task intent:** optional outcomes and acceptance criteria for one local change.
- **Coordination:** temporary dependencies and ownership while parallel work is active.

The short form is:

```text
request
  → retrieve relevant architecture, contracts, and discoveries
  → investigate, coordinate, and implement
  → review architectural impact and run affected checks
  → converge safely

uncertainty
  → discovery evidence
  → intentional resolution
  → architecture, contract, code, tests, documentation, follow-up, or no action
```

## Contributing to Invariant

Set up the source tree:

```bash
uv sync
uv run invariant --version
```

Run the complete verification suite:

```bash
for test_file in tests/test-*.sh; do sh "$test_file" || exit; done
uv run pytest
uv build --no-sources
```

The package implementation lives under `src/invariant/`. Repository-local `intent-*` shell scripts
are deprecated compatibility adapters into that package and are not included in the installed
wheel.
