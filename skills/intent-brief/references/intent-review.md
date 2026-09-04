# Independent intent review

Give a reviewer only the unit goal and prospective diff, selected domains, architecture pointers,
contracts, relevant discoveries, and declared checks. Do not attach repository-wide audits,
unrelated discoveries, other leases, or generic history.

Ask the reviewer to challenge:

- whether the selected semantic domains are complete;
- whether every affected cross-domain contract remains satisfied;
- whether the candidate preserves each referenced architecture decision;
- whether a claimed additive change creates compatibility or side effects;
- whether defining material and implementation still agree.

The reviewer returns findings, not governance. Durable accepted changes go through
`intent-record`; implementation corrections remain ordinary work.
