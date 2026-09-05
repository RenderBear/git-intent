#!/bin/sh
# Verify the agent-facing governance, schema, preparation, runner, and cache surfaces.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cli="$root/bin/invariant"
fixtures=$(mktemp -d "${TMPDIR:-/tmp}/invariant-agent-protocol.XXXXXX")
findings=$(mktemp "${TMPDIR:-/tmp}/invariant-findings.XXXXXX")
assessment=$(mktemp "${TMPDIR:-/tmp}/invariant-assessment.XXXXXX")
cleanup() { rm -rf "$fixtures" "$findings" "$assessment"; }
trap cleanup EXIT HUP INT TERM

die() { echo "not ok - $1"; exit 1; }
ok() { echo "ok - $1"; }

new_repo() {
  destination=$1
  mkdir -p "$destination"
  git -C "$destination" init -qb main
  git -C "$destination" config user.name test
  git -C "$destination" config user.email test@example.com
  git -C "$destination" config commit.gpgsign false
}

governance="$fixtures/governance"
new_repo "$governance"
printf 'seed\n' >"$governance/app.txt"
mkdir -p "$governance/.invariant"
cat >"$governance/.invariant/config.yml" <<'EOF'
version: 1
authority: agent
execution: auto
integration_branch: main
push_remote: off
EOF
git -C "$governance" add -A
git -C "$governance" commit -qm seed

audit_schema=$(cd "$governance" && "$cli" --format json evidence audit schema)
printf '%s\n' "$audit_schema" | grep -q '"required":\["id","summary","evidence","proposed","disposition"\]' ||
  die "audit schema did not expose required finding fields"
assessment_schema=$(cd "$governance" && "$cli" --format json task assessment schema)
printf '%s\n' "$assessment_schema" | grep -q '"allow_open"' || die "assessment schema omitted open-reach acknowledgement"
if printf '%s\n' "$assessment_schema" | grep -q '"output"'; then die "schema JSON duplicated its text form"; fi
ok "audit and assessment schemas are machine-readable and compact"

out=$(cd "$governance" && "$cli" initial-governance begin initial)
printf '%s\n' "$out" | grep -q '^GOVERNANCE-PHASE: audit$' || die "initial governance did not enter its audit phase"
branch=$(printf '%s\n' "$out" | sed -n 's/^BRANCH: //p')
[ "$(git -C "$governance" branch --show-current)" = "$branch" ] || die "initial governance did not open the managed branch first"
cat >"$findings" <<'EOF'
version: 1
findings:
  - id: record-app-boundary
    summary: The application boundary should be recorded.
    evidence: [repo:app.txt]
    proposed: architecture
    disposition: adoptable
EOF
out=$(cd "$governance" && "$cli" initial-governance audit-save initial initial --input "$findings")
audit_id=$(printf '%s\n' "$out" | sed -n 's/^AUDIT: //p')
printf '%s\n' "$audit_id" | grep -Eq '^initial--[0-9]{8}T[0-9]{6}Z$' || die "audit id did not contain its timestamp"
printf '%s\n' "$out" | grep -q '^GOVERNANCE-PHASE: adopt$' || die "agent authority did not advance audit to adoption"
grep -q '^  phase: adopt$' "$governance/.git/invariant/briefs/initial.yml" || die "governance phase was not resumable"
grep -q '^  - record-app-boundary$' "$governance/.git/invariant/briefs/initial.yml" || die "ready finding was not selected automatically"
printf 'candidate\n' >>"$governance/app.txt"
git -C "$governance" add app.txt ".invariant/audits/$audit_id.yml"
git -C "$governance" commit -qm "record audited candidate"
prepared=$(cd "$governance" && "$cli" --format json task assessment prepare initial)
printf '%s\n' "$prepared" | grep -q '"candidate_tree"' || die "assessment preparation omitted the candidate tree"
printf '%s\n' "$prepared" | grep -q '"paths":\[".invariant/audits/' || die "assessment preparation did not use exact candidate paths"
[ -f "$governance/.git/invariant/tasks/initial/prepared-assessment.yml" ] ||
  die "assessment preparation did not save its Git-local draft"
status=$(cd "$governance" && "$cli" status)
printf '%s\n' "$status" | grep -q '^TASK: initial (implementing)$' || die "top-level status omitted the active task"
ok "initial governance keeps audit and adoption inside one resumable managed session"

deferred="$fixtures/deferred"
new_repo "$deferred"
printf 'seed\n' >"$deferred/app.txt"
mkdir -p "$deferred/.invariant"
cat >"$deferred/.invariant/config.yml" <<'EOF'
version: 1
authority: human
execution: auto
integration_branch: main
push_remote: off
EOF
git -C "$deferred" add -A
git -C "$deferred" commit -qm seed
(cd "$deferred" && "$cli" initial-governance begin deferred >/dev/null)
out=$(cd "$deferred" && "$cli" initial-governance audit-save deferred review --input "$findings")
deferred_audit=$(printf '%s\n' "$out" | sed -n 's/^AUDIT: //p')
printf '%s\n' "$out" | grep -q '^GOVERNANCE-PHASE: decision$' || die "human authority did not retain the adoption decision"
out=$(cd "$deferred" && "$cli" initial-governance defer deferred)
printf '%s\n' "$out" | grep -q '^GOVERNANCE-PHASE: deferred$' || die "audit deferral was not reported"
[ "$(git -C "$deferred" branch --show-current)" = main ] || die "audit-only deferral did not restore main"
git -C "$deferred" cat-file -e "main:.invariant/audits/$deferred_audit.yml" || die "deferred audit was not landed"
[ ! -f "$deferred/.git/invariant/briefs/deferred.yml" ] || die "deferred governance receipt was not cleaned"
ok "human authority can land a saved audit while deferring adoption"

architecture="$fixtures/architecture"
new_repo "$architecture"
mkdir -p "$architecture/.invariant" "$architecture/docs"
cat >"$architecture/.invariant/config.yml" <<'EOF'
version: 1
authority: agent
execution: auto
integration_branch: main
push_remote: off
EOF
cat >"$architecture/docs/architecture.md" <<'EOF'
# Architecture

## Application boundary

The application owns its public behavior.
EOF
cat >"$architecture/.invariant/DOMAINS.yml" <<'EOF'
version: 1
domains:
  - id: app
    responsibility: Owns application behavior.
    authority: user:task:test#turn-1
    architecture: [architecture:docs/architecture.md#application-boundary]
EOF
git -C "$architecture" add -A
git -C "$architecture" commit -qm seed
out=$(cd "$architecture" && "$cli" task begin architecture --goal "Refine the application boundary" \
  --boundary unresolved --path docs/architecture.md --domain app)
printf '\nThe application also owns recovery behavior.\n' >>"$architecture/docs/architecture.md"
git -C "$architecture" commit -qam candidate
prepared=$(cd "$architecture" && "$cli" --format json task assessment prepare architecture)
printf '%s\n' "$prepared" | grep -q '"boundary":{"disposition":"recorded"}' ||
  die "architecture prose was not inferred as a durable boundary change"
printf '%s\n' "$prepared" | grep -q '"governance":\["architecture:docs/architecture.md#application-boundary"\]' ||
  die "registered architecture authority was not inferred as candidate governance"
printf '%s\n' "$prepared" | grep -q '"recommended_architecture_reviews":\["architecture:docs/architecture.md#application-boundary"\]' ||
  die "affected architecture review was not exposed separately"
ok "assessment preparation distinguishes registered authority from explicit review acknowledgement"

runner="$fixtures/runner"
new_repo "$runner"
mkdir -p "$runner/.invariant" "$runner/backend"
printf 'one\n' >"$runner/app.txt"
cat >"$runner/backend/verify.sh" <<'EOF'
#!/bin/sh
set -eu
count_file=$(git rev-parse --git-common-dir)/runner-count
count=0
if [ -f "$count_file" ]; then count=$(cat "$count_file"); fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
printf 'NOISY-SUCCESS-OUTPUT %s\n' "$1"
EOF
chmod +x "$runner/backend/verify.sh"
cat >"$runner/.invariant/config.yml" <<'EOF'
version: 1
authority: agent
execution: auto
integration_branch: main
push_remote: off
verification:
  runners:
    backend:
      command: [sh, verify.sh, '{target}']
      cwd: backend
      cache: exact-tree
      timeout: 30
EOF
git -C "$runner" add -A
git -C "$runner" commit -qm seed

out=$(cd "$runner" && "$cli" task begin cache --goal "Exercise runner caching" --boundary no-record --path app.txt)
branch=$(printf '%s\n' "$out" | sed -n 's/^BRANCH: //p')
goal_digest=$(printf '%s\n' "$out" | sed -n 's/^GOAL-DIGEST: //p')
printf 'two\n' >"$runner/app.txt"
git -C "$runner" commit -qam candidate
if out=$(cd "$runner" && "$cli" task finish cache 2>&1); then
  die "task finish accepted a missing prepared assessment"
fi
printf '%s\n' "$out" | grep -q "task assessment prepare cache" ||
  die "missing assessment did not name the preparation command"
cat >"$assessment" <<EOF
version: 1
goal_digest: $goal_digest
paths: [app.txt]
interfaces: []
domains: []
boundary: {disposition: no-record}
governance: []
architecture_reviews: []
checks: [runner:backend#tests/smoke]
EOF
mkdir -p "$runner/.git/invariant/tasks/cache"
cp "$assessment" "$runner/.git/invariant/tasks/cache/prepared-assessment.yml"
out=$(cd "$runner" && "$cli" candidate verify "$branch" --assessment "$assessment")
printf '%s\n' "$out" | grep -q '^CHECK: passed — runner:backend#tests/smoke$' || die "named runner did not execute"
if printf '%s\n' "$out" | grep -q 'NOISY-SUCCESS-OUTPUT'; then die "successful verifier logs leaked into normal output"; fi
out=$(cd "$runner" && "$cli" task finish cache)
printf '%s\n' "$out" | grep -q '^CHECK: reused — runner:backend#tests/smoke$' || die "finish did not reuse exact-candidate verification"
printf '%s\n' "$out" | grep -q '^CHECK-CACHE: 1 reused$' || die "verification cache summary was missing"
[ "$(cat "$runner/.git/runner-count")" = 1 ] || die "cached verifier executed more than once"
ok "project-aware runners retain logs and reuse exact-candidate verification receipts"

echo "5 agent protocol checks passed"
