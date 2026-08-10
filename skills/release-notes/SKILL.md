---
name: release-notes
description: Turn a commit range into a changelog written for the people who read changelogs — what changed, what it means for them, and why where the reason isn't obvious. Use this when cutting a release, preparing release notes or a changelog entry, summarizing what shipped in a range or since a tag, or when the user asks what went into a version.
---

# release-notes

A changelog generated from commit subjects is a list of commit subjects. It reads as though it was written for the person who wrote the commits, because it was.

The version worth shipping answers a different question: what is different for someone using this, and — where it isn't obvious — why. The second half is the part git can't supply and `.branch-notes/` can.

## Invocation

```
/release-notes                          # most recent tag..HEAD
/release-notes v2.3.0..HEAD             # explicit range
/release-notes v2.3.0..v2.4.0           # a released version, after the fact
/release-notes --audience integrators   # or: on-call, users
```

The range defaults to `$(git describe --tags --abbrev=0)..HEAD`. If the repo has no tags, say so and ask for the range rather than picking a commit count — "the last 40 commits" is not a release boundary and the notes will straddle one.

The audience argument changes what gets promoted, not just the tone. A library changelog leads with breaking changes for integrators; an internal service's is read by on-call at 3am wondering what shipped and leads with operational impact. Ask which if the repo doesn't make it obvious, and default to the reader who has to react to something.

## Workflow

### 1. Get the range and the sources

```bash
git log --oneline v2.3.0..HEAD
git log --merges --format='%h %s' v2.3.0..HEAD
git diff --stat v2.3.0..HEAD
```

Merge commits carry branch names, and branch names map to notes:

```bash
ls -R .branch-notes/_archive/
```

Most branches in a shipped range have landed and been deleted, so the archive is where their notes live — `reconcile-notes` puts them there. A range whose branches were never reconciled will have its notes still sitting in `.branch-notes/` proper; check both. A range where every branch has an archived note produces a substantially better changelog than one where none do — say which you had, if the difference is large.

### 2. Group by what changed for the reader

Not by author, not by directory, not by commit order. Standard groupings work because readers already know them:

- **Added** — new capability
- **Changed** — existing behavior is different
- **Fixed** — something broken now works
- **Deprecated / Removed** — plan accordingly
- **Security** — always its own section, always first

One branch may produce entries in several groups, and twelve commits may produce one entry. Collapse aggressively: `wip`, `address review`, and `fix lint` are not events in a user's life.

### 3. Write entries in the reader's terms

The test for each line: could someone who doesn't work on this decide whether it affects them?

```
Bad:   Refactor dispatch into PaymentDispatcher
Better: Payment dispatch now retries at the dispatcher level rather than
        per-request, so retry counts in logs reflect whole operations.
```

Pull the *why* from the branch note only where it changes what the reader should do. A recorded constraint that explains a surprising behavior belongs in the changelog; the abandoned approach that led to it does not — that's for `onboard-file`.

### 4. Surface what requires action

The section people actually read. Breaking changes, migrations, new required config, changed defaults, anything that fails on upgrade if ignored:

```markdown
## 2.4.0

### Requires action
- `RATE_LIMIT_RPS` is now required. Services without it fail at startup
  rather than defaulting to unlimited — the previous default silently
  exceeded Stripe's per-key limit under load.
- Migration 0042 rewrites the `charges` table. Locks for roughly 30s per
  million rows; schedule accordingly.

### Added
- Per-client rate limiting on outbound requests, applied to retries as
  well as first attempts.

### Changed
- Idempotency keys derive from request body rather than a generated UUID,
  so client-side retries now deduplicate correctly.

### Fixed
- Timezone parsing dropped sub-second precision on ISO timestamps with
  offsets (#412).
```

Derive breaking changes from the diff rather than trusting labels — signature changes on public interfaces, removed config keys, changed defaults, migrations. A breaking change missing from the notes is the one failure mode of this document that actually costs someone their evening.

### 5. Say what was omitted

Internal refactors, test changes, dependency bumps with no behavioral effect: one line at the end, or a link to the compare view. Silently dropping them is fine; pretending the list is exhaustive is not.

## Judgment

**Write for the reader you have.** A library changelog is read by integrators who need breaking changes. An internal service's is read by on-call at 3am wondering what shipped. Ask which if it isn't obvious from the repo, and default to the reader who has to react.

**Don't sell.** Changelogs describing changes as "exciting" are skimmed and then not trusted. State what's different.

**Numbers of commits are not achievements.** "47 commits from 6 contributors" belongs nowhere near this document.

**When there's nothing user-visible, say so.** "Internal changes only; no behavior differences" is a complete and useful release note, and much better than three paragraphs constructed to fill the page.