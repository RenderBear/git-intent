#!/bin/sh
# Verify exact-tree review, checks, coordinated lease authentication, and
# atomic integration-ref updates.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
land="$root/skills/intent-land/scripts/land-support.sh"
lease="$root/skills/intent-coordinate/scripts/lease-support.sh"
runtime_support="$root/skills/intent-coordinate/scripts/runtime-support.sh"
brief_support="$root/skills/intent-brief/scripts/brief-support.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-land-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$fixture/.intent" "$fixture/docs" "$fixture/src" "$fixture/ui" "$fixture/checks"
printf '# Architecture\n' >"$fixture/docs/architecture.md"
printf 'one\n' >"$fixture/src/a.txt"
printf 'ui\n' >"$fixture/ui/view.txt"
cat >"$fixture/checks/verify.sh" <<'EOF'
#!/bin/sh
test "$(cat src/a.txt)" != broken
EOF
cat >"$fixture/checks/fail.sh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$fixture/checks/verify.sh" "$fixture/checks/fail.sh"
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

printf 'two\n' >"$fixture/src/a.txt"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" direct "unreviewed" --unit u1 --scope area.src \
    --domain source --paths src/a.txt >/dev/null 2>&1); then die "semantic constraint landed without review"; fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "failed review moved target"
out=$(cd "$fixture" && sh "$land" direct "reviewed source" --unit u1 --scope area.src \
  --domain source --reviewed constraint:source.layout --paths src/a.txt)
printf '%s\n' "$out" | grep -q '^CHECK: running — command:checks/verify.sh$' || die "contract verifier did not run"
printf '%s\n' "$out" | grep -q '^REVIEW: accepted — constraint:source.layout$' || die "constraint review not acknowledged"
printf '%s\n' "$out" | grep -q '^LANDED:' || die "reviewed candidate did not land"
ok "affected contracts verify and semantic constraints require prospective review"

printf 'broken\n' >"$fixture/src/a.txt"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" direct "broken" --unit u2 --scope area.src --domain source \
    --reviewed constraint:source.layout --paths src/a.txt >/dev/null 2>&1); then die "broken contract landed"; fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "failed verifier moved target"
[ "$(cat "$fixture/src/a.txt")" = broken ] || die "failed landing discarded work"
git -C "$fixture" checkout -q -- src/a.txt
ok "failed verification leaves ref and working change safe"

printf 'changed\n' >"$fixture/ui/view.txt"
printf 'unrelated\n' >"$fixture/unrelated.txt"
out=$(cd "$fixture" && sh "$land" direct "simple UI" --unit ui --scope area.ui --paths ui/view.txt)
printf '%s\n' "$out" | grep -q '^REACH: local$' || die "simple UI landing gained governance"
[ -f "$fixture/unrelated.txt" ] || die "selected landing removed unrelated work"
rm "$fixture/unrelated.txt"
ok "simple local landing remains low ceremony and preserves unrelated work"

cat >>"$fixture/.intent/CONSTRAINTS.yml" <<'EOF'
  - id: source.naming
    assertion: Source names remain explicit.
    authority: user:task:test#turn-2
    applies_to: [source]
    material: [architecture:docs/architecture.md]
EOF
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" direct "unresolved adoption" --unit govern --scope area.root \
    --domain source --reviewed constraint:source.layout --reviewed constraint:source.naming \
    --paths .intent/CONSTRAINTS.yml >/dev/null 2>&1); then die "additive governance landed without resolved authority"; fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "unresolved adoption moved target"
out=$(cd "$fixture" && sh "$land" direct "adopt naming" --unit govern --scope area.root \
  --domain source --reviewed constraint:source.layout --reviewed constraint:source.naming \
  --allow-open --paths .intent/CONSTRAINTS.yml)
printf '%s\n' "$out" | grep -q '^GOVERNANCE: additive record establishment$' || die "additive governance was not classified open"
ok "additive governance requires resolved establishment authority"

git -C "$fixture" checkout -qb unit/worker
printf 'worker\n' >"$fixture/src/b.txt"
git -C "$fixture" add src/b.txt
git -C "$fixture" commit -qm worker
git -C "$fixture" checkout -q main
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
if (cd "$fixture" && sh "$land" merge unit/worker "missing lease" --unit worker --scope area.src \
    --domain source --reviewed constraint:source.layout --reviewed constraint:source.naming \
    --plan bundle >/dev/null 2>&1); then die "coordinated landing without lease succeeded"; fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "missing lease moved target"
ok "coordinated landing requires a live lease"

(cd "$fixture" && sh "$lease" create worker --scope area.src --paths src/b.txt --domains source --digest "$source_digest" \
  --branch unit/worker --integration-target main >/dev/null)
out=$(cd "$fixture" && sh "$land" merge unit/worker "land worker" --unit worker --scope area.src \
  --domain source --reviewed constraint:source.layout --reviewed constraint:source.naming \
  --plan bundle)
printf '%s\n' "$out" | grep -q '^LANDED:' || die "fresh matching lease did not land"
[ ! -e "$runtime/leases/worker.yml" ] || die "landed lease was not released"
[ -f "$runtime/plans/bundle.yml" ] || die "incomplete plan was removed"
ok "matching lease is authenticated, released, and incomplete plan retained"

echo "6 landing checks passed"
