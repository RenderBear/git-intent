---
name: intent-record
description: Adopt, amend, or retire accepted domains, cross-domain contracts, and architectural constraints together with their defining material. Use after an audit finding or a complete direct instruction has authority.
---

# intent-record

Record is the governance promotion transaction. It consumes the current accepted audit finding by
default; use an audit id or finding id only when resuming or selecting part of a larger audit.

```text
intent-record adopt
intent-record adopt --audit <id>
intent-record adopt --audit <id> --finding <id>
intent-record amend
intent-record retire
```

## Write protocol

1. Recheck the audit's causal freshness when one is used.
2. Resolve authority according to `resolution: assisted | auto` and the request's hard limits.
3. Create or update the canonical ADR, architecture document, diagram, or specification when the
   accepted meaning is not already explicit.
4. Change only the smallest domain, contract, or constraint records that bind that meaning.
5. Run `../intent-brief/scripts/validate-state.sh`, every affected contract verifier, and any
   constraint verifier that exists.
6. Recompile the brief before dependent units diverge. Leave changes unstaged unless the invoking
   task owns landing.

Domains are semantic responsibility clusters. Do not add filesystem membership merely to make
them mechanically discoverable. A contract is a relied-on promise between at least two domains
and requires executable evidence. A constraint is a binding permitted-shape assertion over one or
more domains; executable verification is optional because compliance may be semantic.

ADRs hold rationale. There is no separate decision record: a binding consequence becomes a domain,
contract, or constraint; a nonbinding durable fact becomes an observation. Critical material is
referenced on the governing record rather than configured as a global documentation folder.

Prefer amending the record that already owns a responsibility or promise. Create a new record only
when the durable meaning cannot be expressed coherently by an existing one. Record operational
meaning rather than incidental technology: for example, authoritative durable state, restart
survival, transactionality, recovery, or migration compatibility rather than merely "uses
PostgreSQL."

For incompatible concurrent governance edits, read
[references/reconciliation.md](references/reconciliation.md).
