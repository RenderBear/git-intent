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
- Verifiers: `command:<executable-path>`, `test:<test-path>`, or `schema:<schema-path>`. Contract
  verifiers must be executable in the exact candidate tree; use a command wrapper when necessary.
- Boundary dispositions: `no-record`, `recorded`, or `audit:<id>` at finish. `unresolved` is valid
  only while work is active.

Reach is derived from candidate paths, selected domains and interfaces, and accepted governance; it
is not an authority claim. A discovery or audit is evidence, not a governance reference. During
initial governance, begin without nonexistent domains and select newly created domains in the final
recorded assessment; Invariant accepts them when the candidate establishes those domain records.

Before writing an assessment or audit, inspect the relevant command's `--help`. Prefer JSON output
for automation and use every diagnostic record in one pass rather than probing one missing field at
a time.
