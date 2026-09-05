# Agent protocol reference

Use locator namespaces consistently. Validation does not convert one semantic object into another.

- Authority sources: `user:task:<id>#<turn>`, `user:url:https://...`, `design:task:<id>`,
  `design:url:https://...`, `architecture:repo:<path>#<anchor>`, or
  `design:repo:<path>#<anchor>`.
- Architecture references: `architecture:<markdown-path>#<heading-slug>`. A domain or contract may
  use only an architecture reference whose Markdown file and heading exist in the candidate.
- Governance references: `domain:<id>`, `contract:<id>`, `constraint:<id>`, or an exact architecture
  reference already registered by a candidate domain or contract.
- Surfaces: `repo:<path>` or `interface:<name>`.
- Evidence: `repo:<path>`, `commit:<ref>`, `interface:<name>`, `task:<id>`, or `url:https://...`.
- Verifiers: `command:<executable-path>`, `test:<test-path>`, `schema:<schema-path>`, or
  `runner:<name>#<target>`. Named runners declare their command, working directory, timeout, and
  cache policy under `verification.runners` in `.invariant/config.yml`. Python tests automatically
  use the nearest tracked `uv.lock` and `pyproject.toml` when present.
- Boundary dispositions: `no-record`, `recorded`, or `audit:<id>` at finish. `unresolved` is valid
  only while work is active.

Reach is derived from candidate paths, selected domains and interfaces, and accepted governance; it
is not an authority claim. A discovery or audit is evidence, not a governance reference. During
initial governance, begin without nonexistent domains and select newly created domains in the final
recorded assessment; Invariant accepts them when the candidate establishes those domain records.

Before writing an audit, load `invariant evidence audit schema`. Before finishing a task, run
`invariant task assessment prepare <task-id>` and consult `task assessment schema` when needed.
Prefer compact JSON for automation and consume the complete `required`, `inferred`, and `will_run`
payload in one pass.
