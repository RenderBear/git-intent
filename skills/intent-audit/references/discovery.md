# Scoped discovery

Adoption is demand-driven. Ordinary work stays `brief → implement → land`.

Inspect only intended paths, immediate imports and consumers, named interfaces, stable architecture
material, existing governance, and executable checks. Identify semantic domains from responsibility
and change coupling, not directory shape. Two implementations and their orchestrator may be three
domains even inside one source tree.

Write a tracked audit containing the inspected commit and tree, paths, evidence, contradictions,
and bounded findings. A finding may propose:

- a domain when a responsibility needs stable identity across sessions;
- a contract when another domain relies on a durable promise and verification exists;
- a constraint when accepted architecture restricts permitted shape;
- an observation when a relevant fact should persist but is not binding;
- no action when evidence is local or accidental.

End by declaring whether record is ready, authority or verifier work is required, or no record is
needed. A fresh repository receives no inventory or bootstrap merely because it is empty.
