#!/bin/sh
# Verify repository bootstrap, agent instruction installation, and interactive choices.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cli="$root/bin/invariant"
fixtures=$(mktemp -d "${TMPDIR:-/tmp}/invariant-init-test.XXXXXX")
cleanup() { rm -rf "$fixtures"; }
trap cleanup EXIT HUP INT TERM

new_repo() {
  destination=$1
  branch=$2
  mkdir -p "$destination"
  git -C "$destination" init -qb "$branch"
  git -C "$destination" config user.name test
  git -C "$destination" config user.email test@example.com
  printf 'seed\n' >"$destination/file.txt"
  git -C "$destination" add file.txt
  git -C "$destination" commit -qm seed
}

die() { echo "not ok - $1"; exit 1; }
ok() { echo "ok - $1"; }

defaults="$fixtures/defaults"
new_repo "$defaults" main
printf '# Existing Codex instructions\n' >"$defaults/AGENTS.md"
printf '# Existing Claude instructions\n' >"$defaults/CLAUDE.md"

out=$(cd "$defaults" && "$cli" init --defaults)
grep -q '^harnesses:$' "$defaults/.invariant/config.yml" || die "default init omitted harnesses"
grep -q '^- codex$' "$defaults/.invariant/config.yml" || die "default init omitted Codex"
grep -q '^- claude$' "$defaults/.invariant/config.yml" || die "default init omitted Claude"
grep -q '^integration_branch: auto$' "$defaults/.invariant/config.yml" || die "default init did not preserve automatic integration selection"
grep -q '^resolution: assisted$' "$defaults/.invariant/config.yml" || die "default init did not use assisted resolution"
grep -q "^push_remote: 'off'$" "$defaults/.invariant/config.yml" || die "default init enabled publication"
grep -q '^# Existing Codex instructions$' "$defaults/AGENTS.md" || die "Codex setup replaced existing instructions"
[ "$(grep -c '^<!-- invariant:workflow:start -->$' "$defaults/AGENTS.md")" -eq 1 ] || die "Codex workflow marker is not singular"
grep -q '^## Invariant lifecycle$' "$defaults/AGENTS.md" || die "Codex workflow was not installed"
grep -q '^# Existing Claude instructions$' "$defaults/CLAUDE.md" || die "Claude setup replaced existing instructions"
grep -q '^@AGENTS.md$' "$defaults/CLAUDE.md" || die "Claude does not import the shared workflow"
printf '%s\n' "$out" | grep -q '^RECOMMENDED: Ask your coding agent to conduct a full audit with Invariant' || die "init omitted the audit recommendation"
printf '%s\n' "$out" | grep -q '^PROMPT: Audit this repository with Invariant\.' || die "init omitted the agent prompt"
[ ! -e "$defaults/.invariant/DOMAINS.yml" ] || die "init manufactured empty domains"
[ ! -e "$defaults/.invariant/CONTRACTS.yml" ] || die "init manufactured empty contracts"
[ ! -e "$defaults/.invariant/audits" ] || die "init ran an audit"
ok "--defaults configures both harnesses and recommends an audit without running one"

interactive="$fixtures/interactive"
new_repo "$interactive" trunk
git -C "$interactive" branch stable
answers='claude
auto
assisted
stable
on
on
on'
out=$(printf '%s\n' "$answers" | (cd "$interactive" && "$cli" init))
grep -q '^harnesses:$' "$interactive/.invariant/config.yml" || die "interactive init omitted harnesses"
grep -q '^- claude$' "$interactive/.invariant/config.yml" || die "interactive init did not select Claude"
if grep -q '^- codex$' "$interactive/.invariant/config.yml"; then die "interactive init selected Codex unexpectedly"; fi
grep -q '^resolution: auto$' "$interactive/.invariant/config.yml" || die "interactive resolution choice was lost"
grep -q '^execution: assisted$' "$interactive/.invariant/config.yml" || die "interactive execution choice was lost"
grep -q '^integration_branch: stable$' "$interactive/.invariant/config.yml" || die "named integration branch was lost"
grep -q "^push_remote: 'on'$" "$interactive/.invariant/config.yml" || die "interactive publication choice was lost"
[ ! -e "$interactive/AGENTS.md" ] || die "Claude-only setup created AGENTS.md"
grep -q '^## Invariant lifecycle$' "$interactive/CLAUDE.md" || die "Claude-only workflow was not installed"
printf '%s\n' "$out" | grep -q '^Integration branch$' || die "interactive init did not explain integration branch"
printf '%s\n' "$out" | grep -q 'Auto uses the current branch for each new task' || die "automatic branch behavior was not explained"
ok "interactive init explains and persists each repository choice"

ambiguous="$fixtures/ambiguous"
new_repo "$ambiguous" main
printf '## Invariant lifecycle\n\nManually maintained.\n' >"$ambiguous/AGENTS.md"
if (cd "$ambiguous" && "$cli" init --defaults >/dev/null 2>&1); then
  die "init overwrote an unmanaged workflow"
fi
[ ! -e "$ambiguous/.invariant/config.yml" ] || die "failed instruction preflight left partial config"
grep -q '^Manually maintained\.$' "$ambiguous/AGENTS.md" || die "failed preflight changed instructions"
ok "init refuses ambiguous instruction files before creating project state"

echo "3 initialization checks passed"
