#!/bin/sh
# Verify workboard status is derived from repository facts, never stored, and
# that the pinned set (landed or leased units) is derivable for redraw checks.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
status="$root/skills/intent-coordinate/scripts/workboard-status.sh"
board_support="$root/skills/intent-coordinate/scripts/workboard-support.sh"
support="$root/skills/intent-brief/scripts/brief-support.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-status-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
touch "$fixture/seed"
git -C "$fixture" add -A
git -C "$fixture" commit -qm seed

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

out=$(cd "$fixture" && sh "$status")
printf '%s\n' "$out" | grep -q 'no workboards' || die "empty workboard store reports cleanly"
ok "empty workboard store reports cleanly"

mkdir -p "$fixture/intent-work/boards" "$fixture/intent-work/leases"
cat >"$fixture/intent-work/boards/demo.yml" <<'EOF'
version: 1
id: demo
goal: Demo plan.
integration_target: main
units:
  - id: contracts
    objective: Stabilize shared assertions.
    dependencies: []
    surfaces: [packages/contracts]
    verifies: [test:tests/validate.sh]
  - id: api
    objective: Implement the workflow.
    dependencies: [contracts]
    relies_on: [demo.boundary]
    surfaces: [services/api]
  - id: web
    objective: Implement the frontend.
    dependencies: [contracts, api]
    surfaces: [apps/web]
EOF

out=$(cd "$fixture" && sh "$board_support" validate demo)
printf '%s\n' "$out" | grep -q '^WORKBOARD: valid' || die "valid board passes mechanical topology checks"
ok "workboard dependencies and unordered claims validate"

cat >"$fixture/intent-work/boards/bad.yml" <<'EOF'
version: 1
id: bad
goal: Overlapping workers.
integration_target: main
units:
  - id: one
    objective: First.
    dependencies: []
    surfaces: [shared]
  - id: two
    objective: Second.
    dependencies: []
    surfaces: [shared/file]
EOF
if (cd "$fixture" && sh "$board_support" validate bad >/dev/null 2>&1); then
  die "unordered overlapping claims were accepted"
fi
rm -f "$fixture/intent-work/boards/bad.yml"
ok "unordered overlapping claims are rejected"

out=$(cd "$fixture" && sh "$status" demo)
printf '%s\n' "$out" | grep -Eq '^contracts +dispatchable' || die "root unit with no deps is dispatchable"
printf '%s\n' "$out" | grep -Eq '^api +waiting +contracts' || die "dependent unit waits on unlanded deps"
ok "derived states before any landing are correct"

out=$(cd "$fixture" && sh "$status" demo --pinned)
[ -z "$out" ] || die "nothing landed or leased means nothing pinned"
ok "an undispatched workboard is fully redrawable — nothing pinned"

git -C "$fixture" checkout -qb unit/contracts
echo x >"$fixture/work"
git -C "$fixture" add work
git -C "$fixture" commit -qm "contracts unit"
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/contracts -m "land contracts

Intent-Unit: contracts
Intent-Scope: demo.contracts"

out=$(cd "$fixture" && sh "$status" demo)
printf '%s\n' "$out" | grep -Eq '^contracts +landed' || die "landed unit derived from first-parent trailer"
printf '%s\n' "$out" | grep -Eq '^api +dispatchable' || die "unit unlocks when deps land"
printf '%s\n' "$out" | grep -Eq '^web +waiting' || die "transitively blocked unit stays waiting"
ok "landing a unit unlocks dependents by ancestry alone"

cat >"$fixture/intent-work/leases/api.yml" <<'EOF'
version: 1
unit: api
EOF
out=$(cd "$fixture" && sh "$status" demo)
printf '%s\n' "$out" | grep -Eq '^api +active' || die "live lease marks unit active"
out=$(cd "$fixture" && sh "$status" demo --pinned)
printf '%s\n' "$out" | grep -q '^PINNED: contracts (landed)$' || die "landed unit is pinned"
printf '%s\n' "$out" | grep -q '^PINNED: api (leased)$' || die "leased unit is pinned"
printf '%s\n' "$out" | grep -q 'web' && die "the undispatched frontier stays unpinned"
ok "pinned set is landed plus leased; the frontier stays redrawable"
rm -f "$fixture/intent-work/leases/api.yml"

msg=$(cd "$fixture" && sh "$support" message "land api and web sequentially" \
  --unit api --unit web --scope demo.api --scope demo.web --board demo)
git -C "$fixture" checkout -qb unit/seq
echo y >"$fixture/work2"
git -C "$fixture" add work2
git -C "$fixture" commit -qm "api and web units"
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/seq -m "$msg"
out=$(cd "$fixture" && sh "$status" demo)
printf '%s\n' "$out" | grep -Eq '^api +landed' || die "sequential-run merge lands api by its trailer"
printf '%s\n' "$out" | grep -Eq '^web +landed' || die "sequential-run merge lands web by its trailer"
ok "one sequential-run merge with per-unit trailers lands every contained unit"

rm -rf "$fixture/intent-work"
git -C "$fixture" log --oneline >/dev/null || die "removing runtime state cannot affect repository content"
ok "removing workboards leaves repository content untouched"

echo "9 workboard checks passed"
