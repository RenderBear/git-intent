#!/bin/sh
# Verify prospective-tree validation and atomic integration-ref updates.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
land="$root/skills/intent-land/scripts/land-support.sh"
brief="$root/skills/intent-brief/scripts/brief-support.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-land-test.XXXXXX")
fresh=""
cleanup() { rm -rf "$fixture"; [ -z "$fresh" ] || rm -rf "$fresh"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$fixture/src" "$fixture/checks" "$fixture/.intent"
echo one >"$fixture/src/a.txt"
echo base >"$fixture/other.txt"
cat >"$fixture/.intent/config.yml" <<'EOF'
version: 1
escalation: human
EOF
cat >"$fixture/.intent/ROUTES.yml" <<'EOF'
version: 1
routes:
  - scope: area.src
    paths: [src]
    contracts: [contract:src.valid]
EOF
cat >"$fixture/.intent/CONTRACTS.yml" <<'EOF'
version: 1
contracts:
  - id: src.valid
    assertion: The source fixture is never broken.
    authority: user:task:land-test#turn-1
    scope: area.src
    surfaces: [repo:src]
    verifies: [command:checks/pass.sh]
EOF
cat >"$fixture/checks/pass.sh" <<'EOF'
#!/bin/sh
test "$(cat src/a.txt)" != broken
EOF
cat >"$fixture/checks/fail.sh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$fixture/checks/pass.sh" "$fixture/checks/fail.sh"
git -C "$fixture" add -A
git -C "$fixture" commit -qm seed

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

echo two >"$fixture/src/a.txt"
echo changed >"$fixture/other.txt"
echo unrelated >"$fixture/notes.txt"
old=$(git -C "$fixture" rev-parse HEAD)
out=$(cd "$fixture" && sh "$land" direct "land u1" --unit u1 --scope area.src \
  --paths src/a.txt --check command:checks/pass.sh)
printf '%s\n' "$out" | grep -q '^LANDED:' || die "direct landing reports success"
new=$(git -C "$fixture" rev-parse HEAD)
[ "$new" != "$old" ] || die "direct landing advances the integration ref"
[ "$(git -C "$fixture" show HEAD:src/a.txt)" = two ] || die "candidate tree contains the selected change"
git -C "$fixture" status --short | grep -q '^?? notes.txt$' || die "unrelated work remains untouched"
git -C "$fixture" status --short | grep -q '^ M other.txt$' || die "unrelated tracked work remains untouched"
(cd "$fixture" && sh "$brief" trailer HEAD >/dev/null) || die "landed direct commit has honest trailers"
ok "direct landing verifies a prospective tree and preserves unrelated work"

echo broken >"$fixture/src/a.txt"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" direct "bad u2" --unit u2 --scope area.src \
  --paths src/a.txt --check command:checks/fail.sh >/dev/null 2>&1); then
  die "failing prospective check was allowed to land"
fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "failed preflight moved the integration ref"
[ "$(cat "$fixture/src/a.txt")" = broken ] || die "failed preflight discarded work"
ok "failed verification leaves both the ref and working change intact"

git -C "$fixture" checkout -q -- src/a.txt
git -C "$fixture" checkout -q -- other.txt
rm -f "$fixture/notes.txt"

printf '# additive governance\n' >>"$fixture/.intent/CONTRACTS.yml"
old=$(git -C "$fixture" rev-parse HEAD)
if (cd "$fixture" && sh "$land" direct "unresolved extension" --unit govern \
  --scope area.src --paths .intent/CONTRACTS.yml >/dev/null 2>&1); then
  die "contract extension landed without establishment authority"
fi
[ "$(git -C "$fixture" rev-parse HEAD)" = "$old" ] || die "unresolved extension moved the integration ref"
out=$(cd "$fixture" && sh "$land" direct "authorized extension" --unit govern \
  --scope area.src --paths .intent/CONTRACTS.yml --allow-open)
printf '%s\n' "$out" | grep -q '^LANDED:' || die "authorized extension did not land"
ok "contract establishment requires resolved escalation authority"

git -C "$fixture" checkout -qb unit/feature
echo feature >"$fixture/src/b.txt"
git -C "$fixture" add src/b.txt
git -C "$fixture" commit -qm feature
git -C "$fixture" checkout -q main
out=$(cd "$fixture" && sh "$land" merge unit/feature "land feature" --unit feature \
  --scope area.src --check command:checks/pass.sh)
printf '%s\n' "$out" | grep -q '^LANDED:' || die "merge landing reports success"
[ "$(git -C "$fixture" show HEAD:src/b.txt)" = feature ] || die "prospective merge tree was landed"
[ "$(git -C "$fixture" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 3 ] || die "coordinated landing preserves the feature parent"
(cd "$fixture" && sh "$brief" trailer HEAD >/dev/null) || die "landed merge has honest trailers"
ok "merge landing verifies before creating a two-parent integration commit"

fresh=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-first-land-test.XXXXXX")
git -C "$fresh" init -qb trunk
git -C "$fresh" config user.name test
git -C "$fresh" config user.email test@example.com
git -C "$fresh" config commit.gpgsign false
echo first >"$fresh/README.md"
out=$(cd "$fresh" && sh "$land" direct "first landing" --unit first --scope area.root --paths README.md)
printf '%s\n' "$out" | grep -q '^LANDED:' || die "first landing reports success"
[ "$(git -C "$fresh" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 1 ] || die "first landing created an unexpected parent"
[ "$(git -C "$fresh" branch --show-current)" = trunk ] || die "unborn current branch was not retained as integration target"
ok "fresh repositories land atomically without a bootstrap branch"

echo "5 atomic landing checks passed"
