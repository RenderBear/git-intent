#!/bin/sh
# Verify audit discovery is deterministic, scoped, and write-free.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
audit="$root/skills/intent-audit/scripts/audit-support.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-audit-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
mkdir -p "$fixture/backend" "$fixture/.intent"
echo b >"$fixture/backend/app.py"
cat >"$fixture/.intent/ROUTES.yml" <<'EOF'
version: 1
routes:
  - scope: area.backend
    paths: [backend]
    domain: [user:task:seeded#turn-1]
EOF
git -C "$fixture" add -A
git -C "$fixture" commit -qm seed

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

out=$(cd "$fixture" && sh "$audit" scope --paths backend/app.py frontend/a.ts frontend/b.ts scripts/run.sh Makefile)
printf '%s\n' "$out" | grep -q '^  - scope: area.frontend$' || die "unrouted directory becomes an area route"
printf '%s\n' "$out" | grep -q '^    paths: \[frontend\]$' || die "area route matches the directory, not files"
printf '%s\n' "$out" | grep -q '^  - scope: area.scripts$' || die "every unrouted top-level directory is proposed"
printf '%s\n' "$out" | grep -q '^  - scope: area.root$' || die "root-level files group under area.root"
printf '%s\n' "$out" | grep -q '^    paths: \[Makefile\]$' || die "root files are listed explicitly"
printf '%s\n' "$out" | grep -q 'area.backend' && die "routed paths are never re-proposed"
printf '%s\n' "$out" | grep -q '^# discovered candidate rows' || die "existing ROUTES.yml gets candidate rows, not a new file"
printf '%s\n' "$out" | grep -q 'REPLACE-with-current-request-locator' || die "authority placeholder demands the current request"
ok "scoped audit emits area rows for exactly the unrouted spread"

out=$(cd "$fixture" && sh "$audit" scope --paths backend/app.py)
printf '%s\n' "$out" | grep -q '^DISCOVER: 0' || die "fully routed touch set proposes nothing"
ok "fully routed touch set proposes nothing"

if (cd "$fixture" && sh "$audit" full >/dev/null 2>&1); then
  die "full audit accepts no implicit mode"
fi
ok "full audit requires an explicit execution mode"

out=$(cd "$fixture" && sh "$audit" full --autonomous)
printf '%s\n' "$out" | grep -q '^AUDIT: full$' || die "full audit does not identify itself"
printf '%s\n' "$out" | grep -q '^MODE: autonomous$' || die "autonomous mode is not carried"
printf '%s\n' "$out" | grep -q '^SNAPSHOT: ' || die "full audit lacks a snapshot"
printf '%s\n' "$out" | grep -q '^BOUNDARY: area.backend backend$' || die "full audit lacks the derived map"
printf '%s\n' "$out" | grep -q '^ROUTE: area.backend$' || die "full audit lacks existing route evidence"
printf '%s\n' "$out" | grep -q 'REPLACE-with-current-request-locator' && die "full audit must not propose universal route coverage"
ok "autonomous full audit emits evidence without blanket candidates"

out=$(cd "$fixture" && sh "$audit" full --assisted)
printf '%s\n' "$out" | grep -q '^MODE: assisted$' || die "assisted mode is not carried"
ok "assisted full audit uses the same read-only evidence boundary"

rm -f "$fixture/.intent/ROUTES.yml"
out=$(cd "$fixture" && sh "$audit" scope --paths frontend/a.ts)
printf '%s\n' "$out" | grep -q '^version: 1$' || die "absent ROUTES.yml gets a full-file skeleton"
printf '%s\n' "$out" | grep -q '^routes:$' || die "skeleton declares the routes list"
ok "absent ROUTES.yml yields a complete file skeleton"

out=$(cd "$fixture" && sh "$audit" scope --paths .intent/CONTRACTS.yml .github/workflows/ci.yml .env frontend/a.ts)
printf '%s\n' "$out" | grep -q 'area.frontend' || die "ordinary paths still propose"
printf '%s\n' "$out" | grep -q 'scope: area.root' || die "root dotfiles and hidden directories belong to area.root"
printf '%s\n' "$out" | grep -q '\.intent' && die "intent state is never proposed"
ok "dotfiles are addressable while intent state remains excluded"

[ ! -e "$fixture/.intent/ROUTES.yml" ] || die "audit must not write"
ok "audit writes nothing"

# Recurrence: the audit-offer trigger, derived from the first-parent stream.
git -C "$fixture" config commit.gpgsign false
cat >"$fixture/.intent/ROUTES.yml" <<'EOF'
version: 1
routes:
  - scope: area.backend
    paths: [backend]
    domain: [user:task:seeded#turn-1]
EOF
git -C "$fixture" add .intent
git -C "$fixture" commit -qm routes >/dev/null 2>&1 || true
i=1
while [ "$i" -le 3 ]; do
  echo "$i" >>"$fixture/backend/app.py"
  git -C "$fixture" commit -qam "u$i

Intent-Unit: u$i
Intent-Scope: area.frontend
Intent-Scope: area.backend"
  i=$((i + 1))
done
echo once >"$fixture/once.txt"
git -C "$fixture" add once.txt
git -C "$fixture" commit -qm "single

Intent-Unit: u9
Intent-Scope: area.scripts"
echo board1 >>"$fixture/backend/app.py"
git -C "$fixture" commit -qam "board unit 1

Intent-Unit: b1
Intent-Scope: area.board
Intent-Board: one-goal"
echo board2 >>"$fixture/backend/app.py"
git -C "$fixture" commit -qam "board unit 2

Intent-Unit: b2
Intent-Scope: area.board
Intent-Board: one-goal"
out=$(cd "$fixture" && sh "$audit" recurrence)
printf '%s\n' "$out" | grep -q '^RECURRENT: area.frontend 3$' || die "an ungoverned identifier recurring across landings is reported"
printf '%s\n' "$out" | grep -q 'area.backend' && die "a governed identifier never triggers the offer"
printf '%s\n' "$out" | grep -q 'area.scripts' && die "first contact never triggers the offer"
printf '%s\n' "$out" | grep -q 'area.board' && die "several commits from one coordinated goal count once"
ok "recurrence counts completed goals rather than workflow commits"

echo "9 audit-support checks passed"
