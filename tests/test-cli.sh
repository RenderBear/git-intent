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

mkdir -p "$fixture/checks"
cat >"$fixture/checks/fail.sh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$fixture/checks/fail.sh"
git -C "$fixture" add checks/fail.sh
git -C "$fixture" commit -qm "add failing check"
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
architecture_reviews: []
checks: [command:checks/fail.sh]
EOF
if out=$(cd "$fixture" && "$cli" task finish failed-flow --assessment "$assessment" 2>&1); then
  die "failed verifier advanced the lifecycle"
fi
printf '%s\n' "$out" | grep -q '^CHECK: running — command:checks/fail.sh$' || die "failed verifier output was hidden"
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
printf '%s\n' "$json" | grep -q '\\nREACH: local' || die "JSON result did not preserve mechanical output"
ok "read-only commands expose one machine-readable envelope"

mkdir -p "$fixture/.invariant"
cat >"$fixture/.invariant/config.yml" <<'EOF'
version: 1
execution: assisted
integration_branch: main
EOF
git -C "$fixture" add .invariant/config.yml
git -C "$fixture" commit -qm "configure assisted execution"

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
architecture_reviews: []
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

echo "6 CLI lifecycle checks passed"
