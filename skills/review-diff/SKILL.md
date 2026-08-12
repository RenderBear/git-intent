---
name: review-diff
description: Summarize a branch, PR, or diff for the people who have to review it — what changed, why, and where the risk actually sits — or check it against a requirement. Use this whenever the user asks for a PR/MR description, a summary of a branch or diff, help reviewing someone else's changes, "what's in this PR", "what should I look at first", whether a branch satisfies a ticket or spec, or is preparing changes for review. Also use when a diff is large enough that a reviewer would not read it carefully end to end, since that is exactly when a risk-ordered summary is the difference between a real review and a rubber stamp.
---

# review-diff

The point of a review summary is not to describe the diff. Reviewers can read the diff. The point is to tell them **where to spend their attention**, because attention is the scarce resource and a 900-line PR gets the same twenty minutes as a 90-line one.

So the organizing principle is risk, not file order. A summary that walks files alphabetically has sorted by an irrelevant key and buried the one function that changes behavior under forty lines of import reshuffling.

Two modes, and the input decides which:

- **Summary** — `/review-diff dev`. Risk-ordered, for a reviewer with no prior context.
- **Requirement check** — a written requirement is present. Goes clause by clause against the spec instead.

Requirement check is the stronger mode where a spec exists. Run it whenever there's something to check against.

## Invocation

```
/review-diff                                    # against the integration branch
/review-diff dev                                # against a different target
/review-diff dev "PROJ-412: per-client rate limiting, must apply to retries"
/review-diff dev PROJ-412                       # ticket id alone — see below
```

A second argument switches modes. Anything that reads as a requirement — pasted text, a ticket body, a question like "does this satisfy PROJ-412?" — triggers the clause-by-clause check instead of the summary.

A bare ticket id is the case that needs care. If nothing in the session can fetch it, **ask for the text rather than proceeding**: a requirement check against a remembered or guessed spec produces ticks that look authoritative and were never checked against anything. The branch note's recorded requirement counts as the text if it has one.

## Workflow

### 1. Get the real diff

```bash
TARGET="$1"
[ -z "$TARGET" ] && TARGET=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
[ -z "$TARGET" ] && for c in main master trunk develop; do
  git show-ref -q --verify "refs/remotes/origin/$c" && { TARGET=$c; break; }
done

BASE=$(git merge-base HEAD "origin/$TARGET")
git diff --stat $BASE..HEAD
git log --oneline $BASE..HEAD
git diff $BASE..HEAD
```

Diff against the merge base, not against the target directly — otherwise unrelated commits that landed on the target show up as part of this branch's changes and the summary describes work nobody in this PR did.

Say which target you resolved and how. `origin/HEAD` is unset in most non-cloned checkouts, so the fallback list carries more traffic than it looks like it should, and a summary computed against the wrong target is wrong in a way that reads as normal.

### 2. Read the intent before deriving it

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
cat ".branch-notes/$BRANCH.md" 2>/dev/null
cat "$(git rev-parse --git-common-dir)/intent/base.md" 2>/dev/null
```

If a branch note exists, it holds what the branch was for, the requirement it was written against, and the approaches that were tried and dropped. Use it. Re-deriving intent from a diff is a reconstruction; the note is testimony.

If it doesn't exist, derive intent from commit messages, the ticket if reachable, and the shape of the change. Say which you did — a reviewer should know whether "this branch adds per-client rate limiting" is quoted or inferred.

The baseline tells you what's normal in this repo, so deviations from it are findings rather than noise. It's a regenerable cache — if it's missing or stale, that's a `/baseline-scan` away and not a reason to stop.

### 2b. Check whether testimony exists at all

Capture is triggered by someone choosing to run it, and nothing in git records that choice. So the only way to know whether the testimony layer is working is to check for its absence — and this skill runs at the moment that check is cheapest and most useful, because a missing note is still fixable before the branch lands.

Three states, and they need different things said about them:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
NOTE=".branch-notes/$BRANCH.md"

test -f "$NOTE"                                   # exists at all?
grep -c '^- 20[0-9][0-9]-' "$NOTE" 2>/dev/null    # dated reasoning entries
comm -23 <(git log --format='' --name-only $BASE..HEAD | sort -u) \
         <(git diff --name-only $BASE..HEAD | sort -u)   # work that was undone
```

- **No note** — report it plainly, once, without nagging. A note is worth most on a branch with non-obvious reasoning; a three-line typo fix doesn't need one and saying so is part of being trusted.
- **A note with no dated entries under "Why this shape"** — it's a stub. It records what changed, which the diff already had, and none of what didn't survive.
- **A note that exists, but the branch has files touched-and-reverted that it doesn't mention** — the strongest signal available. Something was tried and abandoned and the note is silent about it. Name the file; that's what makes the gap answerable rather than rhetorical.

The third case is the one worth interrupting for. It is the only automatic evidence that the differentiated half of this system didn't fire, and it decays — once the branch lands and the note is archived, the reasoning is gone for good and no later run can recover it.

### 2c. Check whether the note still describes this branch

Every note ends with the commit it was written against. Review changes code; nobody re-runs capture; the note ships stale into the integration branch — and it is the *merged* note that gets archived, so the version preserved forever is the one written before review touched anything.

One comparison catches it, and this skill is already reading both sides:

```bash
ANCHOR=$(sed -n 's/^captured_at: *//p' ".branch-notes/$BRANCH.md" 2>/dev/null)
[ -n "$ANCHOR" ] && git log --oneline "$ANCHOR"..HEAD
```

Non-empty means the note is behind the branch. Report it at the top of the summary, with the count and whether those commits look behavioral:

```
Note is 6 commits behind HEAD (last captured at c81f0a2).
Three of them change behavior — the exhaustion path in client.py:L94 is new
since the note was written, and the note still lists it under Open.
Re-run capture-diff before merging.
```

Behavioral commits since the anchor mean `capture-diff` should append and re-anchor. Review nits mean re-anchoring alone. Either way this is a finding for the author, not something to fix silently — the note is their testimony and appending to it on their behalf is putting words in their mouth.

### 2d. Evaluate the branch's own assertions

The note's `assert` block is what the author said had to survive, written so a command can falsify it. This is the last cheap moment to check — once the branch lands, a broken claim is a production question instead of a review comment.

Anchor first, then the predicate. That order is the whole design:

```bash
git grep -qn '\bdispatch\b' -- src/client.py   || echo "a1 unresolvable"   # anchor
git grep -qn 'RateLimiter'  -- src/client.py   || echo "a1 violated"       # predicate
```

Three verdicts, and the third is not a gentler second:

```
ASSERTIONS
  ✓ a1  contains src/client.py:dispatch RateLimiter
  ✗ a2  absent RetryDecorator
        reintroduced at src/retry.py:L14 — the note says this double-counted
        every retried request
  ? a3  contains src/client.py:validate_charge Money
        anchor gone: src/client.py:validate_charge no longer resolves. Moved in
        this branch? If so, supersede a3 rather than dropping it.
```

- **✓ holds** — anchor resolved, predicate true.
- **✗ violated** — anchor resolved, predicate false. Quote the assertion's `why:` line alongside it; a predicate without its sentence is unarguable, and the sentence is the thing the author actually meant.
- **? unresolvable** — the anchor is gone. A **question, not a failure.**

Never report unresolvable as a failure and never block on one. Every legitimate refactor moves an anchor, and a rename that reads as a violation teaches people to skip the whole section — which costs the real violations too. If the answer is that the assertion should be superseded, that is `capture-diff`'s job and not this skill's; the note is the author's testimony and rewriting it for them is putting words in their mouth.

Check only **live** assertions. An entry named by another entry's `supersedes:` is history, and evaluating it reports violations for claims that were deliberately retired.

Report the scope limit where it matters: the needle is file-scoped even when the anchor names a symbol, so `contains src/client.py:dispatch RateLimiter` means both appear in that file — not that one encloses the other.

### 3. Separate signal from noise

Sort every hunk into one of these, because reviewers need to know which pile a change is in before they can judge it:

- **Behavior change** — the program does something different now. This is what review is *for*.
- **Interface change** — a signature, schema, config key, API route, or database column changed. High blast radius, often invisible in the diff's local context.
- **Refactor** — structure moved, behavior claimed unchanged. Worth verifying that claim.
- **Mechanical** — formatting, renames, generated files, lockfiles, import sorting. Should be explicitly set aside so it stops competing for attention.

Volume correlates poorly with risk. A 2,000-line lockfile update and a three-line change to an auth check are not comparable, and a summary that reports "2,140 lines changed" without that distinction has actively misinformed the reviewer.

### 4. Identify risk

Call out concretely, and only where actually present:

- Changes to auth, permissions, input validation, or anything handling untrusted data
- Interface changes with callers that weren't updated — check for them rather than assuming
- Migrations, especially irreversible ones or ones that lock large tables
- Concurrency, retries, timeouts, error handling — the paths that are hard to test and fail in production
- Behavior changes arriving with no test changes; this is worth naming plainly
- Deleted code — reviewers skim deletions, and deletions are where functionality quietly leaves
- Changes to `.gitattributes`, `CODEOWNERS`, CI config, or `.branch-notes/` arriving in the same PR as the code they would affect. These are policy: a `-merge` attribute or an ownership change alters how future conflicts get resolved and who has to sign off, and it is far easier to see from here than from the diff. Name it explicitly rather than letting it pass as a config tweak

Don't manufacture risk to fill the section. "No elevated-risk areas; this is a contained change to X" is genuinely useful to read, and inflating routine changes into warnings trains people to skip the section.

### 5a. Summary mode

```markdown
## What this does
<1-2 sentences: the goal, in terms of behavior or user impact>

## Changes
- **<area>** — <what changed and why>
- **<area>** — <what changed and why>

## Review focus
1. `path/to/file.py:L120` — <the specific thing to check and why it matters>
2. `path/to/other.py` — <...>

## Lower priority
<mechanical changes, grouped in one line so reviewers can skip them confidently>

## Notes
<migrations, follow-ups, deliberate omissions, anything a reviewer would otherwise ask about>
```

Point at specific files and lines in "Review focus". A reviewer who has to hunt for the thing you mean will give up and skim instead.

Where the change is small and contained, compress hard — a four-line summary for a four-line PR. Applying the full template to a typo fix is noise; the template serves the reviewer, not itself.

### 5b. Requirement check mode

Get the requirement text. In order of preference: the branch note's recorded requirement, the ticket if reachable, or what the user pasted. If only an ID is available and nothing can fetch it, ask for the text rather than guessing at what `PROJ-412` wanted.

Break it into individually checkable clauses and give each one of four verdicts:

```
PROJ-412 — rate limiting for outbound requests

✓ Configurable limit        RATE_LIMIT_RPS in config.py
✓ Applies to retries        limiter wraps the retry loop (client.py:L88)
✗ Per-client, not global    one bucket shared across clients (client.py:L61)
? "Fails gracefully"        not judgeable from a diff; no test covers exhaustion

Not in the requirement:
  connection pool timeout raised 5s → 30s (client.py:L34) — unrelated to PROJ-412
```

- **✓** — satisfied, with the file and line that satisfies it. Never tick without a location.
- **✗** — contradicted by the code. Point at what contradicts it.
- **?** — not determinable from a diff. Vague clauses, runtime behavior, performance, anything needing a test that doesn't exist.
- **Not in the requirement** — code that does things the spec doesn't ask for.

The `?` verdict is the one that makes this mode worth running. A checklist that only has ticks and crosses will convert every ambiguous clause into a false tick, and a false tick is worse than no check. Say plainly what could not be judged and what would settle it — usually a test that doesn't exist yet.

Scope creep belongs in the last section rather than being silently dropped. A refactor bundled with a feature is a legitimate review finding, and it's far easier to see from here than from the diff.

## Writing for the reader

Write for someone who knows the codebase but not this branch. Skip the narration of what a reviewer can see (`renamed X to Y`) in favor of what they can't (`renamed X to Y because the old name collided with the ORM's reserved attribute, which was causing the silent field drop in #412`).

Prefer plain description over selling. A summary that argues for the change makes reviewers suspicious, and rightly so — the job is to help them evaluate, not to get to approval.

When commit messages are uninformative (`fix`, `wip`, `address comments`), derive intent from the diff and say so, rather than repeating empty messages back as if they were content.