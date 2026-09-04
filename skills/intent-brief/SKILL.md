---
name: intent-brief
description: Interpret a requested change against the smallest applicable durable repository intent and identify unresolved semantic questions.
---

# Intent brief

Use this optional semantic guide to understand a task. The `invariant` CLI owns receipts, branches,
freshness, reach calculation, and lifecycle transitions.

Start from the user's prose and intended behavior. Select semantic domains because their stable
responsibilities apply, never because their names resemble directories. Read only the selected
architecture, contracts, and relevant discoveries. Distinguish repository facts from semantic
judgment and keep ordinary work ordinary.

Apply the durable-meaning test: could future work be locally reasonable but systemically wrong
unless it knew and preserved a decision introduced or changed here? Consider responsibility,
relied-on interfaces and formats, authoritative state, persistence, transactions, failure,
recovery, migration, rollout, compatibility, and architectural restrictions. Size and directory
layout do not answer the question.

Return a compact semantic envelope: goal, applicable durable intent, selected paths/interfaces/
domains, whether durable meaning is unchanged, changed, or uncertain, and the smallest question
that genuinely needs authority. `no-record`, `audit:<id>`, and `recorded` are semantic decisions;
reach does not manufacture them.

Use `invariant task begin|check|status|guidance` and `invariant context ...` for deterministic work.
After context compaction, reload `task guidance`; a fresh receipt proves dependencies but does not
place prose back into model context. Read [references/intent-interview.md](references/intent-interview.md)
only when consequential ambiguity requires a user decision.
