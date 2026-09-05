## Agent protocol reference

### Locator namespaces

Use locator namespaces consistently. Validation does not convert one semantic object into another.

| Concept | Accepted form |
|---|---|
| Authority source | `user:task:<id>#<turn>`, `user:url:https://...`, `design:task:<id>`, `design:url:https://...`, `architecture:repo:<path>#<anchor>`, or `design:repo:<path>#<anchor>` |
| Architecture reference | `architecture:<markdown-path>#<heading-slug>` |
| Governance reference | `domain:<id>`, `contract:<id>`, `constraint:<id>`, or an exact registered architecture reference |
| Surface | `repo:<path>` or `interface:<name>` |
| Evidence | `repo:<path>`, `commit:<ref>`, `interface:<name>`, `task:<id>`, or `url:https://...` |
| Verifier | `command:<executable-path>`, `test:<test-path>`, `schema:<schema-path>`, or `runner:<name>#<target>` |
| Final boundary disposition | `no-record`, `recorded`, or `audit:<id>` |

A domain or contract may use only an architecture reference whose Markdown file and heading exist
in the candidate. A governance architecture reference must already be registered by a candidate
domain or contract. `unresolved` is a valid boundary disposition only while work is active.

Named verifier runners declare their command, working directory, timeout, and cache policy under
`verification.runners` in `.invariant/config.yml`. Python tests automatically use the nearest
tracked `uv.lock` and `pyproject.toml` when present.

### Meaning and standing

Reach is derived from candidate paths, selected domains and interfaces, and accepted governance; it
is not an authority claim. A discovery or audit is evidence, not a governance reference.

During initial governance, begin without nonexistent domains and select newly created domains in
the final recorded assessment. Invariant accepts them when the candidate establishes those domain
records.

### Prepare structured inputs

Before writing an audit, load `invariant evidence audit schema`. Before finishing a task, run
`invariant task assessment prepare <task-id>` and consult `invariant task assessment schema` when
needed.

Prefer compact JSON for automation. Consume the complete `required`, `inferred`, and `will_run`
payload in one pass rather than probing the protocol one validation error at a time.
