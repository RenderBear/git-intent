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

![A Git-grounded lifecycle carries a user goal through coordination, execution, verification, conflict resolution by an agent or human, and local landing. A durable semantic layer maps domains to architecture files and contracts to contract files.](.github/assets/lifecycle.svg)

Invariant is a standalone Python CLI. Any coding agent, CI job, IDE, harness, or person can invoke
the same local command contract. It advances the local integration branch only after exact-candidate
verification succeeds and keeps remote publication disabled by default.

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

## Configure Invariant

Invariant works without a configuration file. 

Its effective defaults are:

```yaml
version: 1
resolution: assisted
execution: auto
integration_branch: <current branch>
push_remote: off
lifecycle:
  intent_expansion: false
  outcome_review: false
```

Settings:

| Setting | Default | Values | What it controls |
|---|---|---|---|
| `version` | `1` | `1` | Configuration schema version. It is fixed, not a runtime setting. |
| `resolution` | `assisted` | `assisted`, `auto` | Whether consequential semantic ambiguity needs a human or may be settled by an agent acting within accepted authority. |
| `execution` | `auto` | `auto`, `assisted` | Whether state-changing lifecycle transitions run immediately or pause for explicit continuation. |
| `integration_branch` | current branch | local branch name | The branch that receives verified landings. `config init` persists the current branch name. |
| `push_remote` | `off` | `off`, `on` | Whether a successful landing stays local or pushes the exact verified commit to the integration branch's existing upstream. |
| `lifecycle.intent_expansion` | `false` | `false`, `true` | Whether work pauses for explicit outcomes, acceptance criteria, and constraints before implementation. Set with `off` or `on` through the CLI. |
| `lifecycle.outcome_review` | `false` | `false`, `true` | Whether those outcomes must be assessed against the exact candidate before landing. Set with `off` or `on` through the CLI. |

Inspect the resolved values, persist them, or update one setting at a time:

```bash
invariant config show
invariant config init
invariant config set execution assisted
invariant config set integration_branch main
invariant config set push_remote on
invariant config set lifecycle.intent_expansion on
```

`push_remote` is a separate publication policy. It defaults to `off`. When accepted configuration
sets it to `on`, a successful landing pushes the exact verified commit only to the integration
branch's existing Git upstream; Invariant never chooses or configures a remote. A missing upstream
blocks before local landing. If the remote rejects a push after landing, the verified local commit
is retained and reported. Enabling takes effect only after that configuration reaches the
integration branch, while disabling takes effect on the candidate that disables it.

The generated `.invariant/config.yml` is tracked repository policy. Review and commit updates
through the same managed workflow as other repository changes.

## Use Invariant

Invariant is not a coding agent and does not connect to a model. Running `invariant` does not start
an interactive assistant: the executable is a deterministic repository tool that a person, script,
CI job, or coding agent invokes. The caller supplies semantic decisions and implementation;
Invariant supplies context retrieval, lifecycle state, exact-candidate verification, and Git
landing mechanics. Use `invariant --help` to inspect its command surface.

| Usage | Who reasons and implements | Who invokes Invariant | Model connection |
|---|---|---|---|
| Coding agent or harness | The agent, with human input when needed | The agent or harness invokes CLI commands | Supplied by the coding harness, not Invariant |
| Direct shell or automation | A person or purpose-built script | The person, script, or CI job invokes CLI commands | None |

### Through a coding agent or harness

Activate Invariant once in the repository's persistent agent instructions. The portable policy
block in [AGENTS.example.md](AGENTS.example.md) can live in `AGENTS.md` for Codex, `CLAUDE.md` for
Claude Code, or the equivalent instruction surface for another coding agent or harness. To share one
copy between Codex and Claude Code, keep it in `AGENTS.md` and add `@AGENTS.md` to `CLAUDE.md`.

The user can then ask for a change normally. The coding agent interprets the goal, invokes the
`invariant` commands through its shell, implements and commits on the branch Invariant creates,
prepares the semantic assessment, and asks Invariant to verify and land the result. No model is
embedded in the CLI, and no Invariant-specific model integration or plugin is required.

### Directly from the shell

A person or script can drive the same lifecycle without a model. In this mode, the caller performs
the interpretation, implementation, and review that a coding agent would otherwise perform.

Begin a task with the goal and currently known scope:

```bash
invariant task begin retry-recovery \
  --goal "Recover interrupted document-processing jobs" \
  --posture local \
  --boundary no-record \
  --path src/processing
```

Invariant creates and checks out an isolated work branch. Make and commit the change there, then
write the assessment consumed by verification:

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

Finish the task with that file:

```bash
invariant task finish retry-recovery --assessment /tmp/retry-recovery.yml
```

Invariant reconstructs the prospective integration tree, recomputes architectural reach, runs the
applicable reviews and checks, and atomically lands the verified candidate. The direct CLI is
therefore useful for human-operated workflows and automation, but it does not replace the coding
agent itself.

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
