---
name: cli-design
description: Design or refine Invariant's terminal interface, including interactive setup, human-facing lifecycle controls, summaries, color, and machine-readable output.
---

# Invariant CLI design

Design the CLI as the visible edge of a repository-native control plane for coding agents. Humans
should provide goals, choose repository policy, approve semantic decisions, and optionally control
lifecycle transitions; they should not need to understand paths, evidence locators, assessment
files, receipts, or Git plumbing.

## Separate the two surfaces

- Human-facing commands use plain language, explain consequences before requesting input, and end
  with a compact outcome or next action.
- Agent-facing commands expose deterministic detail through `--format json`. Do not dilute that
  contract to make raw mechanics friendlier for manual entry.
- Never imply that running `invariant` starts or connects to a model. The coding agent owns the
  conversation and investigation; Invariant owns repository context and lifecycle mechanics.

## Interaction hierarchy

- Lead with the `◈ INVARIANT` wordmark and the line `Durable intent for agentic work` on setup flows.
- Group one decision at a time under a short title. State the effect as a question, give named
  choices, explain each in one line, and visibly mark the recommended default.
- Name controls by what the human is deciding: `Semantic decisions`, `Git lifecycle`, `Integration
  branch`, and `Remote publication`. Keep implementation terminology out of these labels.
- Present intent expansion and outcome review as one `Intent shaping` choice: model-led by default,
  optional custom pre-step, optional custom post-step, or both.
- After setup, show selected values as a compact aligned summary. Do not dump the configuration
  document or internal resolution fields into normal text output.
- Recommend a full audit as a copyable natural-language request. The agent should investigate
  without interruption and return one consolidated semantic proposal.

## Color and accessibility

- Use magenta for the wordmark, cyan for structure and prompts, green for selected or successful
  states, and yellow for attention or recommended next actions.
- Keep color supportive rather than essential: symbols, labels, and wording must carry the same
  meaning with ANSI removed.
- Emit ANSI only when stdout is a terminal. Honor `NO_COLOR` for every human-facing path.
- Keep piped output stable and readable. JSON output never contains ANSI or decorative prose.

## Product boundaries

- `resolution` controls semantic authority. `execution` controls mechanical Git pauses. Present
  them as independent choices and never suggest that automatic execution bypasses approval.
- A full audit is read-only. Adoption may require semantic approval; approved repository changes
  then use the configured branch, verification, and landing lifecycle.
- Remote publication is independent, explicit repository policy. Local success and remote push are
  never presented as the same operation.

## Verification

Exercise interactive defaults, non-default selections, redirected text output, `NO_COLOR`, and JSON
output. Verify behavior and state changes, not exact marketing prose or ANSI byte sequences.
