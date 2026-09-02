# Conflict resolution — compose, never pick a side

Resolve merge, rebase, cherry-pick, or revert conflicts by composing both sides against
routed domain direction, architectural constraints, semantic contracts, and accepted
exceptions. Never select a side merely because Git labels it `ours` or `theirs`.

Require `git ls-files -u` to be non-empty. Identify the operation before naming sides:
rebase stage roles differ from merge, cherry-pick, and revert.

## Resolve

1. Read base, stage 2, and stage 3 for each conflict.
2. Compile `intent-brief` for the conflicted unit and paths. Use matching routes and active
   decisions, not the full state. Read the exact unit exception file only for landing.
3. Read proposal files from each ref only when the conflict actually involves concurrent
   intent.
4. Inspect merge attributes and generated/binary policy; a policy introduced by the same
   change it exempts is not automatically trusted.
5. Classify:

   - adjacent: preserve both;
   - overlapping-compatible: compose both properties;
   - structural: replay behavior at its new location;
   - contradictory: apply the consequence gate after composition and same-domain
     resolution.

6. Resolve against routed schemas, types, APIs, and contract tests, composing domain
   direction with architectural constraints. When composition needs the history of a
   boundary, read the intent log — `git log --first-parent -- .intent/` — rather than
   commit messages or code archaeology.
7. Run commands defined by the repository and report results at runtime. Confirm no active
   exception is hidden or falsely discharged.

Path overlap alone is never contradictory. Implementation uncertainty invites reversible
experimentation, not escalation. For a consequential non-composable conflict, follow
`../../intent-brief/references/intent-interview.md`; the configured resolver acts subject to
the hard authority gates.

Default behavior proposes content and the correct continuation command without writing.
Write and stage only conflicted files, and only when no semantic contradiction remains,
every affected contract passes, and current authorization permits the operation. Never
commit, push, switch unrelated worktrees, or stage unrelated files.

If the resolution creates a durable non-testable decision, use direct capture
(`intent-record`) unless the decision itself is concurrent. Record accepted temporary
underdelivery in the unit exception file; never create a read receipt or implementation
report.
