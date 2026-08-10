---
name: onboard-file
description: Explain why a file or a specific line is shaped the way it is — the decisions behind it, what is load-bearing, what is safe to change, and who to ask. Use this when someone inherits unfamiliar code, asks why a piece of code exists or why it was done this way, wonders whether something is safe to remove or refactor, or is about to change code they didn't write. Works at file level or on a specific line or function.
---

# onboard-file

`git blame` answers who and when. The question people actually ask is *why*, and answering it currently means blame, then the commit, then the PR, then a Slack thread that's been deleted.

This is the read path for everything the other skills recorded.

## Invocation

```
/onboard-file src/client.py            # whole file
/onboard-file src/client.py:88         # this line
/onboard-file src/client.py:88-104     # this range
/onboard-file src/client.py dispatch   # this function
```

The path is required and is the only thing that can't be derived. Everything else — when it was added, who has been in it, what it changes alongside, whether it's hot or dormant — comes from history.

Given a directory rather than a file, ask which file: the output is shaped around one file's decisions, and averaging it over twenty produces a summary with nothing actionable in it.

The line-level question is the common one — "why is *this* here" is asked far more often than "explain this file" — and it's the one blame answers worst, because the commit that last touched a line is usually a rename.

## Workflow

### 1. Read what was recorded before reconstructing anything

```bash
cat "$(git rev-parse --git-common-dir)/intent/base.md" 2>/dev/null
grep -rl 'client.py' .branch-notes/ 2>/dev/null
git check-attr -a -- src/client.py
```

The archive under `.branch-notes/_archive/` matters more than the live notes here. A landed branch's note describes code that is now in the integration branch — that file is at peak usefulness at exactly the moment it looks like history.

The baseline says whether this file is hot or dormant, who has been in it, and what it changes together with. All three change the advice: dormant code with no tests is a different risk from a file three people are editing this week, and a file that always changes alongside another is a file you cannot safely change alone.

### 2. Establish the shape

```bash
git log --follow --oneline -- src/client.py | head -30
git log --follow --diff-filter=A --format='%h %ad %an' -- src/client.py | tail -1
git log --format='%an' --follow -- src/client.py | sort | uniq -c | sort -rn
```

`--follow` is not optional. Without it, history stops at the last rename and you'll report a two-year-old file as three months old.

For a line or function:

```bash
git log -L 88,88:src/client.py --oneline | head -20        # line history
git log -L :dispatch:src/client.py --oneline | head -20    # function history
```

`git log -L` follows the line through moves and reindentation, which is what makes it useful where blame isn't. It gives the commits that actually changed this logic, rather than the one that last shifted it down four lines.

### 3. Find the reasoning

For each significant commit, in order of reliability:

1. The branch note, live or archived — recorded by whoever made the decision
2. The commit message body, not just the subject
3. The merge commit's PR number, if the message carries one
4. The diff itself, read for what problem it was solving

Say which level you got to. "Recorded in the branch note" and "inferred from the diff" are different claims, and a reader deciding whether to delete something needs to know which they're holding.

### 4. Separate load-bearing from incidental

This is the part that makes the output actionable:

- **Load-bearing** — there's a recorded reason, an external constraint, or a test that fails if it changes. Name the reason and the test.
- **Incidental** — a choice with no stated reason and no dependents. Probably fine to change.
- **Unknown** — nothing recorded and it isn't obvious. Say so rather than guessing; "no recorded reason" is honest and useful, while a plausible invented rationale gets quoted back later as fact.

Look specifically for reversals. If a note or history shows an approach was tried and dropped, that's the highest-value thing in the output — the next person will have the same good idea, and the diff contains no trace of why it didn't work.

### 5. Report

```
src/client.py — added 2024-03-11, 47 commits, hot (12 in last 3 months)
Primary authors: sam (28), dana (9)

WHAT IT IS
  Outbound HTTP client and dispatch layer for payment providers.

LOAD-BEARING
  Idempotency keys derive from the request body, not a UUID (L34).
    Recorded in docs/adr/0007-idempotency-keys.md — client retries must
    dedupe correctly. Changing this silently double-charges on retry.
    No test covers it.

  Rate limiter sits inside dispatch(), not as a decorator (L88).
    Recorded in .branch-notes/_archive/feature/rate-limit.md: the decorator
    was tried first and double-counted retried requests, because retries
    re-enter dispatch. Don't reintroduce it.

PROBABLY INCIDENTAL
  Module-level DEFAULT_TIMEOUT (L12) — no recorded reason, one caller.

UNKNOWN
  The 30s connection pool timeout (L34) was raised from 5s in c81f0a2 with
  commit message "fix". No note, no PR body. Ask sam before touching it.

ASK
  sam — 28 of 47 commits, and authored both recorded decisions above.
```

Line-level queries return the same structure scoped down: what the line does, what it was replacing, whether anything depends on it, and whether it's safe to remove.

## Judgment

**Distinguish recorded from inferred, every time.** This output gets pasted into PR comments and quoted as fact months later. An inference presented as a finding becomes a false constraint that nobody dares change.

**"No recorded reason" is a finding.** It tells someone the code can probably be changed, and points at where to add a note when they do.

**Don't summarize the code.** Anyone asking this can read it. The value is entirely in what isn't in the file.

**Name a person, and be honest about it.** Commit counts are a proxy for knowledge, not for availability or for who owns it now. If the primary author's last commit was two years ago, say that instead of sending someone to a dead end.