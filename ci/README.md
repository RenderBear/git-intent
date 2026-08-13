# ci/ — the mechanical half, where the human already is

Review happens in a browser tab. So does merge. Neither is a place an agent session exists, which
means the two moments this layer most wants to reach are the two it cannot — and the long-lived
half of the system depends on `branch.landed`, which is a button on a web page.

CI is the only transport that reaches that tab.

It works because these checks are mechanical. Resolving an assertion's anchor, comparing
`captured_at` against a tip, and asking whether a note has dated entries are `git grep` and
`git log`. No model, therefore no session.

## What's here

| File | |
|---|---|
| `check-notes.sh` | POSIX. Every actual check lives here |
| `github-actions.example.yml` | A thin wrapper. Provider-specific lines only |

The split is deliberate. Every other transport in this design is plain git and runs anywhere;
this one is written against a provider's YAML and is the only thing in the repo that is. Keeping
the logic in a shell script means porting to GitLab CI or Buildkite is a different six-line
wrapper rather than a rewrite.

## Install

Copy both into the repo you're working in, then:

```bash
chmod +x ci/check-notes.sh
```

Run it locally exactly as CI does:

```bash
sh ci/check-notes.sh                      # every live note
sh ci/check-notes.sh .branch-notes/feature/rate-limit.md
```

## What fails the build, and what doesn't

Only a **violated** assertion exits non-zero: the anchor still resolves and the thing the author
said had to survive is gone.

Everything else is advisory and exits 0.

```
.branch-notes/feature/rate-limit.md
  ~ note is 6 commits behind HEAD (captured at c81f0a2)
  ok a1  contains src/client.py:dispatch RateLimiter
  FAIL a2  absent RetryDecorator
       why: the decorator double-counted every retried request
  ?? a3  contains src/client.py:validate_charge Money
       anchor no longer resolves — supersede this assertion if the move was intended
```

`??` is the one that matters for whether this survives contact with a real team. An anchor stops
resolving every time somebody renames a function, extracts a module, or splits a file — which is
to say, every time somebody does good work. Failing the build on that teaches people that the
intent checks are noise, and they will be right, and the violated ones go with them.

So unresolvable is a **question**: should this assertion be superseded? The answer belongs in the
note, appended by `capture-diff`, never edited in place.

That is also why nothing here writes to the repository. A check that enforces a claim as strictly
as `.gitattributes` has turned one branch author's sentence into repo policy that nobody voted
on. Assertions are testimony that happens to be falsifiable — not rules.

## Scope

Only **live** notes, and on a pull request only the notes that PR touches.

`_archive/` is skipped entirely, and this is not an optimization. Archived notes are frozen
(SPEC 7.3) and cannot be superseded, so the first legitimate rename after a branch lands would
put its assertions permanently in violation. A check that accumulates permanent failures is a
check nobody reads.

## Convergence

The `push` job **reports** what SPEC 3.8's convergence pass would repair — notes whose branches
are gone, waiting to be archived. It does not archive them. Archiving is a commit to the
integration branch, and nothing in CI has a mandate to make one; a human runs `/reconcile-notes`
having seen the report.
