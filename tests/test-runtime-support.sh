#!/bin/sh
# Verify the runtime is visible, ignored, shared across linked worktrees, and
# safely cleanable without touching repository content.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
runtime_support="$root/skills/intent-coordinate/scripts/runtime-support.sh"
lease_support="$root/skills/intent-coordinate/scripts/lease-support.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-runtime-test.XXXXXX")
linked="$fixture-linked"
cleanup() { rm -rf "$fixture" "$linked"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
touch "$fixture/seed"
git -C "$fixture" add seed
git -C "$fixture" commit -qm seed

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

runtime=$(cd "$fixture" && sh "$runtime_support" root)
fixture_real=$(CDPATH= cd -- "$fixture" && pwd -P)
[ "$runtime" = "$fixture_real/intent-work" ] || die "main worktree runtime is not visible at intent-work"
ok "runtime root is visible in the primary worktree"

git -C "$fixture" worktree add -q -b linked "$linked"
linked_runtime=$(cd "$linked" && sh "$runtime_support" root)
[ "$linked_runtime" = "$runtime" ] || die "linked worktree resolved a private runtime"
ok "linked worktrees share the primary visible runtime"

(cd "$linked" && sh "$runtime_support" ensure >/dev/null)
[ -f "$runtime/.gitignore" ] || die "runtime lacks its self-ignore marker"
[ -z "$(git -C "$fixture" status --porcelain -- intent-work)" ] || die "runtime pollutes Git status"
ok "runtime self-ignores without entering repository state"

mkdir -p "$runtime/observations" "$runtime/receipts/tree"
printf 'snapshot\n' >"$runtime/observations/digest"
printf 'receipt\n' >"$runtime/receipts/tree/check"
(cd "$fixture" && sh "$lease_support" create watcher --scope area.root --paths seed --duration 2h >/dev/null)
mkdir -p "$runtime/boards"
cat >"$runtime/boards/done.yml" <<'EOF'
version: 1
id: done
goal: Exercise completed-board cleanup.
integration_target: main
units:
  - id: one
    objective: First unit.
    dependencies: []
    surfaces: [one]
  - id: two
    objective: Second unit.
    dependencies: [one]
    surfaces: [two]
EOF
printf 'landed\n' >>"$fixture/seed"
git -C "$fixture" commit -qam "land runtime fixtures

Intent-Unit: one
Intent-Unit: two
Intent-Scope: area.root"
out=$(cd "$fixture" && sh "$runtime_support" status)
printf '%s\n' "$out" | grep -q "^RUNTIME: $runtime$" || die "status hides the runtime path"
printf '%s\n' "$out" | grep -q '^CACHE: observations 1 file(s) — disposable$' || die "status omits observations"
printf '%s\n' "$out" | grep -q '^CACHE: receipts 1 file(s) — disposable$' || die "status omits receipts"
printf '%s\n' "$out" | grep -q '^STALE: watcher — intersecting landing touched seed' || die "status does not expose stale leases"
ok "runtime status exposes disposable contents"

(cd "$fixture" && sh "$lease_support" release watcher >/dev/null)
out=$(cd "$fixture" && sh "$runtime_support" clean)
printf '%s\n' "$out" | grep -q '^CLEANABLE: observations 1 cache file(s)$' || die "dry run omits observations"
printf '%s\n' "$out" | grep -q '^CLEANABLE: completed board done$' || die "dry run omits completed boards"
[ -f "$runtime/observations/digest" ] || die "dry-run cleanup mutated runtime"
out=$(cd "$fixture" && sh "$runtime_support" clean --apply)
printf '%s\n' "$out" | grep -q '^CLEANED: receipts 1 cache file(s)$' || die "applied cleanup omits receipts"
printf '%s\n' "$out" | grep -q '^CLEANED: completed board done$' || die "applied cleanup omits completed boards"
[ ! -e "$runtime" ] || die "empty runtime workspace remains after cleanup"
git -C "$fixture" log -1 --format=%s | grep -q '^land runtime fixtures$' || die "cleanup changed repository history"
ok "cleanup is dry-run first and removes only disposable state when applied"

echo "5 runtime-support checks passed"
