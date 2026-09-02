#!/bin/sh
# Verify reach derivation, digest freshness, message emission, and
# trailer honesty.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
support="$root/skills/intent-brief/scripts/brief-support.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-brief-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false

mkdir -p "$fixture/docs" "$fixture/contracts" "$fixture/tests" "$fixture/other" "$fixture/.intent"
touch "$fixture/docs/domain.md" "$fixture/docs/architecture.md" "$fixture/docs/boundary-spec.md"
touch "$fixture/contracts/demo.schema" "$fixture/tests/demo_test.sh" "$fixture/other/thing.txt"
cat >"$fixture/.intent/ROUTES.yml" <<'EOF'
version: 1
routes:
  - scope: demo.unit
    paths: [contracts/demo.schema, tests/demo_test.sh]
    interfaces: [DemoContract]
    domain: [design:repo:docs/domain.md#demo]
    contracts: [contract:demo.boundary]
  - scope: other.area
    paths: [other]
    domain: [design:repo:docs/domain.md#other]
  - scope: ui.area
    paths: [uidir]
    domain: [design:repo:docs/domain.md#ui]
EOF
cat >"$fixture/.intent/CONTRACTS.yml" <<'EOF'
version: 1
contracts:
  - id: demo.boundary
    assertion: Demo consumers observe one stable boundary.
    authority: architecture:repo:docs/architecture.md#demo
    scope: demo.unit
    surfaces: [repo:contracts/demo.schema]
    material: [design:docs/boundary-spec.md]
    verifies: [test:tests/demo_test.sh::demo]
EOF
git -C "$fixture" add -A
git -C "$fixture" commit -qm seed

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "clean tree is REACH local"
ok "clean tree is REACH local"

echo x >>"$fixture/contracts/demo.schema"
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: bounded$' || die "single-scope single-contract diff is bounded"
printf '%s\n' "$out" | grep -q 'SCOPES: 1 — demo.unit' || die "matched scope is reported"
printf '%s\n' "$out" | grep -q 'DECLARED CONTRACTS: 1 — demo.boundary' || die "affected declared contract is reported"
ok "single-scope single-contract diff is REACH bounded"

echo x >>"$fixture/other/thing.txt"
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: bounded$' || die "an unrelated second scope does not open a probe-eligible contract"
ok "multi-scope work remains bounded when its contract is probe-eligible"
git -C "$fixture" checkout -q -- .

printf '# note\n' >>"$fixture/.intent/CONTRACTS.yml"
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: open$' || die "additive CONTRACTS.yml change is open via EXTENSION"
printf '%s\n' "$out" | grep -q '^STRUCTURAL:' || die "structural change is labeled"
printf '%s\n' "$out" | grep -q '^EXTENSION:' || die "additive record diff carries the EXTENSION fact"
ok "additive CONTRACTS.yml change is EXTENSION, not gated"
sed 's/one stable boundary/another boundary/' "$fixture/.intent/CONTRACTS.yml" >"$fixture/.intent/CONTRACTS.yml.tmp"
mv "$fixture/.intent/CONTRACTS.yml.tmp" "$fixture/.intent/CONTRACTS.yml"
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: gated$' || die "breaking CONTRACTS.yml change is gated"
ok "breaking CONTRACTS.yml change is REACH gated"
git -C "$fixture" checkout -q -- .

mkdir -p "$fixture/newarea"
echo x >"$fixture/newarea/one.txt"
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "one unrouted file in one directory stays local"
printf '%s\n' "$out" | grep -q '^UNROUTED: 1$' || die "unrouted count is reported"
ok "one unrouted file in one directory stays local"
rm -rf "$fixture/newarea"

mkdir -p "$fixture/appdir" "$fixture/styledir"
echo x >"$fixture/appdir/a.txt"
echo x >"$fixture/styledir/b.txt"
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "two derived boundaries with zero contracts collapse under a single executor"
printf '%s\n' "$out" | grep -q '^COLLAPSE:' && die "derived topology does not create lifecycle ceremony"
printf '%s\n' "$out" | grep -q '^BOUNDARIES: 2 — area.appdir area.styledir' || die "derived boundaries are named"
ok "two derived boundaries with zero contracts collapse to a direct unit"
rm -rf "$fixture/appdir" "$fixture/styledir"

mkdir -p "$fixture/appdir" "$fixture/styledir" "$fixture/zdir"
echo x >"$fixture/appdir/a.txt"
echo x >"$fixture/styledir/b.txt"
echo x >"$fixture/zdir/c.txt"
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "wide unrouted spread remains semantically local"
printf '%s\n' "$out" | grep -q '^SPREAD:' || die "spread topology is still reported"
ok "wide unrouted spread is topology, not governance"
rm -rf "$fixture/appdir" "$fixture/styledir" "$fixture/zdir"

out=$(cd "$fixture" && sh "$support" reach --paths appdir/a.txt spec/test_a.py)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "a fix and its test are one boundary"
printf '%s\n' "$out" | grep -q '^BOUNDARIES: 1 — area.appdir' || die "canonical test paths attach, never form their own boundary"
printf '%s\n' "$out" | grep -q '^COLLAPSE:' && die "test attachment needs no collapse"
ok "canonical test paths attach to the boundary they exercise"

out=$(cd "$fixture" && sh "$support" reach --paths .github/workflows/ci.yml backend/.env.example)
printf '%s\n' "$out" | grep -q '^BOUNDARIES: 2 — area.backend area.root' || die "hidden paths inherit parent and root boundaries during reach"
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "hidden paths remain ordinary unrouted work"
ok "reach classifies hidden paths under usable boundaries"

out=$(cd "$fixture" && sh "$support" reach --paths appdir/a.txt styledir/b.txt zdir/c.txt)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "--paths reports an unrouted intended touch set without escalating it"
out=$(cd "$fixture" && sh "$support" reach --paths contracts/demo.schema)
printf '%s\n' "$out" | grep -q '^REACH: bounded$' || die "--paths probe of one routed contract surface is bounded"
printf '%s\n' "$out" | grep -q 'SCOPES: 1 — demo.unit' || die "--paths probe reports the matched scope"
ok "--paths probes intended work without touching the tree"

out=$(cd "$fixture" && sh "$support" reach --paths other/thing.txt uidir/c.txt)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "multi-scope zero-contract work collapses under a single executor"
printf '%s\n' "$out" | grep -q '^COLLAPSE:' && die "multi-scope work needs no collapse mode"
printf '%s\n' "$out" | grep -q 'SCOPES: 2 — other.area ui.area' || die "collapsed reach still reports both scopes"
ok "multi-scope zero-contract work is a direct unit"

cat >"$fixture/.intent/config.yml" <<'EOF'
version: 1
escalation: agent
EOF
out=$(cd "$fixture" && sh "$support" reach --paths other/thing.txt uidir/c.txt)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "resolver authority does not change semantic reach"
ok "escalation authority does not change semantic reach"
rm -f "$fixture/.intent/config.yml"

out=$(cd "$fixture" && sh "$support" reach --paths other/thing.txt contracts/demo.schema)
printf '%s\n' "$out" | grep -q '^REACH: bounded$' || die "multi-scope work stays bounded while all affected contracts are probe-eligible"
ok "boundary count does not open a contract"

out=$(cd "$fixture" && sh "$support" probe --paths contracts/demo.schema)
printf '%s\n' "$out" | grep -q '^PROBE: demo.boundary ELIGIBLE — test:tests/demo_test.sh::demo$' || die "surface-only diff is probe-eligible with its verifiers listed"
printf '%s\n' "$out" | grep -q 'INELIGIBLE' && die "all-eligible probe reports no ineligible contract"
ok "surface-only diff is probe-eligible with its verifiers listed"

out=$(cd "$fixture" && sh "$support" verifiers --paths contracts/demo.schema)
printf '%s\n' "$out" | grep -q '^VERIFY: demo.boundary test:tests/demo_test.sh::demo$' || die "affected verifier locators are executable landing input"
ok "affected contract verifiers are emitted for atomic landing"

out=$(cd "$fixture" && sh "$support" probe --paths tests/demo_test.sh)
printf '%s\n' "$out" | grep -q 'INELIGIBLE (diff touches verifier tests/demo_test.sh)' || die "verifier edit forfeits the shortcut"
ok "editing a contract verifier forfeits the shortcut"

out=$(cd "$fixture" && sh "$support" probe --paths docs/boundary-spec.md)
printf '%s\n' "$out" | grep -q 'INELIGIBLE (diff touches defining material docs/boundary-spec.md)' || die "defining-material edit opens the boundary"
ok "editing defining material opens the boundary"

out=$(cd "$fixture" && sh "$support" probe --paths contracts/demo.schema .intent/CONTRACTS.yml)
printf '%s\n' "$out" | grep -q 'INELIGIBLE (.intent/CONTRACTS.yml changed)' || die "CONTRACTS.yml edit is structural, never probeable"
ok "CONTRACTS.yml edit is never probeable"

out=$(cd "$fixture" && sh "$support" probe --paths other/thing.txt)
[ -z "$out" ] || die "diff outside contract surfaces reaches no contract"
ok "diff outside contract surfaces reaches no contract"

mkdir -p "$fixture/intent-work/boards"
cat >"$fixture/intent-work/boards/demo.yml" <<'EOF'
version: 1
id: demo
goal: Demo plan.
integration_target: main
units:
  - id: web
    objective: Frontend.
    dependencies: []
    relies_on: [demo.boundary]
    surfaces: [apps/web]
EOF

out=$(cd "$fixture" && sh "$support" reach --paths docs/notes.md)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "isolated unrouted doc change stays local"
ok "isolated doc change is REACH local"

out=$(cd "$fixture" && sh "$support" reach --paths contracts/demo.schema)
printf '%s\n' "$out" | grep -q '^REACH: bounded$' || die "eligible contract surface is bounded"
printf '%s\n' "$out" | grep -q '^PROBE: demo.boundary ELIGIBLE' || die "bounded reach lists verifiers"
ok "surface-only change is REACH bounded with verifiers"

out=$(cd "$fixture" && sh "$support" reach --paths docs/boundary-spec.md)
printf '%s\n' "$out" | grep -q '^REACH: open$' || die "material change is REACH open"
printf '%s\n' "$out" | grep -q 'OPEN: demo.boundary (defining material docs/boundary-spec.md changed) — consumers: scope:demo.unit unit:web' || die "open boundary lists declared consumers"
ok "defining-material change is REACH open with consumers expanded"

out=$(cd "$fixture" && sh "$support" reach --paths .intent/CONTRACTS.yml)
printf '%s\n' "$out" | grep -q '^REACH: gated$' || die "contract records change is gated"
ok "one-line CONTRACTS.yml change is REACH gated"

out=$(cd "$fixture" && sh "$support" reach --paths appdir/a.txt styledir/b.txt zdir/c.txt)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "unadopted spread remains local"
printf '%s\n' "$out" | grep -q '^SPREAD:' || die "bootstrap fallback is labeled"
ok "unadopted spread remains direct"

out=$(cd "$fixture" && sh "$support" reach --paths other/thing.txt contracts/demo.schema docs/boundary-spec.md)
printf '%s\n' "$out" | grep -q '^REACH: open$' || die "multi-scope open work escalates"
printf '%s\n' "$out" | grep -q '^NEXT: intent-land' || die "open work still lands directly unless coordination is separately activated"
ok "open governance does not force coordination"

digest=$(cd "$fixture" && sh "$support" digest demo.unit | awk '{print $2}')
[ -n "$digest" ] || die "digest is emitted"
(cd "$fixture" && sh "$support" observe "$digest" demo.unit >/dev/null) || die "unchanged content is OBSERVED"
ok "unchanged governing content is OBSERVED"

sed 's/one stable boundary/a different boundary/' "$fixture/.intent/CONTRACTS.yml" >"$fixture/.intent/CONTRACTS.yml.tmp"
mv "$fixture/.intent/CONTRACTS.yml.tmp" "$fixture/.intent/CONTRACTS.yml"
if (cd "$fixture" && sh "$support" observe "$digest" demo.unit >/dev/null 2>&1); then
  die "changed contract content is STALE"
fi
ok "changed contract content is STALE"

out=$( (cd "$fixture" && sh "$support" observe --explain "$digest" demo.unit 2>&1) || true )
printf '%s\n' "$out" | grep -q '^STALE' || die "explain still reports STALE"
printf '%s\n' "$out" | grep -q '^EXPLAIN: changed id: demo.boundary$' || die "explain names the changed governing row"
ok "observe --explain names exactly the changed governing row"
git -C "$fixture" checkout -q -- .

msg=$(cd "$fixture" && sh "$support" message "land u1" --unit u1 --scope demo.unit)
printf '%s\n' "$msg" | grep -q '^Intent-Unit: u1$' || die "message emits the unit trailer"
printf '%s\n' "$msg" | grep -q '^Intent-Scope: demo.unit$' || die "message emits the scope trailer"
git -C "$fixture" checkout -qb unit/u1
echo change >>"$fixture/contracts/demo.schema"
git -C "$fixture" commit -qam "u1"
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/u1 -m "$msg"
units=$(git -C "$fixture" log -1 --format='%(trailers:key=Intent-Unit,valueonly)' HEAD | sed '/^$/d')
[ "$units" = "u1" ] || die "git parses the tool-owned trailer block"
(cd "$fixture" && sh "$support" trailer HEAD >/dev/null) || die "honest trailer claim passes"
ok "tool-owned message lands a parseable honest trailer"

if (cd "$fixture" && sh "$support" message "bad" --unit u9 >/dev/null 2>&1); then
  die "message with --unit but no --scope is rejected"
fi
ok "message with --unit but no --scope is rejected"

msg=$(cd "$fixture" && sh "$support" message "land seq" --unit s1 --unit s2 --scope demo.unit --scope other.area)
git -C "$fixture" checkout -qb unit/seq
echo change >>"$fixture/contracts/demo.schema"
echo change >>"$fixture/other/thing.txt"
git -C "$fixture" commit -qam "seq"
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/seq -m "$msg"
(cd "$fixture" && sh "$support" trailer HEAD >/dev/null) || die "multi-scope claim covers a multi-scope diff"
n=$(git -C "$fixture" log -1 --format='%(trailers:key=Intent-Unit,valueonly,separator=%x0a)' HEAD | sed '/^$/d' | wc -l | tr -d ' ')
[ "$n" = "2" ] || die "both unit trailers parse on one merge"
ok "sequential-run merge carries one trailer per unit and per scope"

msg=$(cd "$fixture" && sh "$support" message "land board" --unit web --scope demo.unit --board demo)
printf '%s\n' "$msg" | grep -q '^Intent-Board: demo$' || die "board message emits the board trailer"
printf '%s\n' "$msg" | grep -q '^Intent-Board-Digest: ' || die "board message emits the board digest"
printf '%s\n' "$msg" | grep -q '^Units:$' || die "board message emits the unit table"
printf '%s\n' "$msg" | grep -q '^  web$' || die "board message lists coordinated units"
ok "coordinated message carries board trailers and the unit table"

if (cd "$fixture" && sh "$support" message "land board" --board missing >/dev/null 2>&1); then
  die "message for an absent workboard is rejected"
fi
ok "message for an absent workboard is rejected"

git -C "$fixture" checkout -qb unit/u2
echo change >>"$fixture/other/thing.txt"
git -C "$fixture" commit -qam "u2"
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/u2 -m "land u2

Intent-Unit: u2
Intent-Scope: demo.unit"
if (cd "$fixture" && sh "$support" trailer HEAD >/dev/null 2>&1); then
  die "false trailer claim fails"
fi
ok "false trailer claim fails"

echo z >"$fixture/zfile"
git -C "$fixture" add zfile
git -C "$fixture" commit -qm "no trailer"
if (cd "$fixture" && sh "$support" trailer HEAD >/dev/null 2>&1); then
  die "missing trailer fails"
fi
ok "missing trailer fails"

out=$(cd "$fixture" && sh "$support" reach --paths contracts/demo.schema)
printf '%s\n' "$out" | grep -q '^NEXT: intent-land' || die "bounded work routes to intent-land"
out=$(cd "$fixture" && sh "$support" reach --paths docs/notes.md)
printf '%s\n' "$out" | grep -q '^NEXT: intent-land' || die "local work routes to intent-land"
ok "NEXT routes local and bounded work to intent-land"

out=$(cd "$fixture" && sh "$support" reach --paths appdir/a.txt styledir/b.txt zdir/c.txt)
printf '%s\n' "$out" | grep -q '^NEXT: intent-land' || die "spread remains direct by default"
printf '%s\n' "$out" | grep -q 'intent-seed' && die "reach never offers seeding; the offer lives in the landing report"
ok "NEXT keeps spread direct; seeding is never offered at intake"

out=$(cd "$fixture" && sh "$support" reach --paths docs/boundary-spec.md)
printf '%s\n' "$out" | grep -q '^NEXT: intent-land' || die "open work routes to intent-land"
out=$(cd "$fixture" && sh "$support" reach --paths other/thing.txt contracts/demo.schema docs/boundary-spec.md)
printf '%s\n' "$out" | grep -q '^NEXT: intent-land' || die "multi-scope open work routes to intent-land"
ok "NEXT never confuses governance with coordination"

printf '%s\n' "$out" | tail -1 | grep -q '^REACH:' || die "REACH stays the terminal verdict line"
ok "REACH stays the terminal verdict line"

out=$(cd "$fixture" && sh "$support" rows demo.unit)
printf '%s\n' "$out" | grep -q '^DOMAIN demo.unit — design:repo:docs/domain.md#demo$' || die "rows emits route domain pointers"
printf '%s\n' "$out" | grep -q '^CONTRACT demo.boundary — Demo consumers observe one stable boundary. (verify: test:tests/demo_test.sh::demo)$' || die "rows emits the contract assertion with verifiers"
printf '%s\n' "$out" | grep -q '^ROWS: 2$' || die "rows counts the governing rows"
ok "rows compiles labeled governing rows"

mkdir -p "$fixture/.intent/decisions/demo" "$fixture/intent-work/leases"
cat >"$fixture/.intent/decisions/demo/abc1234-1.yml" <<'EOF'
version: 1
decisions:
  - id: abc1234-1
    decision: Demo stays conversational.
    kind: domain_direction
    authority: user_explicit
    status: active
    source: user:task:demo#turn-1
    scope: demo.unit
    introduced: abc1234
EOF
cat >"$fixture/intent-work/leases/u9.yml" <<'EOF'
version: 1
unit: u9
owner: unit/u9
branch: unit/u9
scope: demo.unit
created: 2026-01-01T00:00:00Z
renewed: 2026-01-01T00:00:00Z
expires: 2026-01-01T02:00:00Z
EOF
out=$(cd "$fixture" && sh "$support" rows demo.unit)
printf '%s\n' "$out" | grep -q '^DECISION abc1234-1 (domain_direction) — Demo stays conversational.$' || die "rows includes active decisions"
printf '%s\n' "$out" | grep -q '^LEASE u9 — demo.unit$' || die "rows includes intersecting live leases"
printf '%s\n' "$out" | grep -q '^ROWS: 4$' || die "rows counts decisions and leases"
ok "rows includes active decisions and intersecting leases"
rm -rf "$fixture/.intent/decisions" "$fixture/intent-work/leases"

cat >>"$fixture/.intent/ROUTES.yml" <<'EOF'
  - scope: big.area
    paths: [bigdir]
    domain: [design:repo:d1, design:repo:d2, design:repo:d3, design:repo:d4, design:repo:d5, design:repo:d6, design:repo:d7, design:repo:d8, design:repo:d9]
EOF
out=$(cd "$fixture" && sh "$support" rows big.area)
printf '%s\n' "$out" | grep -q '^ROWS: 9 — exceeds the eight-row cap' || die "nine rows trip the cap"
ok "nine or more rows trip the eight-row cap"
git -C "$fixture" checkout -q -- .intent/ROUTES.yml

out=$(cd "$fixture" && sh "$support" map)
printf '%s\n' "$out" | grep -q '^BOUNDARY: area.contracts contracts$' || die "map derives boundaries from top-level names"
printf '%s\n' "$out" | grep -q '^BOUNDARY: area.docs docs$' || die "map lists every top-level seam"
printf '%s\n' "$out" | grep -q '^ATTACH: tests' || die "map marks canonical test directories as attaching"
printf '%s\n' "$out" | grep -q 'area.tests' && die "a test directory never becomes its own boundary"
ok "map derives boring name-based boundaries with test attachment"

cat >>"$fixture/.intent/CONTRACTS.yml" <<'EOF'
  - id: demo.extra
    assertion: A second boundary holds.
    authority: architecture:repo:docs/architecture.md#extra
    scope: demo.unit
    surfaces: [repo:docs/domain.md]
    verifies: [test:tests/demo_test.sh::extra]
EOF
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^EXTENSION:' || die "purely additive record diff is an EXTENSION fact"
printf '%s\n' "$out" | grep -q '^REACH: open$' || die "extension keeps the full open path, not the gate"
ok "additive contract-record diff is EXTENSION and REACH open"
git -C "$fixture" checkout -q -- .

git -C "$fixture" mv contracts contractsv2
sed 's|contracts/demo.schema|contractsv2/demo.schema|g' "$fixture/.intent/CONTRACTS.yml" >"$fixture/.intent/CONTRACTS.yml.tmp"
mv "$fixture/.intent/CONTRACTS.yml.tmp" "$fixture/.intent/CONTRACTS.yml"
git -C "$fixture" add -A
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^MOVE:' || die "rename-following record diff is a MOVE fact"
printf '%s\n' "$out" | grep -q '^REACH: open$' || die "move keeps the full open path, not the gate"
ok "rename-following contract-record diff is MOVE and REACH open"
git -C "$fixture" reset -q HEAD -- . && git -C "$fixture" checkout -q -- . && rm -rf "$fixture/contractsv2"

sed 's/one stable boundary/a rewritten boundary/' "$fixture/.intent/CONTRACTS.yml" >"$fixture/.intent/CONTRACTS.yml.tmp"
mv "$fixture/.intent/CONTRACTS.yml.tmp" "$fixture/.intent/CONTRACTS.yml"
out=$(cd "$fixture" && sh "$support" reach)
printf '%s\n' "$out" | grep -q '^REACH: gated$' || die "rewriting an assertion stays gated"
printf '%s\n' "$out" | grep -q '^EXTENSION:\|^MOVE:' && die "a breaking diff earns no autonomous fact line"
ok "breaking contract-record diff stays REACH gated"
git -C "$fixture" checkout -q -- .

git -C "$fixture" checkout -qb unit/u3
mkdir -p "$fixture/newarea"
echo n >"$fixture/newarea/n.txt"
git -C "$fixture" add newarea
git -C "$fixture" commit -qm "u3"
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/u3 -m "$(cd "$fixture" && sh "$support" message 'land u3' --unit u3 --scope area.newarea)"
(cd "$fixture" && sh "$support" trailer HEAD >/dev/null) || die "derived-boundary claim verifies by containment"
ok "trailer verifies a derived-boundary claim by containment"

git -C "$fixture" checkout -qb unit/dotfiles
echo hidden >"$fixture/newarea/.env.example"
echo root >"$fixture/.dockerignore"
git -C "$fixture" add newarea/.env.example .dockerignore
git -C "$fixture" commit -qm "dotfiles"
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/dotfiles -m "$(cd "$fixture" && sh "$support" message 'land dotfiles' --unit dotfiles --scope area.newarea --scope area.root)"
(cd "$fixture" && sh "$support" trailer HEAD >/dev/null) || die "dotfiles inherit parent and root boundaries"
out=$(cd "$fixture" && sh "$support" map)
printf '%s\n' "$out" | grep -q '^BOUNDARY: area.root \.$' || die "root dotfiles make area.root addressable"
ok "nested and root dotfiles are addressable"

git -C "$fixture" checkout -qb unit/u4
echo n2 >>"$fixture/newarea/n.txt"
git -C "$fixture" commit -qam "u4"
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/u4 -m "land u4

Intent-Unit: u4
Intent-Scope: area.elsewhere"
if (cd "$fixture" && sh "$support" trailer HEAD >/dev/null 2>&1); then
  die "an uncontained derived claim fails"
fi
ok "an uncontained derived claim fails containment"

digest=$(cd "$fixture" && sh "$support" digest demo.unit | awk '{print $2}')
cat >"$fixture/.intent/config.yml" <<'EOF'
version: 1
escalation: agent
EOF
(cd "$fixture" && sh "$support" observe "$digest" demo.unit >/dev/null) || die "operational config made governance stale"
ok "operational config is excluded from the governance digest"
rm -f "$fixture/.intent/config.yml"

echo "51 brief-support checks passed"
