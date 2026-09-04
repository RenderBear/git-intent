# Scoped discovery

Adoption is demand-driven. Ordinary work stays `brief → implement → land`.

Apply the durable-meaning test: could future work be locally reasonable but systemically wrong
unless it knew and preserved a decision introduced or changed here? Inspect responsibility identity,
relied-on interfaces and formats, authoritative state, persistence and transaction properties,
failure and recovery, migrations, compatibility and rollout order, and restrictions on future
implementation. Diff size and directory shape are not evidence by themselves.

Inspect only intended paths, immediate imports and consumers, named interfaces, stable architecture
material, existing governance, and executable checks. Identify semantic domains from responsibility
and change coupling, not directory shape. Two implementations and their orchestrator may be three
domains even inside one source tree.

Write a tracked audit containing the inspected commit and tree, paths, evidence, contradictions,
and bounded findings. A finding may lead to:

- a domain when a responsibility needs stable identity across sessions;
- a contract when another domain relies on a durable promise and verification exists;
- architecture when rationale or permitted shape must be preserved in an anchored Markdown section;
- a discovery when unresolved evidence is worth carrying into future work;
- code, documentation, tests, or follow-up work when the gap is not governance;
- another discovery when the original question must be split;
- no artifact when evidence is local, accidental, or conclusively resolved in prose.

Prefer amending the accepted artifact that already owns the meaning. Propose a new artifact only
when no coherent existing responsibility, architecture section, or promise can own it. Do not encode a
technology choice such as PostgreSQL when the durable meaning is instead authoritative state,
persistence, transactional behavior, recovery, or migration compatibility.

End by declaring whether record is ready, authority or verifier work is required, or no record is
needed. A fresh repository receives no inventory or bootstrap merely because it is empty.

Queue a discovery only when the evidence cannot be resolved now and will materially help later
work. Give it an observation, exact-tree basis, relevance, and open disposition. Open and causally
suspect discoveries warn by default; they do not govern. Resolution does not imply promotion and
does not require a contract.
