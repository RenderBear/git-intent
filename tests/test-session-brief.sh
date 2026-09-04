#!/bin/sh
# Verify reusable brief receipts stay non-authoritative, shared, and causally fresh.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/invariant-session-brief-test.XXXXXX")
framework=$(mktemp -d "${TMPDIR:-/tmp}/invariant-session-framework-test.XXXXXX")
linked="$fixture-linked"
unborn="$fixture-unborn"
cleanup() { rm -rf "$fixture" "$framework" "$linked" "$unborn"; }
trap cleanup EXIT HUP INT TERM

mkdir -p "$framework/skills"
cp -R "$root/skills/intent-brief" "$root/skills/intent-land" "$root/skills/intent-coordinate" "$framework/skills/"
cp -R "$root/src" "$framework/src"
export INVARIANT_PYTHON="$root/.venv/bin/python"
session_brief="$framework/skills/intent-brief/scripts/session-brief.sh"

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$fixture/.invariant/discoveries" "$fixture/docs" "$fixture/src"
cat >"$fixture/docs/architecture.md" <<'EOF'
# Architecture

## Source boundary

Source behavior remains isolated.
EOF
printf 'seed\n' >"$fixture/src/a file.py"
cat >"$fixture/.invariant/config.yml" <<'EOF'
version: 1
resolution: assisted
integration_branch: main
EOF
cat >"$fixture/.invariant/DOMAINS.yml" <<'EOF'
version: 1
domains:
  - id: source
    responsibility: Owns source behavior.
    authority: user:task:test#turn-1
    architecture: [architecture:docs/architecture.md#source-boundary]
EOF
git -C "$fixture" add -A
git -C "$fixture" commit -qm seed

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

out=$(cd "$fixture" && sh "$session_brief" open task-1 --goal "Change source safely" \
  --posture bounded --boundary no-record --path "src/a file.py" --interface SourceApi --domain source)
printf '%s\n' "$out" | grep -q '^BRIEF: opened task-1$' || die "brief did not open"
manifest="$fixture/.git/invariant/briefs/task-1.yml"
[ -f "$manifest" ] || die "brief receipt is not stored in the shared Git directory"
[ ! -e "$fixture/.invariant/runtime" ] || die "brief cache polluted the coordination runtime"
grep -q 'Change source safely' "$manifest" && die "raw goal was persisted"
ok "brief receipt is disposable Git-local state"

out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change source safely" \
  --path "src/a file.py" --interface SourceApi --domain source)
printf '%s\n' "$out" | grep -q '^BRIEF: fresh task-1$' || die "unchanged brief was not reusable"
printf '%s\n' "$out" | grep -q '^REUSE: cached semantic envelope$' || die "reuse overstated cached model context"
printf '%s\n' "$out" | grep -q '^POSTURE: bounded$' || die "cached posture was not retained"
ok "unchanged instructions, governance, goal, and scope reuse the brief"

if out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "A different task" 2>&1); then
  die "changed goal reused the prior brief"
fi
printf '%s\n' "$out" | grep -q '^STALE: goal changed$' || die "goal staleness lacks a precise reason"
ok "goal digest prevents cross-purpose reuse"

out=$(cd "$fixture" && sh "$session_brief" check task-1 \
  --goal "Safely change source" --compatible-goal \
  --path "src/a file.py" --interface SourceApi --domain source)
printf '%s\n' "$out" | grep -q '^GOAL: changed text accepted for cached semantic envelope$' ||
  die "compatible goal wording was not acknowledged"
printf '%s\n' "$out" | grep -q '^BRIEF: fresh task-1$' || die "compatible goal wording did not reuse the brief"
out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "Safely change source")
printf '%s\n' "$out" | grep -q '^BRIEF: fresh task-1$' || die "accepted goal digest was not refreshed"
(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change source safely" --compatible-goal >/dev/null) ||
  die "test goal could not be restored"
ok "semantic confirmation reuses the envelope and refreshes exact goal identity"

if out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change another source" \
  --compatible-goal --path src/new.py 2>&1); then
  die "compatible-goal bypassed expanded scope"
fi
printf '%s\n' "$out" | grep -q '^STALE: path scope expanded to src/new.py$' ||
  die "hard freshness checks did not outrank semantic goal confirmation"
out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change source safely")
printf '%s\n' "$out" | grep -q '^BRIEF: fresh task-1$' || die "rejected goal change altered the receipt"
ok "semantic confirmation cannot bypass or partially update hard freshness gates"

printf '\nEditorial guidance clarification.\n' >>"$framework/src/invariant/semantics/guidance/brief.md"
out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change source safely")
printf '%s\n' "$out" | grep -q '^BRIEF: fresh task-1$' ||
  die "stage guidance evicted an otherwise fresh receipt"
ok "cognitive guidance reload is independent from receipt freshness"

cp "$framework/src/invariant/mechanics/governance.py" "$framework/governance.saved"
printf '\n# Cache behavior changed.\n' >>"$framework/src/invariant/mechanics/governance.py"
if out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change source safely" 2>&1); then
  die "changed CLI mechanics reused the prior brief"
fi
printf '%s\n' "$out" | grep -q '^STALE: CLI mechanics changed$' || die "mechanics staleness lacks a precise reason"
mv "$framework/governance.saved" "$framework/src/invariant/mechanics/governance.py"
ok "mechanics hash guards executable behavior without coupling skill instructions"

if out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change source safely" --path src/new.py 2>&1); then
  die "expanded path scope reused a narrow brief"
fi
printf '%s\n' "$out" | grep -q '^STALE: path scope expanded to src/new.py$' || die "scope expansion lacks a precise reason"
ok "scope expansion invalidates reuse"

cat >"$fixture/.invariant/discoveries/layout.yml" <<EOF
version: 1
id: layout
status: pending
ground: $(git -C "$fixture" rev-parse HEAD)
tree: $(git -C "$fixture" rev-parse 'HEAD^{tree}')
domains: [source]
statement: Source currently has one file.
evidence: [repo:src]
candidates: [architecture]
EOF
(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change source safely" >/dev/null) || die "non-authoritative evidence invalidated governance"
ok "non-authoritative discoveries stay outside brief freshness"

cp "$fixture/.invariant/DOMAINS.yml" "$fixture/.invariant/DOMAINS.saved"
sed 's/Owns source behavior/Owns isolated source behavior/' "$fixture/.invariant/DOMAINS.saved" >"$fixture/.invariant/DOMAINS.yml"
if out=$(cd "$fixture" && sh "$session_brief" check task-1 --goal "Change source safely" 2>&1); then
  die "changed selected governance reused a stale brief"
fi
printf '%s\n' "$out" | grep -q '^STALE: selected governance changed$' || die "governance staleness lacks a precise reason"
mv "$fixture/.invariant/DOMAINS.saved" "$fixture/.invariant/DOMAINS.yml"
ok "selected governance digest guards semantic reuse"

git -C "$fixture" worktree add -q -b linked "$linked"
out=$(cd "$linked" && sh "$session_brief" check task-1 --goal "Change source safely")
printf '%s\n' "$out" | grep -q '^BRIEF: fresh task-1$' || die "linked worktree could not reuse shared brief"
ok "linked worktrees share the Git-local receipt"

printf 'unrelated\n' >"$fixture/unrelated.txt"
git -C "$fixture" add unrelated.txt
git -C "$fixture" commit -qm "unrelated main work"
out=$(cd "$linked" && sh "$session_brief" check task-1 --goal "Change source safely")
printf '%s\n' "$out" | grep -q '^HEAD: advanced .* — mergeable, brief reused$' || die "unrelated head movement did not reuse the brief"
printf '%s\n' "$out" | grep -q '^BRIEF: fresh task-1$' || die "advanced mergeable head was not fresh"
ok "unrelated integration work advances the cached head without re-briefing"

printf '\nAccepted ownership is clarified.\n' >>"$fixture/docs/architecture.md"
git -C "$fixture" commit -qam "change governing material"
if out=$(cd "$linked" && sh "$session_brief" check task-1 --goal "Change source safely" 2>&1); then
  die "changed governing material reused the prior brief"
fi
printf '%s\n' "$out" | grep -q '^STALE: governing material changed — architecture:docs/architecture.md#source-boundary$' ||
  die "governing-material staleness lacks a precise reason"
ok "governing material changes refresh semantic context"

git -C "$linked" merge -q --ff-only main
(cd "$linked" && sh "$session_brief" open task-1 --goal "Change source safely" \
  --posture bounded --boundary no-record --path "src/a file.py" --interface SourceApi --domain source >/dev/null)
printf 'task\n' >"$linked/src/a file.py"
git -C "$linked" commit -qam "task source change"
printf 'main\n' >"$fixture/src/a file.py"
git -C "$fixture" commit -qam "conflicting main change"
if out=$(cd "$linked" && sh "$session_brief" check task-1 --goal "Change source safely" 2>&1); then
  die "real content conflict was reported as mergeable"
fi
printf '%s\n' "$out" | grep -q '^MERGE-REQUIRED: task conflicts with advanced integration head ' ||
  die "content conflict was misclassified as semantic staleness"
ok "real content conflicts require merging without discarding semantic context"

out=$(cd "$fixture" && sh "$session_brief" invalidate task-1)
printf '%s\n' "$out" | grep -q '^BRIEF: invalidated task-1$' || die "brief was not invalidated"
[ ! -e "$manifest" ] || die "invalidated brief remains on disk"
ok "invalidation removes only the selected receipt"

mkdir -p "$unborn/.invariant"
git -C "$unborn" init -qb main
cat >"$unborn/.invariant/config.yml" <<'EOF'
version: 1
integration_branch: main
EOF
out=$(cd "$unborn" && sh "$session_brief" open unborn-task --goal "Create the repository" \
  --posture local --boundary no-record --path README.md)
printf '%s\n' "$out" | grep -q '^BRIEF: opened unborn-task$' || die "unborn repository could not open a brief"
out=$(cd "$unborn" && sh "$session_brief" check unborn-task --goal "Create the repository")
printf '%s\n' "$out" | grep -q '^BRIEF: fresh unborn-task$' || die "unborn repository could not reuse its brief"
ok "brief receipts support an unborn integration branch"

echo "16 session-brief checks passed"
