# CLAUDE.md

## Repository purpose

git-intent implements an intent layer for agentic work over Git. Durable semantic governance
lives in `.intent/`; ephemeral workboards, leases, observations, and verification receipts live
in the visible, ignored `intent-work/` workspace of the primary worktree.

Read [SPEC.md](SPEC.md) for the design of record.

## Core invariants

- Missing governance is an observed posture, never a blocker or planning trigger.
- Routes are sparse pointers and carry no authority of their own.
- Contracts are accepted durable assertions with executable verification.
- Derived boundaries address all ordinary repository paths. Nested dotfiles inherit their
  parent; root dotfiles and hidden top-level directories belong to `area.root`; `.intent/`
  is excluded.
- Reach measures semantic governance only. Runtime concurrency does not change it.
- Coordination activates only for genuinely concurrent, independently owned, or
  handoff-sensitive work.
- Workboards and leases are ephemeral and statusless; causal facts derive their state.
- Governing digests exclude operational configuration.
- Landing validates the exact prospective commit before a compare-and-swap update of the
  integration ref.
- Failed landing never moves the target ref.
- Push and other external effects require explicit request authority.

## Write ownership

| Component | Writes |
|---|---|
| `intent-brief` | disposable `intent-work/observations` snapshots only |
| `intent-audit` | nothing |
| `intent-coordinate` | visible `intent-work/` boards, leases, and cleanup |
| `intent-land` | disposable receipts, local commits, and integration refs |
| `intent-record` | tracked `.intent/` governance |

Do not make one skill read another skill's procedural prose. Skills call shared scripts and pass
structured facts.

## Configuration

Schema version stays `1`.

```yaml
version: 1
escalation: human
integration_branch: main
```

Both fields after version are optional. Escalation values are `human | agent`. When the target
is absent, capture the current branch at intake. A configured target must exist unless it is
the current unborn branch before the root commit.

Never add worker capability, question timing, execution mode, push authority, or adoption
preference to tracked configuration.

## Verification

Run every shell test:

```bash
for test_file in tests/test-*.sh; do sh "$test_file" || exit; done
```

Use POSIX shell for scripts. Test deterministic mechanics rather than duplicating policy prose.
Keep fixture cleanup scoped to exact temporary directories.
