#!/bin/sh
# Deterministic audit evidence and causal freshness. Semantic findings are
# written by intent-audit to tracked .intent/audits/; this helper never invents
# domains or normative meaning.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
brief_script="$script_dir/../../intent-brief/scripts/brief-support.sh"
validate_script="$script_dir/../../intent-brief/scripts/validate-state.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  audit-support.sh scope --paths <path> [<path>...]
      Emit the exact snapshot, derived path boundaries, existing semantic
      records, and likely architecture/check sources for a scoped audit.
  audit-support.sh full --assisted
  audit-support.sh full --auto
      Emit the same evidence for an explicitly requested repository audit.
  audit-support.sh fresh <audit-file-or-id> [<head>]
      Derive FRESH, STALE, or DIVERGED from Git ancestry and changes that
      intersect the audit's paths or evidence. Wall-clock time is ignored.
EOF
  exit 2
}

[ "$#" -ge 1 ] || usage
cmd=$1
shift

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git-intent: not inside a Git repository" >&2
  exit 2
}
cd "$root" || exit 2

snapshot() {
  ground=$(git rev-parse -q --verify HEAD 2>/dev/null || echo unborn)
  index=$(mktemp "${TMPDIR:-/tmp}/git-intent-audit-index.XXXXXX") || exit 2
  rm -f "$index"
  if [ "$ground" = unborn ]; then GIT_INDEX_FILE="$index" git read-tree --empty
  else GIT_INDEX_FILE="$index" git read-tree "$ground^{tree}"; fi
  GIT_INDEX_FILE="$index" git add -A -- . >/dev/null 2>&1 || true
  tree=$(GIT_INDEX_FILE="$index" git write-tree)
  rm -f "$index"
  printf 'GROUND: %s\nTREE: %s\n' "$ground" "$tree"
}

emit_records() {
  for spec in DOMAINS:DOMAIN CONTRACTS:CONTRACT CONSTRAINTS:CONSTRAINT; do
    file=${spec%%:*}; label=${spec#*:}
    [ -f ".intent/$file.yml" ] || continue
    awk -v label="$label" '/^  - id:/ {v=$0; sub(/^[^:]*: */,"",v); sub(/[[:space:]]+#.*$/, "", v); print label ": " v}' ".intent/$file.yml"
  done
}

emit_sources() {
  git ls-files 2>/dev/null | awk '
    {
      low=tolower($0)
      if(low ~ /(^|\/)(architecture|adr|adrs)(\/|\.|$)/ || low ~ /(^|\/)(readme\.md|openapi[^\/]*|asyncapi[^\/]*|[^\/]*schema[^\/]*)$/ || low ~ /\.(drawio|mmd|mermaid)$/)
        print "SOURCE: " $0
      if(low ~ /(^|\/)(makefile|justfile|taskfile\.ya?ml|package\.json|pyproject\.toml|cargo\.toml|go\.mod)$/ || low ~ /^\.github\/workflows\//)
        print "CHECK-SOURCE: " $0
    }
  '
}

emit_frame() {
  mode=$1; shift
  printf 'AUDIT: %s\n' "$mode"
  snapshot
  if [ "$mode" = scope ]; then
    for path do
      printf 'PATH: %s\n' "$path"
      sh "$brief_script" reach --paths "$path" 2>/dev/null | sed -n 's/^TOPOLOGY:/DERIVED:/p'
    done
  else
    sh "$brief_script" map
  fi
  emit_records
  emit_sources
  printf 'STATE-VALIDATION:\n'
  sh "$validate_script" --audit || true
  printf 'NEXT: write semantic findings to .intent/audits/<id>.yml; then use intent-record adopt when accepted\n'
}

case "$cmd" in
  scope)
    [ "${1:-}" = --paths ] || usage; shift; [ "$#" -ge 1 ] || usage
    emit_frame scope "$@"
    ;;
  full)
    [ "$#" -eq 1 ] || usage
    case "$1" in --assisted) resolution=assisted ;; --auto) resolution=auto ;; *) usage ;; esac
    printf 'RESOLUTION: %s\n' "$resolution"
    emit_frame full
    ;;
  fresh)
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
    case "$1" in */*) audit=$1 ;; *) audit=".intent/audits/$1.yml" ;; esac
    [ -f "$audit" ] || { echo "git-intent: no audit '$1'" >&2; exit 2; }
    head=${2:-HEAD}
    ground=$(sed -n 's/^ground:[[:space:]]*//p' "$audit" | head -1)
    tree=$(sed -n 's/^tree:[[:space:]]*//p' "$audit" | head -1)
    mode=$(sed -n 's/^mode:[[:space:]]*//p' "$audit" | head -1)
    [ -n "$ground" ] || { echo "git-intent: audit has no ground" >&2; exit 2; }
    [ -n "$tree" ] || { echo "git-intent: audit has no tree" >&2; exit 2; }
    if [ "$ground" = unborn ]; then
      if git rev-parse -q --verify "$head^{commit}" >/dev/null 2>&1; then echo "STALE: audit predates the root commit"; exit 1
      else echo "FRESH: repository remains unborn"; exit 0; fi
    fi
    git rev-parse -q --verify "$head^{commit}" >/dev/null 2>&1 || { echo "git-intent: head '$head' does not resolve" >&2; exit 2; }
    git rev-parse -q --verify "$tree^{tree}" >/dev/null 2>&1 || { echo "git-intent: audit tree '$tree' does not resolve" >&2; exit 2; }
    if ! git merge-base --is-ancestor "$ground" "$head" 2>/dev/null; then echo "DIVERGED: $ground is not an ancestor of $head"; exit 1; fi
    case "$audit" in
      "$root"/*) audit_path=${audit#"$root"/} ;;
      ./*) audit_path=${audit#./} ;;
      *) audit_path=$audit ;;
    esac
    changed=$(git diff --name-only "$tree" "$head^{tree}" -- 2>/dev/null | grep -vxF "$audit_path" || true)
    [ -n "$changed" ] || { echo "FRESH: head matches the audited tree"; exit 0; }
    if [ "$mode" = full ]; then
      first=$(printf '%s\n' "$changed" | sed -n '1p')
      echo "STALE: repository-wide audited tree differs at $first"
      exit 1
    fi
    watched=$(
      {
        sed -n 's/^paths:[[:space:]]*//p' "$audit" | tr '[],' '   ' | tr ' ' '\n'
        sed -n 's/^    evidence:[[:space:]]*//p; s/^evidence:[[:space:]]*//p' "$audit" |
          tr '[],' '   ' | tr ' ' '\n' | sed -n 's/^repo://p'
      } | sed 's/#.*//' | sed '/^$/d' | sort -u
    )
    for path in $watched; do
      for landed in $changed; do
        if [ "$landed" = "$path" ]; then echo "STALE: changed evidence $landed"; exit 1; fi
        case "$landed" in "$path"/*) echo "STALE: changed evidence $landed"; exit 1 ;; esac
        case "$path" in "$landed"/*) echo "STALE: changed evidence $landed"; exit 1 ;; esac
      done
    done
    if grep -q '^domains:[[:space:]]*\[[^]]' "$audit" &&
      printf '%s\n' "$changed" | grep -Eq '^\.intent/(DOMAINS|CONTRACTS|CONSTRAINTS)\.ya?ml$'; then
      echo "STALE: selected-domain governance changed since the audited tree"
      exit 1
    fi
    echo "FRESH: head differs only outside the recorded scope and evidence"
    ;;
  *) usage ;;
esac
