---
name: intent-coordinate
description: Decompose genuinely parallel or handoff-sensitive work into causally ordered, independently verifiable semantic units.
---

# Intent coordinate

Use this optional semantic guide only when at least two units are independently ownable, parallel,
or handoff-sensitive. Several files or sequential implementation steps are not enough.

Define each unit in prose with a concrete objective, dependencies, path/interface/governance
claims, provided and relied-on promises, and executable verification. Order providers before
consumers. Keep shared domain context separate from ownership claims: sharing a semantic domain does
not itself create a collision.

The CLI owns plan validation, runtime placement, leases, freshness, liveness, cleanup, and landing
authentication. Use `invariant coordinate plan validate`, `coordinate status`, and `coordinate lease
...`; do not reproduce those mechanics in prompts or scripts. Plans and leases coordinate active
work but never become architectural authority.
