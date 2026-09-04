# Audit orientation

In an unfamiliar repository, inspect structure, architecture material, public protocols, check
entrypoints, and recent causal changes. Keep facts tied to repository paths or commits. Do not infer
domains solely from directories.

Prefer `rg --files`, repository manifests, CODEOWNERS, `ARCHITECTURE.md`, ADR indexes, schemas,
diagrams, and CI configuration. Read history only around a concrete boundary. Existing code and
commits establish observed shape and reliance, never accepted meaning.

First inspect counts and likely sources. Open full documents only when a task or finding makes them
relevant. Unresolved evidence worth carrying forward may become a discovery; authoritative
architecture sections and contracts are referenced by domains.
