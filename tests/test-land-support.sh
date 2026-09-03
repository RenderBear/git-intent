#!/bin/sh
# Verify work-branch-only landing, durable-boundary disposition, exact-tree
# review, checks, coordinated lease authentication, and atomic ref updates.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
land="$root/skills/intent-land/scripts/land-support.sh"
lease="$root/skills/intent-coordinate/scripts/lease-support.sh"
runtime_support="$root/skills/intent-coordinate/scripts/runtime-support.sh"
brief_support="$root/skills/intent-brief/scripts/brief-support.sh"
audit_support="$root/skills/intent-audit/scripts/audit-support.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-land-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$fixture/.intent/audits" "$fixture/docs" "$fixture/src" "$fixture/ui" "$fixture/checks"
printf '# Architecture\n' >"$fixture/docs/architecture.md"
printf 'one\n' >"$fixture/src/a.txt"
printf 'ui\n' >"$fixture/ui/view.txt"
cat >"$fixture/checks/verify.sh" <<'EOF'
#!/bin/sh
test "$(cat src/a.txt)" != broken
EOF
chmod +x "$fixture/checks/verify.sh"
cat >"$fixture/.intent/config.yml" <<'EOF'
version: 1
resolution: assisted
EOF
cat >"$fixture/.intent/DOMAINS.yml" <<'EOF'
version: 1
domains:
  - id: source
    description: Source behavior.
    authority: user:task:test#turn-1
  - id: consumer
    description: Consumes source behavior.
    authority: user:task:test#turn-1
EOF
cat >"$fixture/.intent/CONTRACTS.yml" <<'EOF'
version: 1
contracts:
  - id: source.protocol.v1
    assertion: Source behavior remains consumable.
    authority: user:task:test#turn-1
    between: [source, consumer]
    surfaces: [repo:src]
    material: [architecture:docs/architecture.md]
    verifies: [command:checks/verify.sh]
EOF
cat >"$fixture/.intent/CONSTRAINTS.yml" <<'EOF'
version: 1
constraints:
  - id: source.layout
    assertion: Source behavior remains inside the source domain.
    authority: user:task:test#turn-1
    applies_to: [source]
    surfaces: [repo:src]
    material: [architecture:docs/architecture.md]
EOF
git -C "$fixture" add -A
git -C "$fixture" commit -qm seed

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }
start_branch() { git -C "$fixture" switch -qc "$1" main; }
finish_branch() {
  git -C "$fixture" add -A
  git -C "$fixture" commit -qm "$1"
  git -C "$fixture" switch -q main
}

printf 'direct\n' >"$fixture/ui/view.txt"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" direct "direct mutation" --unit direct --scope area.ui \
    --paths ui/view.txt --boundary-review no-record >/dev/null 2>&1); then
  die "direct landing advanced a born integration branch"
fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "rejected direct landing moved target"
git -C "$fixture" checkout -q -- ui/view.txt
ok "born integration branches reject direct landing"

start_branch intent/work/u1
printf 'two\n' >"$fixture/src/a.txt"
finish_branch "source update"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" merge intent/work/u1 "missing boundary review" --unit u1 \
    --scope area.src --domain source --reviewed constraint:source.layout >/dev/null 2>&1); then
  die "merge landed without a boundary disposition"
fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "missing boundary review moved target"
if (cd "$fixture" && sh "$land" merge intent/work/u1 "unreviewed" --unit u1 --scope area.src \
    --domain source --boundary-review no-record >/dev/null 2>&1); then
  die "semantic constraint landed without review"
fi
out=$(cd "$fixture" && sh "$land" merge intent/work/u1 "reviewed source" --unit u1 \
  --scope area.src --domain source --reviewed constraint:source.layout --boundary-review no-record)
printf '%s\n' "$out" | grep -q '^CHECK: running — command:checks/verify.sh$' || die "contract verifier did not run"
printf '%s\n' "$out" | grep -q '^BOUNDARY-REVIEW: no-record$' || die "no-record disposition missing"
printf '%s\n' "$out" | grep -q '^LANDED:' || die "reviewed candidate did not land"
git -C "$fixture" log -1 --format='%(trailers:key=Intent-Boundary,valueonly)' | grep -qxF no-record ||
  die "boundary disposition was not preserved in the landing commit"
ok "merge requires boundary disposition and applicable semantic review"

start_branch intent/work/u2
printf 'broken\n' >"$fixture/src/a.txt"
finish_branch "broken source"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" merge intent/work/u2 "broken" --unit u2 --scope area.src \
    --domain source --reviewed constraint:source.layout --boundary-review no-record >/dev/null 2>&1); then
  die "broken contract landed"
fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "failed verifier moved target"
[ "$(git -C "$fixture" show intent/work/u2:src/a.txt)" = broken ] || die "failed landing lost branch work"
ok "failed verification leaves the integration ref unchanged and branch work recoverable"

start_branch intent/work/ui
printf 'changed\n' >"$fixture/ui/view.txt"
finish_branch "simple UI"
out=$(cd "$fixture" && sh "$land" merge intent/work/ui "simple UI" --unit ui --scope area.ui \
  --boundary-review no-record)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "simple UI landing gained governance"
ok "simple local work remains low-governance while using a work branch"

start_branch intent/work/migrations
mkdir -p "$fixture/migrations"
printf 'create table example(id integer);\n' >"$fixture/migrations/001.sql"
finish_branch "add migrations"
out=$(cd "$fixture" && sh "$land" merge intent/work/migrations "add migrations" --unit migrations \
  --scope area.migrations --boundary-review no-record)
printf '%s\n' "$out" | grep -q '^TOPOLOGY-NEW: area.migrations$' || die "new topology was not reported"
ok "new mechanical topology prompts review without inventing governance"

start_branch intent/work/audit
printf 'audited\n' >"$fixture/ui/view.txt"
frame=$(cd "$fixture" && sh "$audit_support" scope --paths ui)
audit_ground=$(printf '%s\n' "$frame" | sed -n 's/^GROUND: //p')
audit_tree=$(printf '%s\n' "$frame" | sed -n 's/^TREE: //p')
cat >"$fixture/.intent/audits/ui-boundary.yml" <<EOF
version: 1
id: ui-boundary
ground: $audit_ground
tree: $audit_tree
mode: scope
paths: [ui]
findings:
  - id: ui-result
    summary: UI behavior needs no durable governance.
    evidence: [repo:ui]
    proposed: none
    disposition: needs-authority
EOF
finish_branch "audit UI boundary"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" merge intent/work/audit "unresolved audit" --unit audit \
    --scope area.ui --boundary-review audit:ui-boundary >/dev/null 2>&1); then
  die "unresolved audit cleared boundary review"
fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "unresolved audit moved target"
git -C "$fixture" switch -q intent/work/audit
sed 's/disposition: needs-authority/disposition: no-action/' "$fixture/.intent/audits/ui-boundary.yml" >"$fixture/.intent/audits/ui-boundary.tmp"
mv "$fixture/.intent/audits/ui-boundary.tmp" "$fixture/.intent/audits/ui-boundary.yml"
finish_branch "resolve UI audit"
out=$(cd "$fixture" && sh "$land" merge intent/work/audit "audited UI" --unit audit \
  --scope area.ui --boundary-review audit:ui-boundary)
printf '%s\n' "$out" | grep -q '^BOUNDARY-REVIEW: audit:ui-boundary' || die "conclusive audit disposition missing"
ok "only a fresh conclusive scoped audit clears boundary review"

start_branch intent/work/governance
cat >>"$fixture/.intent/CONSTRAINTS.yml" <<'EOF'
  - id: source.naming
    assertion: Source names remain explicit.
    authority: user:task:test#turn-2
    applies_to: [source]
    material: [architecture:docs/architecture.md]
EOF
finish_branch "adopt naming constraint"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" merge intent/work/governance "unresolved adoption" --unit govern \
    --scope area.root --domain source --reviewed constraint:source.layout \
    --reviewed constraint:source.naming --boundary-review recorded \
    --governance constraint:source.naming >/dev/null 2>&1); then
  die "additive governance landed without resolved authority"
fi
if (cd "$fixture" && sh "$land" merge intent/work/governance "wrong disposition" --unit govern \
    --scope area.root --domain source --reviewed constraint:source.layout \
    --reviewed constraint:source.naming --boundary-review no-record --allow-open >/dev/null 2>&1); then
  die "governance change accepted a no-record disposition"
fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "unresolved governance moved target"
out=$(cd "$fixture" && sh "$land" merge intent/work/governance "adopt naming" --unit govern \
  --scope area.root --domain source --reviewed constraint:source.layout \
  --reviewed constraint:source.naming --boundary-review recorded \
  --governance constraint:source.naming --allow-open)
printf '%s\n' "$out" | grep -q '^GOVERNANCE: additive record establishment$' || die "additive governance was not classified open"
printf '%s\n' "$out" | grep -q '^BOUNDARY-REVIEW: recorded — constraint:source.naming$' || die "recorded governance disposition missing"
git -C "$fixture" log -1 --format='%(trailers:key=Intent-Governance,valueonly)' |
  grep -qxF constraint:source.naming || die "governance reference was not preserved in the landing commit"
ok "governance changes require authority and accepted record references"

start_branch intent/work/worker
printf 'worker\n' >"$fixture/src/b.txt"
finish_branch "worker"
ground=$(git -C "$fixture" rev-parse HEAD)
source_digest=$(cd "$fixture" && sh "$brief_support" digest source | sed -n 's/^DIGEST: //p')
runtime=$(cd "$fixture" && sh "$runtime_support" ensure)
mkdir -p "$runtime/plans"
cat >"$runtime/plans/bundle.yml" <<EOF
version: 1
id: bundle
goal: Land parallel source work.
integration_target: main
integration_ground: $ground
domains: [source]
governing_digest: $source_digest
units:
  - id: worker
    objective: Add source worker output.
    dependencies: []
    paths: [src/b.txt]
    verifies: [command:checks/verify.sh]
  - id: followup
    objective: Follow up independently.
    dependencies: [worker]
    paths: [ui/followup.txt]
    verifies: [command:checks/verify.sh]
EOF
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" merge intent/work/worker "missing lease" --unit worker \
    --scope area.src --domain source --reviewed constraint:source.layout \
    --reviewed constraint:source.naming --boundary-review no-record --plan bundle >/dev/null 2>&1); then
  die "coordinated landing without lease succeeded"
fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "missing lease moved target"
(cd "$fixture" && sh "$lease" create worker --scope area.src --paths src/b.txt --domains source \
  --digest "$source_digest" --branch intent/work/worker --integration-target main >/dev/null)
out=$(cd "$fixture" && sh "$land" merge intent/work/worker "land worker" --unit worker \
  --scope area.src --domain source --reviewed constraint:source.layout \
  --reviewed constraint:source.naming --boundary-review no-record --plan bundle)
printf '%s\n' "$out" | grep -q '^LANDED:' || die "fresh matching lease did not land"
[ ! -e "$runtime/leases/worker.yml" ] || die "landed lease was not released"
[ -f "$runtime/plans/bundle.yml" ] || die "incomplete plan was removed"
ok "matching coordinated lease is authenticated and released"

unborn="$fixture/unborn"
mkdir -p "$unborn"
git -C "$unborn" init -qb main
git -C "$unborn" config user.name test
git -C "$unborn" config user.email test@example.com
git -C "$unborn" config commit.gpgsign false
printf '# New repository\n' >"$unborn/README.md"
out=$(cd "$unborn" && sh "$land" direct "initial commit" --unit initial --scope area.root \
  --paths README.md --boundary-review no-record)
printf '%s\n' "$out" | grep -q '^LANDED:' || die "unborn direct landing failed"
ok "direct landing remains available only for an unborn integration branch"

echo "9 landing policy checks passed"
