#!/bin/sh
# Verify the optional semantic bookends and generalized discovery ontology.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cli="$root/bin/invariant"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/invariant-semantic-test.XXXXXX")
intent_file="$fixture-intent.yml"
assessment="$fixture-assessment.yml"
cleanup() { rm -rf "$fixture" "$intent_file" "$assessment"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$fixture/.invariant" "$fixture/docs" "$fixture/src"
printf 'one\n' >"$fixture/src/a.txt"
cat >"$fixture/docs/architecture.md" <<'EOF'
# Architecture

## Source ownership

The source domain owns the durable value and consumers may not redefine it.

## Unrelated material

This section is not selected for the source task.
EOF
cat >"$fixture/.invariant/config.yml" <<'EOF'
version: 1
execution: auto
lifecycle:
  intent_expansion: true
  outcome_review: true
EOF
cat >"$fixture/.invariant/DOMAINS.yml" <<'EOF'
version: 1
domains:
  - id: source
    responsibility: Owns source behavior.
    authority: user:task:test#turn-1
    architecture: [architecture:docs/architecture.md#source-ownership]
EOF
git -C "$fixture" add -A
git -C "$fixture" commit -qm seed
(cd "$fixture" && "$cli" evidence discovery capture implicit-source \
  --observation "Source recovery ownership is still implicit." \
  --evidence repo:src/a.txt --path src --domain source \
  --basis-prose "Code and architecture agree on ownership, but recovery behavior remains incomplete." >/dev/null)
git -C "$fixture" add .invariant/discoveries/implicit-source.yml
git -C "$fixture" commit -qm "record source discovery"

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

goal='Change the source with explicit acceptance'
goal_digest=$(printf '%s' "$goal" | git -C "$fixture" hash-object --stdin)
if out=$(cd "$fixture" && "$cli" task begin semantic-flow --goal "$goal" \
    --posture bounded --boundary no-record --path src/a.txt --domain source 2>&1); then
  die "intent expansion was silently skipped"
fi
printf '%s\n' "$out" | grep -q '^STATUS: awaiting-intent-expansion$' ||
  die "intent expansion did not expose its lifecycle gate"
[ "$(git -C "$fixture" branch --show-current)" = main ] ||
  die "intent expansion gate created the work branch early"
ok "intent expansion is an optional pre-implementation lifecycle gate"

cat >"$intent_file" <<EOF
version: 1
intent:
  goal: $goal
  outcomes:
    - id: O1
      prose: Source behavior changes.
  acceptance:
    - id: A1
      prose: The committed source contains the new value.
  constraints:
    - id: C1
      prose: Existing repository intent remains unchanged.
EOF
out=$(cd "$fixture" && "$cli" task begin semantic-flow --goal "$goal" \
  --posture bounded --boundary no-record --path src/a.txt --domain source --intent "$intent_file")
printf '%s\n' "$out" | grep -q '^STATUS: implementing$' ||
  die "expanded task did not enter implementation"
branch=$(printf '%s\n' "$out" | sed -n 's/^BRANCH: //p')
cat >"$fixture/docs/architecture.md" <<'EOF'
# Architecture

## Source ownership

Candidate prose must not become the premise used to review its own change.
EOF
guidance=$(cd "$fixture" && "$cli" task guidance semantic-flow)
printf '%s\n' "$guidance" | grep -q '^# Active task context$' ||
  die "compiled guidance omitted the active semantic envelope"
printf '%s\n' "$guidance" | grep -q '^# Expanded task intent$' ||
  die "compiled guidance omitted the task-specific prose"
printf '%s\n' "$guidance" | grep -q '^# Durable semantic reasoning$' ||
  die "stage guidance omitted durable semantic reasoning"
printf '%s\n' "$guidance" | grep -q '^# Repository archaeology$' ||
  die "stage guidance omitted repository archaeology"
printf '%s\n' "$guidance" | grep -q '^# Selected architecture prose$' ||
  die "compiled guidance omitted selected architecture prose"
printf '%s\n' "$guidance" | grep -q 'The source domain owns the durable value and consumers may not redefine it.' ||
  die "compiled guidance did not resolve the selected architecture section"
if printf '%s\n' "$guidance" | grep -q 'Candidate prose must not become the premise'; then
  die "compiled guidance read architecture from the candidate instead of accepted ground"
fi
printf '%s\n' "$guidance" | grep -q '^DISCOVERY-CONTEXT: implicit-source (open)$' ||
  die "compiled guidance omitted the relevant discovery"
printf '%s\n' "$guidance" | grep -q 'Source recovery ownership is still implicit.' ||
  die "compiled guidance reduced discovery reasoning to an identifier"
printf '%s\n' "$guidance" | grep -q '^# Progressive discovery$' ||
  die "stage guidance omitted progressive discovery prose"
printf '%s\n' "$guidance" | grep -q '^# Optional outcome review$' ||
  die "stage guidance omitted the enabled outcome review"
git -C "$fixture" restore docs/architecture.md
ok "free-form brief, discovery, coordinate, and landing prose is compiled for the active stage"

printf 'two\n' >"$fixture/src/a.txt"
git -C "$fixture" add src/a.txt
git -C "$fixture" commit -qm implementation
cat >"$assessment" <<EOF
version: 1
goal_digest: $goal_digest
paths: [src/a.txt]
interfaces: []
domains: [source]
boundary:
  disposition: no-record
governance: []
architecture_reviews: [architecture:docs/architecture.md#source-ownership]
checks: []
EOF
if out=$(cd "$fixture" && "$cli" task finish semantic-flow --assessment "$assessment" 2>&1); then
  die "outcome review was silently skipped"
fi
candidate_tree=$(printf '%s\n' "$out" | sed -n 's/^CANDIDATE-TREE: //p')
[ -n "$candidate_tree" ] || die "outcome review did not identify the exact candidate tree"
[ "$(git -C "$fixture" show main:src/a.txt)" = one ] ||
  die "outcome gate advanced the target before review"

cat >>"$assessment" <<EOF
candidate_tree: $candidate_tree
outcome_assessment:
  - satisfies: A1
    disposition: satisfied
    prose: The candidate contains the committed value.
    evidence: [repo:src/a.txt]
EOF
out=$(cd "$fixture" && "$cli" task finish semantic-flow --assessment "$assessment")
printf '%s\n' "$out" | grep -q '^STATUS: completed$' ||
  die "satisfied exact-tree outcome review did not complete"
[ "$(git -C "$fixture" branch --show-current)" = main ] ||
  die "completed reviewed task did not restore main"
[ "$(cat "$fixture/src/a.txt")" = two ] || die "reviewed task was not landed"
if git -C "$fixture" show-ref --verify -q "refs/heads/$branch"; then
  die "reviewed task branch survived cleanup"
fi
ok "outcome review binds stable acceptance IDs to the exact candidate tree"

out=$(cd "$fixture" && "$cli" evidence discovery capture missing-adr \
  --observation "No ADR describes the source boundary." \
  --searched docs/adr --path src --domain source --related task:document-source-boundary)
printf '%s\n' "$out" | grep -q '^STATUS: open$' || die "discovery was not captured"
discovery="$fixture/.invariant/discoveries/missing-adr.yml"
grep -q '^basis:' "$discovery" || die "discovery basis is missing"
grep -q '^relevance:' "$discovery" || die "discovery relevance is missing"
grep -q '^disposition:' "$discovery" || die "discovery disposition is missing"
(cd "$fixture" && "$cli" evidence discovery resolve missing-adr \
  --prose "Track documentation as follow-up work." --output task:document-source-boundary >/dev/null)
(cd "$fixture" && "$cli" state validate >/dev/null) ||
  die "discovery resolution to non-contract work was rejected"
ok "discoveries resolve broadly and do not have to become contracts"

echo "4 semantic option checks passed"
