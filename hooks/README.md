# hooks

Optional. These detect two of git-intent's lifecycle events and print a suggestion to stderr.

**A git hook cannot run an agent.** It has no session, no context, and no way to ask you
anything. So these do not resolve, capture, or reconcile — they notice that a moment arrived
and tell you which skill handles it. The work still happens in your agent session, on your say-so.

That is the whole design. The alternative — a hook that shells out to something that writes to
your repo — is the separate service this project exists to avoid.

| Hook | Event | Fires when | Suggests |
|---|---|---|---|
| `post-checkout` | `branch.start` | a branch is checked out with no commits of its own | `/collision-scan` |
| `post-merge` | `branch.landed` | a merge completes on the integration branch, with unarchived notes present | `/reconcile-notes` |

Both exit 0 unconditionally. Neither writes anything. A hook that blocks a commit gets disabled
within a week, and takes the useful ones with it.

## Enabling

```bash
git config core.hooksPath hooks
```

Run it in the repo where you want the events, from its root. The hooks ship with the clone, so
this is one command per clone rather than a file each developer has to copy.

**`core.hooksPath` replaces the hook directory entirely.** Anything already in `.git/hooks` —
a pre-commit formatter, a commit-msg linter, whatever a framework installed — stops running the
moment you set it. Check first:

```bash
ls .git/hooks | grep -v '\.sample$'
```

If that lists anything, don't set `core.hooksPath`. Link the two files individually instead:

```bash
ln -s ../../hooks/post-checkout .git/hooks/post-checkout
ln -s ../../hooks/post-merge    .git/hooks/post-merge
```

The relative path is correct as written — the symlink resolves from inside `.git/hooks/`.

Linked worktrees share `.git/hooks` with the main worktree, so either method covers all of them
at once.

## Turning it off

```bash
git config --unset core.hooksPath
```

Or delete the symlinks. Nothing else in git-intent depends on these — every event is detectable
from git state on demand, which is why the hooks are a convenience rather than a requirement.

## What these deliberately don't cover

`decision.made` — the moment an approach is abandoned or a constraint forces a design. It leaves
no git state to detect, so no hook can see it. That one needs a rule in the repo's `AGENTS.md`
or `CLAUDE.md` instead; see [`AGENTS.example.md`](../AGENTS.example.md).

`branch.ready` — no clean local signal. A pull request opening is a forge event, and reacting to
it would mean running a service.

`review.round` — detectable, but the natural place to check is when someone runs `/review-diff`,
which already reads both the note and the diff. A hook would only tell you what that run tells
you anyway.
