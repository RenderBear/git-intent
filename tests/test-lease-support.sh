#!/bin/sh
# Verify lease mechanics: unconditional dispatch minting, renewal, release,
# coordination-side freshness, and the clock-scheduled, causally decided
# conclusive liveness check.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
lease="$root/skills/intent-coordinate/scripts/lease-support.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-lease-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$fixture/src"
echo x >"$fixture/src/a.py"
git -C "$fixture" add src
git -C "$fixture" commit -qm seed

leases="$fixture/intent-work/leases"

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

out=$(cd "$fixture" && sh "$lease" create u1 --scope demo.unit --paths src/a.py)
printf '%s\n' "$out" | grep -q '^LEASE: u1 created — no live unit intersects' || die "dispatch mints unconditionally and reports no intersection"
[ -f "$leases/u1.yml" ] || die "every dispatch mints a lease"
grep -q '^version: 1$' "$leases/u1.yml" || die "lease carries the schema version"
grep -q '^tip: ' "$leases/u1.yml" || die "lease records the branch tip at grant"
grep -q '^ground: ' "$leases/u1.yml" || die "lease records the integration ground at grant"
grep -q '^created: ....-..-..T..:..:..Z$' "$leases/u1.yml" || die "created is UTC RFC 3339"
ok "create mints unconditionally with tip and ground recorded"

out=$(cd "$fixture" && sh "$lease" create u2 --scope demo.unit.sub --duration 30m)
printf '%s\n' "$out" | grep -q '^LEASE: u2 created — intersects u1' || die "scope-related live unit is reported as intersecting"
ok "create reports intersecting live units"

if (cd "$fixture" && sh "$lease" create u1 --scope demo.unit >/dev/null 2>&1); then
  die "existing lease is never overwritten"
fi
ok "create never overwrites an existing lease"

created_before=$(sed -n 's/^created:[[:space:]]*//p' "$leases/u2.yml")
expires_before=$(sed -n 's/^expires:[[:space:]]*//p' "$leases/u2.yml")
sleep 1
out=$(cd "$fixture" && sh "$lease" renew u2 --duration 2h)
printf '%s\n' "$out" | grep -q '^LEASE: u2 renewed' || die "renew reports the new expiry"
created_after=$(sed -n 's/^created:[[:space:]]*//p' "$leases/u2.yml")
expires_after=$(sed -n 's/^expires:[[:space:]]*//p' "$leases/u2.yml")
[ "$created_before" = "$created_after" ] || die "renew preserves created"
[ "$expires_before" != "$expires_after" ] || die "renew moves expires"
ok "renew preserves created, moves expires, re-records the tip"

out=$(cd "$fixture" && sh "$lease" list)
printf '%s\n' "$out" | grep -q '^LEASE: u1 demo.unit — expires .* (live)$' || die "list marks live leases"
out=$(cd "$fixture" && sh "$lease" list --scope demo.unit.sub)
printf '%s\n' "$out" | grep -q 'u2' || die "list --scope keeps related leases"
ok "list reports expiry state and filters by scope"

out=$(cd "$fixture" && sh "$lease" fresh u1)
printf '%s\n' "$out" | grep -q '^FRESH: u1' || die "nothing landed means FRESH"
echo y >>"$fixture/src/a.py"
git -C "$fixture" commit -qam "landing touching the claim"
if out=$(cd "$fixture" && sh "$lease" fresh u1); then
  die "intersecting landing goes STALE"
fi
printf '%s\n' "$out" | grep -q '^STALE: u1' || die "staleness is labeled with the touched path"
ok "fresh is FRESH until an intersecting landing, then STALE"

(cd "$fixture" && sh "$lease" release u1 >/dev/null)
(cd "$fixture" && sh "$lease" release u2 >/dev/null)

# Conclusive liveness: DEAD by ancestry, RENEW by tip advance, QUIESCENT by
# expired-and-unmoved, DEAD by branch-and-worktree gone.
git -C "$fixture" checkout -qb unit/m1
echo m >"$fixture/src/m.py"
git -C "$fixture" add src/m.py
git -C "$fixture" commit -qm m1
git -C "$fixture" checkout -q main
git -C "$fixture" merge -q --no-ff unit/m1 -m "merged"
(cd "$fixture" && sh "$lease" create m1 --scope demo.m --branch unit/m1 --duration 1s >/dev/null)
out=$(cd "$fixture" && sh "$lease" reap)
printf '%s\n' "$out" | grep -q '^DEAD: m1 (branch merged into main)$' || die "merged branch is conclusively DEAD by ancestry"
ok "a merged branch is DEAD by ancestry, never dates"
(cd "$fixture" && sh "$lease" release m1 >/dev/null)

git -C "$fixture" checkout -qb unit/q1
echo q >"$fixture/src/q.py"
git -C "$fixture" add src/q.py
git -C "$fixture" commit -qm q1
git -C "$fixture" checkout -q main
(cd "$fixture" && sh "$lease" create q1 --scope demo.q --branch unit/q1 --duration 1s >/dev/null)
sleep 2
out=$(cd "$fixture" && sh "$lease" reap)
printf '%s\n' "$out" | grep -q '^QUIESCENT: q1 — expired, tip unmoved' || die "expired with unmoved tip is QUIESCENT"
git -C "$fixture" checkout -q unit/q1
echo q2 >>"$fixture/src/q.py"
git -C "$fixture" commit -qam q2
git -C "$fixture" checkout -q main
out=$(cd "$fixture" && sh "$lease" reap)
printf '%s\n' "$out" | grep -q '^RENEW: q1 — tip advanced' || die "expired with advanced tip is RENEW, the worker is alive"
out=$(cd "$fixture" && sh "$lease" reap --apply)
printf '%s\n' "$out" | grep -q 'renewed 1' || die "apply renews the alive worker"
[ -f "$leases/q1.yml" ] || die "renewed lease survives apply"
ok "expiry schedules the check: QUIESCENT when unmoved, RENEW when the tip advanced"

tmp=$(mktemp "${TMPDIR:-/tmp}/git-intent-lease-test-ed.XXXXXX")
sed -e 's|^branch: unit/q1$|branch: unit/gone|' -e "s|^worktree: .*|worktree: /nonexistent-worktree|" \
  -e 's|^expires: .*|expires: 2099-01-01T00:00:00Z|' "$leases/q1.yml" >"$tmp" && mv "$tmp" "$leases/q1.yml"
out=$(cd "$fixture" && sh "$lease" reap)
printf '%s\n' "$out" | grep -q '^DEAD: q1 (branch and worktree gone)$' || die "branch and worktree both gone is conclusively DEAD"
out=$(cd "$fixture" && sh "$lease" reap --apply)
printf '%s\n' "$out" | grep -q 'reaped 1' || die "apply reaps the DEAD set"
[ ! -e "$leases/q1.yml" ] || die "apply removes DEAD leases"
ok "branch-and-worktree gone is DEAD; reap --apply deletes it"

(cd "$fixture" && sh "$lease" create r1 --scope demo.r --paths src >/dev/null)
out=$(cd "$fixture" && sh "$lease" release r1)
[ "$out" = "released r1" ] || die "release reports the unit"
[ ! -e "$leases/r1.yml" ] || die "release deletes the file"
if (cd "$fixture" && sh "$lease" release r1 >/dev/null 2>&1); then
  die "releasing a missing lease fails"
fi
ok "release deletes exactly one lease and fails when absent"

echo "10 lease-support checks passed"
