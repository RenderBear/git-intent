# Invariant: Durable architectural intent for agentic work

Invariant is a repository-native control plane for coding agents and harnesses, delivered as a
standalone Python CLI. It governs durable intent and verified lifecycle transitions without hosting
or executing the model loop. Humans provide intent, resolve escalated conflicts or ambiguity, and
may control lifecycle transitions; agents handle repository internals. Invariant advances the
integration branch only after exact-candidate verification succeeds and keeps remote publication
disabled by default.

It connects four critical axes for agentic work:

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



The complete design is in [SPEC.md](SPEC.md).

## Install

Install Invariant directly from its Git repository:

```bash
uv tool install git+https://github.com/RenderBear/invariant-cli.git
```

Or, from the root of a local checkout:

```bash
uv tool install .
```

Confirm the installation:

```bash
invariant --version
```

## Initialize a repository

From the repository root, run:

```bash
invariant init
```

Interactive setup explains each repository setting before asking for a value. It configures Codex,
Claude Code, or both; writes the selected values to `.invariant/config.yml`; and safely adds a
managed Invariant workflow to the applicable root instruction files without replacing existing
content.

Use every safe default without prompts:

```bash
invariant init --defaults
```

This selects both Codex and Claude Code, agent semantic authority, automatic lifecycle
execution, the current branch as the automatic integration target, local-only landing, and the
optional lifecycle bookends disabled. Initialization does not run a model; after setup it prints a
natural-language request for your coding agent to run the complete initial governance workflow
from saved audit through adoption.

Interactive setup presents the two optional intent controls as one choice. The default is
model-led: it relies on the coding agent's own understanding and normal candidate review. A
repository can instead add a custom pre-step, a custom post-step, or both.

## Use Invariant

Invariant does not contain or connect to a model. Codex, Claude Code, or another coding harness
provides the model, conversation, and tools; Invariant provides the durable repository context and
verified lifecycle that the harness invokes.

| Actor | Responsibility |
|---|---|
| Human | State the goal and acceptance intent, resolve escalated semantic or merge conflicts, and optionally approve lifecycle transitions. |
| Coding agent or harness | Inspect the code, select relevant paths and domains, implement the change, prepare candidate assessments, and invoke Invariant. |
| Invariant CLI | Retrieve durable context, maintain receipts and coordination state, manage isolated Git work, verify the exact candidate, and land it under repository policy. |

The human does not need to inspect repository internals, choose domains or paths, author assessment
files, or manage branches. Those are agent and Invariant responsibilities.

### Use with a coding agent

`invariant init` activates Invariant in the repository's persistent agent instructions. For Codex it
uses `AGENTS.md`; for Claude Code it uses `CLAUDE.md`; when both are selected, Claude imports the
shared workflow from `AGENTS.md`. [AGENTS.example.md](AGENTS.example.md) remains a portable reference
for other coding agents and harnesses.

The user can then ask for a change normally. The coding agent interprets the goal, invokes the
`invariant` commands through its shell, implements and commits on the branch Invariant creates,
prepares the semantic assessment, and asks Invariant to verify and land the result. When Invariant
needs authority or encounters a real conflict, the agent returns to the human with the decision—not
with a request to investigate the code manually. No Invariant-specific model plugin is required.

### CLI surface

The CLI exists so every coding harness, CI job, and IDE can use the same local, model-independent
protocol. Detailed arguments such as paths, domains, interfaces, governance references, and
candidate assessments are integration fields for those callers; they are not concepts a human is
expected to memorize or enter during normal development.

Humans may use the small operational surface directly—for example, `invariant status`,
`invariant status <task-id>`, or `invariant task continue <task-id> --apply`. Harnesses should use
compact `--format json` for the deeper command contract; add `--verbose` only when the duplicate
text rendering is useful. Running `invariant` alone does not start an assistant; without a coding
harness, it remains a deterministic repository and automation tool.

The protocol is self-describing:

```bash
invariant evidence audit schema
invariant evidence audit example
invariant task assessment schema
invariant task assessment example
invariant task assessment prepare <task-id>
```

Assessment preparation derives the exact candidate paths, domains established by the candidate,
governance references, prospective tree, affected architecture reviews, and checks that will run.
It reports unresolved semantic requirements together instead of revealing them one validation error
at a time. The editable draft is stored in Git-local task runtime, so it does not dirty the candidate;
after completing it, `invariant task finish <task-id>` uses that draft by default.

## Configure Invariant

Invariant works without a configuration file.

Its effective defaults are:

```yaml
version: 1
coding_agents: [codex, claude]
authority: agent
execution: auto
integration_branch: auto
push_remote: off
lifecycle:
  intent_expansion: false
  outcome_review: false
```

Settings:

| Setting | Default | Values | What it controls |
|---|---|---|---|
| `version` | `1` | `1` | Configuration schema version. It is fixed and not user-configurable. |
| `coding_agents` | `[codex, claude]` | Any non-empty subset of `codex`, `claude` | Which root agent instruction files receive the managed Invariant workflow during initialization. |
| `authority` | `agent` | `agent`, `human` | Who may define repository-wide semantics, resolve contradictions, and approve durable intent. |
| `execution` | `auto` | `auto`, `assisted` | Whether state-changing lifecycle transitions run immediately or pause for explicit continuation. |
| `integration_branch` | `auto` | `auto`, local branch name | The branch that receives verified landings. `auto` uses the current branch when a task begins; a name fixes one local convergence target. |
| `push_remote` | `off` | `off`, `on` | Whether a successful landing stays local or pushes the exact verified commit to the integration branch's existing upstream. |
| `lifecycle.intent_expansion` | `false` | `false`, `true` | Intent expansion before implementation: make outcomes, acceptance criteria, and constraints explicit. Set with `off` or `on` through the CLI. |
| `lifecycle.outcome_review` | `false` | `false`, `true` | Outcome review before landing: assess the goal or expanded outcomes against the exact candidate. Set with `off` or `on` through the CLI. |

All selections live in `.invariant/config.yml`. Edit that tracked file directly or inspect and update
validated settings through the CLI:

```bash
invariant config show
invariant config set coding_agents codex,claude
invariant config set authority human
invariant config set execution assisted
invariant config set integration_branch auto
invariant config set integration_branch main
invariant config set push_remote on
invariant config set lifecycle.intent_expansion on
```

### Configure project-aware verification

Python `test:` locators use the nearest `pyproject.toml` and tracked `uv.lock` automatically. More
complex repositories can register named runners:

```yaml
verification:
  runners:
    backend:
      command: [uv, run, pytest, "{target}"]
      cwd: backend
      cache: exact-tree
      timeout: 300
```

A verifier such as `runner:backend#tests/test_contract.py` then executes in `backend`. Successful
output is retained under Git-local Invariant runtime and omitted from normal responses. Exact-tree
receipts let `task finish` reuse a matching prior candidate verification; reach, state validation,
the prospective tree, and the integration compare-and-swap are still recomputed live. Set a runner's
cache to `exact-tree` only when that reuse is sound; named runners default to `never`.

## Establish architectural intent

Invariant does not require a complete model up front: start with an initial governance run, then let
normal work deepen it progressively.

### Run initial governance (recommended)

Ask your coding agent to run Invariant's initial governance workflow. The agent investigates
responsibilities, boundaries, dependencies, and executable promises and saves the completed audit
under `.invariant/audits/`. With `authority: agent`, it continues automatically through adoption and
managed landing. With `authority: human`, it presents a concise findings summary and lets the human
investigate further, adopt all ready findings, adopt selected findings, or defer. `execution`
independently controls branch and landing pauses. The agent-facing audit handoff is explicit. Invariant stamps the exact Git  ground, tree, and UTC creation time, validates the findings, and persists a timestamped audit.

### Continue with progressive discovery

During normal work, the agent inspects outward from the goal and surfaces missing, contradictory, or
outdated intent. With human authority, the human decides whether each finding should be preserved
or resolved; with agent authority, accepted repository policy allows the agent to proceed within
its granted scope. Unresolved discoveries remain evidence, while accepted resolutions can
update architecture, contracts, code, tests, or no artifact at all.

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
