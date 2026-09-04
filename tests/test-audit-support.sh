#!/bin/sh
# Verify audit evidence framing and Git-causal freshness.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
audit="$root/skills/intent-audit/scripts/audit-support.sh"
validator="$root/skills/intent-brief/scripts/validate-state.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/invariant-audit-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb main
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$fixture/docs/adr" "$fixture/src/ocr" "$fixture/ui" "$fixture/.invariant/audits" "$fixture/.invariant/discoveries"
printf '# Architecture\n' >"$fixture/docs/architecture.md"
printf '# ADR\n' >"$fixture/docs/adr/0001.md"
printf 'ocr\n' >"$fixture/src/ocr/engine.txt"
printf 'ui\n' >"$fixture/ui/view.txt"
cat >"$fixture/.invariant/DOMAINS.yml" <<'EOF'
version: 1
domains:
  - id: ocr.engine
    responsibility: Executes OCR.
    authority: user:task:test#turn-1
    architecture: [architecture:docs/architecture.md#architecture]
EOF
git -C "$fixture" add -A
git -C "$fixture" commit -qm seed
ground=$(git -C "$fixture" rev-parse HEAD)
tree=$(git -C "$fixture" rev-parse 'HEAD^{tree}')

ok() { echo "ok - $1"; }
die() { echo "not ok - $1"; exit 1; }

out=$(cd "$fixture" && sh "$audit" scope --paths src/ocr/engine.txt)
printf '%s\n' "$out" | grep -q '^AUDIT: scope$' || die "scope frame missing"
printf '%s\n' "$out" | grep -q "^GROUND: $ground$" || die "ground missing"
printf '%s\n' "$out" | grep -q '^TREE: ' || die "tree missing"
printf '%s\n' "$out" | grep -q '^DERIVED: area.src$' || die "derived mechanical scope missing"
printf '%s\n' "$out" | grep -q '^DOMAIN: ocr.engine$' || die "existing semantic domain missing"
printf '%s\n' "$out" | grep -q '^SOURCE: docs/architecture.md$' || die "architecture source missing"
printf '%s\n' "$out" | grep -q '^NEXT: classify findings, then present one recommended transition and any required decision$' ||
  die "directed audit transition missing"
printf '%s\n' "$out" | grep -q '^routes:' && die "audit still proposes routes"
ok "scoped audit emits causal evidence without inventing semantic records"

out=$(cd "$fixture" && sh "$audit" full --auto)
printf '%s\n' "$out" | grep -q '^RESOLUTION: auto$' || die "full audit resolution missing"
printf '%s\n' "$out" | grep -q '^BOUNDARY: area.src src$' || die "full audit map missing"
ok "explicit full mode uses assisted or auto resolution vocabulary"

cat >"$fixture/.invariant/audits/ocr.yml" <<EOF
version: 1
id: ocr
ground: $ground
tree: $tree
mode: scope
paths: [src/ocr]
findings:
  - id: architecture-source
    summary: OCR behavior is described by the architecture document.
    evidence: [repo:docs/architecture.md, repo:src/ocr]
    proposed: discovery
    disposition: discovery-only
EOF
(cd "$fixture" && sh "$validator" >/dev/null) || die "tracked audit schema is invalid"
git -C "$fixture" add .invariant/audits/ocr.yml
git -C "$fixture" commit -qm "record audit"
out=$(cd "$fixture" && sh "$audit" fresh ocr)
printf '%s\n' "$out" | grep -q '^FRESH:' || die "audit commit made its own evidence stale"
ok "tracked audits can queue non-authoritative discoveries"

mkdir -p "$fixture/captured"
printf 'captured\n' >"$fixture/captured/fact.txt"
frame=$(cd "$fixture" && sh "$audit" scope --paths captured)
captured_ground=$(printf '%s\n' "$frame" | sed -n 's/^GROUND: //p')
captured_tree=$(printf '%s\n' "$frame" | sed -n 's/^TREE: //p')
cat >"$fixture/.invariant/audits/captured.yml" <<EOF
version: 1
id: captured
ground: $captured_ground
tree: $captured_tree
mode: scope
paths: [captured]
findings: []
EOF
git -C "$fixture" add captured .invariant/audits/captured.yml
git -C "$fixture" commit -qm "record exact audited snapshot"
out=$(cd "$fixture" && sh "$audit" fresh captured)
printf '%s\n' "$out" | grep -q '^FRESH: head matches the audited tree$' || die "captured work became stale when recorded"
ok "freshness compares the exact audited tree, not a wall clock or only its ground"

printf 'changed\n' >>"$fixture/ui/view.txt"
git -C "$fixture" commit -qam "unrelated UI change"
out=$(cd "$fixture" && sh "$audit" fresh ocr)
printf '%s\n' "$out" | grep -q '^FRESH:' || die "unrelated change made audit stale"
ok "unrelated descendants preserve audit freshness"

printf 'changed\n' >>"$fixture/docs/architecture.md"
git -C "$fixture" commit -qam "change audited evidence"
if out=$(cd "$fixture" && sh "$audit" fresh ocr); then die "intersecting evidence change stayed fresh"; fi
printf '%s\n' "$out" | grep -q '^STALE: changed evidence docs/architecture.md$' || die "stale evidence is not identified"
ok "intersecting descendant change makes audit stale"

echo "6 audit checks passed"
