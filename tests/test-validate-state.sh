#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
checker="$root/skills/intent-brief/scripts/validate-state.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -q
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
mkdir -p "$fixture/docs" "$fixture/contracts" "$fixture/tests" "$fixture/.github"
touch "$fixture/seed" "$fixture/docs/domain.md" "$fixture/docs/architecture.md"
touch "$fixture/contracts/demo.schema" "$fixture/tests/demo_test.sh" "$fixture/.github/CODEOWNERS"
chmod +x "$fixture/tests/demo_test.sh"
git -C "$fixture" add .
git -C "$fixture" commit -qm seed
sha=$(git -C "$fixture" rev-parse HEAD)
short=$(git -C "$fixture" rev-parse --short HEAD)
id="$short-1"

mkdir -p "$fixture/.intent/decisions/demo"

write_routes() {
  cat >"$fixture/.intent/ROUTES.yml" <<EOF
version: 1
routes:
  - scope: demo.unit
    paths: [contracts/demo.schema, tests/demo_test.sh]
    interfaces: [DemoContract]
    domain: [design:repo:docs/domain.md#demo]
    architecture: [architecture:repo:docs/architecture.md#demo]
    contracts: [contract:demo.boundary]
    owners: [codeowners:.github/CODEOWNERS#demo]
EOF
}

write_contracts() {
  verifier=${1:-test:tests/demo_test.sh::demo}
  cat >"$fixture/.intent/CONTRACTS.yml" <<EOF
version: 1
contracts:
  - id: demo.boundary
    assertion: Demo consumers observe one stable boundary.
    authority: architecture:repo:docs/architecture.md#demo
    scope: demo.unit
    surfaces: [repo:contracts/demo.schema]
    material: [schema:contracts/demo.schema]
    verifies: [$verifier]
EOF
}

write_decision() {
  kind=$1
  authority=$2
  status=$3
  source=$4
  cat >"$fixture/.intent/decisions/demo/$id.yml" <<EOF
version: 1
decisions:
  - id: $id
    decision: The current domain direction remains explicit.
    kind: $kind
    authority: $authority
    status: $status
    source: $source
    scope: demo.unit
    introduced: $sha
EOF
}

stage_intent() { git -C "$fixture" add -A .intent; }

expect_pass() {
  name=$1
  if ! (cd "$fixture" && sh "$checker" >/dev/null); then
    echo "not ok - $name"
    (cd "$fixture" && sh "$checker") || true
    exit 1
  fi
  echo "ok - $name"
}

expect_pass_landing() {
  name=$1
  if ! (cd "$fixture" && sh "$checker" --landing >/dev/null); then
    echo "not ok - $name"
    (cd "$fixture" && sh "$checker" --landing) || true
    exit 1
  fi
  echo "ok - $name"
}

expect_fail() {
  name=$1
  if (cd "$fixture" && sh "$checker" >/dev/null 2>&1); then
    echo "not ok - $name"; exit 1
  fi
  echo "ok - $name"
}

expect_fail_landing() {
  name=$1
  if (cd "$fixture" && sh "$checker" --landing >/dev/null 2>&1); then
    echo "not ok - $name"; exit 1
  fi
  echo "ok - $name"
}

write_contracts
write_routes
write_decision domain_direction user_explicit active user:task:test/current#turn-1
stage_intent
expect_pass "routes, critical contracts, and per-decision active state are valid"

sed 's/    domain:/    product:/' "$fixture/.intent/ROUTES.yml" >"$fixture/.intent/ROUTES.yml.tmp"
mv "$fixture/.intent/ROUTES.yml.tmp" "$fixture/.intent/ROUTES.yml"
stage_intent
expect_fail "v1 routes use domain vocabulary"
write_routes; stage_intent

sed '/    paths:/d; /    interfaces:/d' "$fixture/.intent/ROUTES.yml" >"$fixture/.intent/ROUTES.yml.tmp"
mv "$fixture/.intent/ROUTES.yml.tmp" "$fixture/.intent/ROUTES.yml"
stage_intent
expect_fail "routes require path or interface matchers"
write_routes; stage_intent

sed 's|docs/domain.md|docs/missing.md|' "$fixture/.intent/ROUTES.yml" >"$fixture/.intent/ROUTES.yml.tmp"
mv "$fixture/.intent/ROUTES.yml.tmp" "$fixture/.intent/ROUTES.yml"
stage_intent
expect_fail "repository-backed route targets must resolve"
write_routes; stage_intent

sed 's|contracts/demo.schema, tests/demo_test.sh|contracts/demo.schema, planned/new_area.py|' \
  "$fixture/.intent/ROUTES.yml" >"$fixture/.intent/ROUTES.yml.tmp"
mv "$fixture/.intent/ROUTES.yml.tmp" "$fixture/.intent/ROUTES.yml"
stage_intent
expect_pass "planned route paths are allowed before they exist"
expect_fail_landing "planned route paths must exist at landing"
write_routes; stage_intent

sed 's|contract:demo.boundary|contract:demo.missing|' "$fixture/.intent/ROUTES.yml" >"$fixture/.intent/ROUTES.yml.tmp"
mv "$fixture/.intent/ROUTES.yml.tmp" "$fixture/.intent/ROUTES.yml"
stage_intent
expect_fail "routes must reference known semantic contracts"
write_routes; stage_intent

printf '    change_policy: explicit\n' >>"$fixture/.intent/CONTRACTS.yml"
stage_intent
expect_fail "critical contract records reject redundant policy bookkeeping"
write_contracts test:tests/missing_test.sh::demo
stage_intent
expect_fail "contract verifiers must resolve"
write_contracts command:tests/demo_test.sh
stage_intent
expect_pass "executable command verifiers are accepted"
write_contracts
sed 's|surfaces: \[repo:contracts/demo.schema\]|surfaces: [contracts/demo.schema]|' "$fixture/.intent/CONTRACTS.yml" >"$fixture/.intent/CONTRACTS.yml.tmp"
mv "$fixture/.intent/CONTRACTS.yml.tmp" "$fixture/.intent/CONTRACTS.yml"
stage_intent
expect_fail "contract surfaces require repo: locators"
write_contracts
sed 's|material: \[schema:contracts/demo.schema\]|material: [schema:contracts/missing.schema]|' "$fixture/.intent/CONTRACTS.yml" >"$fixture/.intent/CONTRACTS.yml.tmp"
mv "$fixture/.intent/CONTRACTS.yml.tmp" "$fixture/.intent/CONTRACTS.yml"
stage_intent
expect_fail "contract defining material must resolve"
write_contracts
stage_intent
expect_pass "critical contract assertion, authority, surfaces, material, and verifier are valid"

cat >>"$fixture/.intent/ROUTES.yml" <<EOF
  - scope: demo.unit
    paths: [contracts/demo.schema]
    interfaces: [DemoContract]
    contracts: [contract:demo.boundary]
EOF
stage_intent
expect_fail "route scopes are unique"
write_routes; stage_intent

write_decision implementation_choice implementation active commit:$sha
stage_intent
expect_fail "implementation authority cannot become active"

write_decision wrong_kind user_explicit active user:task:test/current#turn-1
stage_intent
expect_fail "decision kind is validated"

write_decision domain_direction user_explicit proposed user:task:test/current#turn-1
stage_intent
expect_fail "active store requires active status"

write_decision domain_direction user_explicit active user:task:test/current#turn-1
printf '    unknown_field: no\n' >>"$fixture/.intent/decisions/demo/$id.yml"
stage_intent
expect_fail "unknown decision fields are rejected"
write_decision domain_direction user_explicit active user:task:test/current#turn-1; stage_intent

mkdir -p "$fixture/.intent/decisions/other"
mv "$fixture/.intent/decisions/demo/$id.yml" "$fixture/.intent/decisions/other/$id.yml"
stage_intent
expect_fail "active decision directory matches semantic scope root"
mv "$fixture/.intent/decisions/other/$id.yml" "$fixture/.intent/decisions/demo/$id.yml"
rmdir "$fixture/.intent/decisions/other"
stage_intent

mkdir -p "$fixture/.intent/proposals/demo"
cat >"$fixture/.intent/proposals/demo/$short-2.yml" <<EOF
version: 1
decisions:
  - id: $short-2
    decision: A concurrent implementation choice is under review.
    kind: implementation_choice
    authority: implementation
    status: proposed
    source: commit:$sha
    scope: demo.unit
    introduced: $sha
    observed_ids: [$id]
EOF
stage_intent
expect_pass "concurrent implementation proposal remains advisory"

rm -f "$fixture/.intent/proposals/demo/$short-2.yml"
rmdir "$fixture/.intent/proposals/demo" "$fixture/.intent/proposals"
mkdir -p "$fixture/.intent/exceptions"
cat >"$fixture/.intent/exceptions/demo.yml" <<EOF
version: 1
unit: demo
exceptions:
  - requirement: repo:docs/domain.md#demo
    substitute: Temporary formed fixture
    source: user:task:test/current#turn-2
    exit: task:test/replace-fixture
EOF
stage_intent
expect_pass_landing "accepted compact exception can land"

sed '/source:/d' "$fixture/.intent/exceptions/demo.yml" >"$fixture/.intent/exceptions/demo.yml.tmp"
mv "$fixture/.intent/exceptions/demo.yml.tmp" "$fixture/.intent/exceptions/demo.yml"
stage_intent
expect_fail "exception requires accepted authority"

cat >"$fixture/.intent/exceptions/demo.yml" <<EOF
version: 1
unit: demo
exceptions:
  - requirement: repo:docs/domain.md#demo
    substitute: Temporary formed fixture
    source: user:task:test/current#turn-2
    exit: task:test/replace-fixture
    expires: 2000-01-01
EOF
stage_intent
expect_fail_landing "expired exception cannot land"

rm -f "$fixture/.intent/exceptions/demo.yml"
rmdir "$fixture/.intent/exceptions"
cat >"$fixture/.intent/config.yml" <<EOF
version: 1
escalation: agent
EOF
stage_intent
expect_pass "agent escalation is explicit and bounded"

printf 'workers: subagent\n' >>"$fixture/.intent/config.yml"
stage_intent
expect_fail "removed workers field is rejected"
sed '/^workers:/d' "$fixture/.intent/config.yml" >"$fixture/.intent/config.yml.tmp"
mv "$fixture/.intent/config.yml.tmp" "$fixture/.intent/config.yml"

printf 'execution: autonomous\n' >>"$fixture/.intent/config.yml"
stage_intent
expect_fail "removed execution field is rejected as unknown"

sed '/^execution:/d; s/agent/never/' "$fixture/.intent/config.yml" >"$fixture/.intent/config.yml.tmp"
mv "$fixture/.intent/config.yml.tmp" "$fixture/.intent/config.yml"
stage_intent
expect_fail "escalation has no off-switch value"

rm -f "$fixture/.intent/config.yml"
mkdir -p "$fixture/.intent/notes"
cat >"$fixture/.intent/notes/demo.yml" <<EOF
version: 1
unit: demo
brief_ids: [$id]
EOF
stage_intent
expect_fail "unknown intent stores are rejected"

rm -rf "$fixture/.intent/notes"
write_routes
write_contracts
write_decision domain_direction user_explicit active "user:task:demo#turn-1"
cat >>"$fixture/.intent/ROUTES.yml" <<EOF
  - scope: demo.future
    paths: [futuredir]
    domain: [user:task:demo#turn-2]
EOF
printf '    at: [gone/StartMask.tsx]\n' >>"$fixture/.intent/decisions/demo/$id.yml"
stage_intent
out=$(cd "$fixture" && sh "$checker" --audit)
printf '%s\n' "$out" | grep -q "^AUDIT: .intent/ROUTES.yml:demo.future route path 'futuredir' does not exist$" || { echo "not ok - audit reports dead route paths"; exit 1; }
printf '%s\n' "$out" | grep -q "anchor 'gone/StartMask.tsx' does not exist$" || { echo "not ok - audit reports dangling decision anchors"; exit 1; }
printf '%s\n' "$out" | grep -q '^AUDIT-VERIFY: demo.boundary — test:tests/demo_test.sh::demo$' || { echo "not ok - audit lists every verifier to run"; exit 1; }
printf '%s\n' "$out" | grep -q '^audit: 2 finding(s) · 1 verifier(s) to run$' || { echo "not ok - audit summary counts findings and verifiers"; exit 1; }
echo "ok - audit reports contradictions without failing (report-only)"

write_routes
write_decision domain_direction user_explicit active "user:task:demo#turn-1"
stage_intent
out=$(cd "$fixture" && sh "$checker" --audit)
printf '%s\n' "$out" | grep -q '^audit: 0 finding(s) · 1 verifier(s) to run$' || { echo "not ok - clean audit is reported"; exit 1; }
echo "ok - a clean audit is a verified fact"

echo "30 checks passed"
