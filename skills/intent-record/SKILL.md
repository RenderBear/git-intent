---
name: intent-record
description: Author or revise accepted domain responsibilities, architecture decisions, and executable cross-domain contracts when authority is explicit.
---

# Intent record

Use this optional semantic guide only when the request or a resolved finding has authority to change
durable repository intent. It does not own lifecycle or Git mechanics.

Prefer the smallest canonical artifact that already owns the meaning. Architecture Markdown holds
rationale and non-executable decisions. Domains provide stable responsibility and retrieval keys.
Contracts protect relied-on cross-domain promises and require executable verification. Do not create
a contract merely because a discovery exists.

A discovery can close into documentation, code, tests, follow-up work, another discovery, or no
artifact. If it establishes durable meaning, update the architecture/domain/contract and its
disposition together. Keep accepted IDs and Markdown anchors stable unless the change is an explicit
governance migration.

Use `invariant state validate`, context reach, and candidate verification for mechanical checks.
Under assisted resolution, ask one concrete behavior question when authority is genuinely missing;
under automatic resolution, act only within the current request and accepted authority.
