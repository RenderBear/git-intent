#!/bin/sh
# Verify the packaged CLI owns task lifecycle and exact mechanics.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cli="$root/bin/invariant"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/invariant-cli-test.XXXXXX")
assessment="$fixture-assessment.yml"
cleanup() { rm -rf "$fixture" "$assessment"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$fixture/src"
printf 'one\n' >"$fixture/src/a.txt"
git -C "$fixture" add src/a.txt
git -C "$fixture" commit -qm seed

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

goal='Change source through the CLI'
goal_digest=$(printf '%s' "$goal" | git -C "$fixture" hash-object --stdin)
out=$(cd "$fixture" && "$cli" task begin cli-flow --goal "$goal" \
  --path src/a.txt)
printf '%s\n' "$out" | grep -q '^STATUS: implementing$' || die "automatic begin did not enter implementation"
branch=$(printf '%s\n' "$out" | sed -n 's/^BRANCH: //p')
case "$branch" in intent/work/cli-flow-*) ;; *) die "begin did not generate a task branch" ;; esac
[ "$(git -C "$fixture" branch --show-current)" = "$branch" ] || die "begin did not switch to the task branch"
receipt="$fixture/.git/invariant/briefs/cli-flow.yml"
[ -f "$receipt" ] || die "begin did not create a Git-local receipt"
grep -q '^mechanics_digest:' "$receipt" || die "receipt does not bind CLI mechanics"
grep -q '^  boundary: unresolved$' "$receipt" || die "omitted boundary was not kept unresolved"
if grep -q '^skills:' "$receipt"; then die "receipt still binds skill packages"; fi
ok "automatic begin opens a receipt and isolated generated branch"

out=$(cd "$fixture" && "$cli" task status cli-flow)
printf '%s\n' "$out" | grep -q '^STATUS: implementing$' || die "status lost lifecycle stage"
printf '%s\n' "$out" | grep -q "^BRANCH: $branch$" || die "status lost task branch"
out=$(cd "$fixture" && "$cli" task check cli-flow --goal-digest "$goal_digest")
printf '%s\n' "$out" | grep -q '^BRIEF: fresh cli-flow$' || die "digest-based lifecycle check failed"
ok "status and check resume lifecycle state without raw goal persistence"

printf 'two\n' >"$fixture/src/a.txt"
git -C "$fixture" add src/a.txt
git -C "$fixture" commit -qm implementation
cat >"$assessment" <<EOF
version: 1
goal_digest: $goal_digest
paths: [src/a.txt]
interfaces: []
domains: []
boundary:
  disposition: no-record
governance: []
architecture_reviews: []
checks: []
EOF

out=$(cd "$fixture" && "$cli" task finish cli-flow --assessment "$assessment" --subject "change source")
printf '%s\n' "$out" | grep -q '^LANDED:' || die "finish did not use exact-tree landing"
printf '%s\n' "$out" | grep -q '^STATUS: completed$' || die "finish did not complete lifecycle"
[ "$(git -C "$fixture" branch --show-current)" = main ] || die "finish did not restore the integration branch"
[ "$(cat "$fixture/src/a.txt")" = two ] || die "finish did not land implementation"
[ ! -f "$receipt" ] || die "finish did not invalidate the receipt"
if git -C "$fixture" show-ref --verify -q "refs/heads/$branch"; then die "finish did not remove the landed task branch"; fi
ok "finish verifies, lands, restores the target, and cleans lifecycle state"

governance_goal='Establish initial repository governance'
governance_digest=$(printf '%s' "$governance_goal" | git -C "$fixture" hash-object --stdin)
out=$(cd "$fixture" && "$cli" task begin initial-governance --goal "$governance_goal")
governance_branch=$(printf '%s\n' "$out" | sed -n 's/^BRANCH: //p')
mkdir -p "$fixture/.invariant" "$fixture/docs" "$fixture/checks"
cat >"$fixture/docs/architecture.md" <<'EOF'
# Architecture

## Source contract

The source owner provides a stable value to its consumer.
EOF
cat >"$fixture/checks/source-contract.sh" <<'EOF'
#!/bin/sh
test -f src/a.txt
EOF
chmod +x "$fixture/checks/source-contract.sh"
cat >"$fixture/.invariant/DOMAINS.yml" <<'EOF'
version: 1
domains:
  - id: source
    responsibility: Owns the source value.
    authority: user:task:initial-governance#goal
    architecture: [architecture:docs/architecture.md#source-contract]
    contracts: [source.contract.v1]
  - id: consumer
    responsibility: Consumes the source value.
    authority: user:task:initial-governance#goal
EOF
cat >"$fixture/.invariant/CONTRACTS.yml" <<'EOF'
version: 1
contracts:
  - id: source.contract.v1
    assertion: The source value remains available to its consumer.
    authority: user:task:initial-governance#goal
    between: [source, consumer]
    surfaces: [repo:src/a.txt]
    architecture: [architecture:docs/architecture.md#source-contract]
    verifies: [command:checks/source-contract.sh]
EOF
git -C "$fixture" add -A
git -C "$fixture" commit -qm "establish initial governance"
cat >"$assessment" <<EOF
version: 1
goal_digest: $governance_digest
paths: [.invariant/DOMAINS.yml, .invariant/CONTRACTS.yml, docs/architecture.md, checks/source-contract.sh]
interfaces: []
domains: [source, consumer]
boundary:
  disposition: recorded
governance: [domain:source, domain:consumer, contract:source.contract.v1]
architecture_reviews: [architecture:docs/architecture.md#source-contract]
checks: []
allow_open: true
EOF
out=$(cd "$fixture" && "$cli" task finish initial-governance --assessment "$assessment")
printf '%s\n' "$out" | grep -q '^CHECK: running — command:checks/source-contract.sh$' ||
  die "new contract verifier did not run during governance adoption"
printf '%s\n' "$out" | grep -q '^CHECKS: 1 unique$' ||
  die "governance adoption did not count the new contract verifier"
[ "$(git -C "$fixture" branch --show-current)" = main ] ||
  die "initial governance did not restore the integration branch"
if git -C "$fixture" show-ref --verify -q "refs/heads/$governance_branch"; then
  die "initial governance branch survived cleanup"
fi
ok "initial governance can select candidate-defined domains and runs their contract verifiers"

mkdir -p "$fixture/checks"
cat >"$fixture/checks/fail.sh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$fixture/checks/fail.sh"
git -C "$fixture" add checks/fail.sh
git -C "$fixture" commit -q -m "add failing check" -m "Intent-Unit: test-setup
Intent-Scope: area.checks
Intent-Boundary: no-record"
failed_goal='Keep failed work recoverable'
failed_digest=$(printf '%s' "$failed_goal" | git -C "$fixture" hash-object --stdin)
out=$(cd "$fixture" && "$cli" task begin failed-flow --goal "$failed_goal" \
  --boundary no-record --path src/a.txt)
failed_branch=$(printf '%s\n' "$out" | sed -n 's/^BRANCH: //p')
printf 'not-landed\n' >"$fixture/src/a.txt"
git -C "$fixture" add src/a.txt
git -C "$fixture" commit -qm "candidate that fails verification"
cat >"$assessment" <<EOF
version: 1
goal_digest: $failed_digest
paths: [src/a.txt]
interfaces: []
domains: []
boundary:
  disposition: no-record
governance: []
architecture_reviews: [architecture:docs/architecture.md#source-contract]
checks: [command:checks/fail.sh]
EOF
if out=$(cd "$fixture" && "$cli" task finish failed-flow --assessment "$assessment" 2>&1); then
  die "failed verifier advanced the lifecycle"
fi
printf '%s\n' "$out" | grep -q '^CHECK: running — command:checks/fail.sh$' || die "failed verifier output was hidden"
printf '%s\n' "$out" | grep -q '^RECOVERY: receipt and task branch retained; integration target unchanged$' ||
  die "failed finish did not explain retained lifecycle state"
printf '%s\n' "$out" | grep -q "^NEXT: inspect with 'invariant task status failed-flow'" ||
  die "failed finish did not provide a recovery command"
[ "$(git -C "$fixture" show main:src/a.txt)" = two ] || die "failed verifier advanced main"
[ -f "$fixture/.git/invariant/briefs/failed-flow.yml" ] || die "failed verifier discarded the receipt"
[ "$(git -C "$fixture" branch --show-current)" = "$failed_branch" ] || die "failed verifier discarded the work branch"
git -C "$fixture" switch -q main
git -C "$fixture" branch -D "$failed_branch" >/dev/null
(cd "$fixture" && "$cli" task invalidate failed-flow >/dev/null)
ok "verification failure leaves the target unchanged and task work recoverable"

json=$(cd "$fixture" && "$cli" --format json context reach --path src/a.txt)
printf '%s\n' "$json" | grep -q '"protocol":1' || die "JSON protocol version is missing"
printf '%s\n' "$json" | grep -q '"command":"context.reach"' || die "JSON command identity is missing"
printf '%s\n' "$json" | grep -q '"status":"ok"' || die "JSON success status is missing"
printf '%s\n' "$json" | grep -q '"name":"TOPOLOGY","value":"area.src"' || die "JSON records are not structured"
if printf '%s\n' "$json" | grep -q '"output"'; then die "compact JSON duplicated the text rendering"; fi
verbose_json=$(cd "$fixture" && "$cli" --format json --verbose context reach --path src/a.txt)
printf '%s\n' "$verbose_json" | grep -q '\\nREACH: bounded' || die "verbose JSON omitted the requested text rendering"
ok "read-only commands expose compact JSON with opt-in text rendering"

mkdir -p "$fixture/.invariant"
cat >"$fixture/.invariant/config.yml" <<'EOF'
version: 1
execution: assisted
integration_branch: main
EOF
git -C "$fixture" add .invariant/config.yml
git -C "$fixture" commit -q -m "configure assisted execution" -m "Intent-Unit: test-setup
Intent-Scope: area.root
Intent-Boundary: no-record"

out=$(cd "$fixture" && "$cli" task begin assisted-flow --goal "Pause before branch creation" \
  --boundary no-record --path src/a.txt)
printf '%s\n' "$out" | grep -q '^STATUS: awaiting-branch$' || die "assisted begin did not pause"
assisted_branch=$(printf '%s\n' "$out" | sed -n 's/^BRANCH: //p')
[ "$(git -C "$fixture" branch --show-current)" = main ] || die "assisted begin changed branches without approval"
if git -C "$fixture" show-ref --verify -q "refs/heads/$assisted_branch"; then die "assisted begin created a branch before approval"; fi
if (cd "$fixture" && "$cli" task continue assisted-flow >/dev/null 2>&1); then
  die "assisted continuation applied without --apply"
fi
out=$(cd "$fixture" && "$cli" task continue assisted-flow --apply)
printf '%s\n' "$out" | grep -q '^STATUS: implementing$' || die "approved continuation did not enter implementation"
[ "$(git -C "$fixture" branch --show-current)" = "$assisted_branch" ] || die "approved continuation did not switch branches"
printf 'three\n' >"$fixture/src/a.txt"
git -C "$fixture" add src/a.txt
git -C "$fixture" commit -qm "assisted implementation"
assisted_goal_digest=$(printf '%s' "Pause before branch creation" | git -C "$fixture" hash-object --stdin)
cat >"$assessment" <<EOF
version: 1
goal_digest: $assisted_goal_digest
paths: [src/a.txt]
interfaces: []
domains: []
boundary:
  disposition: no-record
governance: []
architecture_reviews: [architecture:docs/architecture.md#source-contract]
checks: []
EOF
if out=$(cd "$fixture" && "$cli" task finish assisted-flow --assessment "$assessment" 2>&1); then
  die "assisted finish landed before approval"
fi
printf '%s\n' "$out" | grep -q '^STATUS: awaiting-landing$' || die "assisted finish did not pause before landing"
[ "$(git -C "$fixture" show main:src/a.txt)" = two ] || die "assisted finish moved main before approval"
out=$(cd "$fixture" && "$cli" task continue assisted-flow --apply)
printf '%s\n' "$out" | grep -q '^STATUS: completed$' || die "approved landing continuation did not complete"
[ "$(cat "$fixture/src/a.txt")" = three ] || die "approved landing continuation did not update the worktree"
[ "$(git -C "$fixture" branch --show-current)" = main ] || die "assisted landing did not restore main"
ok "assisted execution pauses before branch creation and atomic landing"

echo "7 CLI lifecycle checks passed"
