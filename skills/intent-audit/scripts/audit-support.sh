#!/bin/sh
# Deterministic audit evidence. Scoped audit proposes boring area.* route rows
# for an unrouted touch set; full audit emits a repository-wide evidence frame.
# Neither operation writes repository state.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
brief_script="$script_dir/../../intent-brief/scripts/brief-support.sh"
validate_script="$script_dir/../../intent-brief/scripts/validate-state.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  audit-support.sh scope [<base-ref>]
  audit-support.sh scope --paths <path> [<path>...]
      Group the unrouted portion of the current diff (or an intended touch
      set) by top-level directory and emit proposed area.* route rows as a
      ROUTES.yml skeleton on stdout — a full file when no .intent/ROUTES.yml
      exists, appendable rows otherwise. Scope names are deliberately boring
      and stable; routes belong to areas, never to individual changes. The
      agent replaces every REPLACE locator from inspectable sources; the
      current user request supplies authority. Nothing is written and nothing
      is scanned beyond the given paths.
  audit-support.sh full --autonomous
  audit-support.sh full --assisted
      Emit a read-only evidence frame for an explicitly human-requested full
      repository audit. The mode controls whether semantic inspection later
      pauses for material clarification; it does not change authority.
  audit-support.sh recurrence [<n>]
      The seed-offer trigger: scan the last <n> (default 30) first-parent
      landings' Intent-Scope trailers for derived identifiers not yet
      governed by a route, and report each one that recurs as
      RECURRENT: <id> <count>. Recurrence, never first contact, is what
      surfaces the offer — and only in the landing report. Derived from the
      first-parent stream; no counter is persisted.
EOF
  exit 2
}

[ "$#" -ge 1 ] || usage
cmd=$1
shift

case "$cmd" in scope|full|recurrence) ;; *) usage ;; esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git-intent: not inside a Git repository" >&2
  exit 2
}
cd "$root" || exit 2

routes_file=.intent/ROUTES.yml
contracts_file=.intent/CONTRACTS.yml

if [ "$cmd" = "full" ]; then
  [ "$#" -eq 1 ] || usage
  case "$1" in
    --autonomous) mode=autonomous ;;
    --assisted) mode=assisted ;;
    *) usage ;;
  esac

  snapshot=$(git rev-parse --verify HEAD 2>/dev/null || echo unborn)
  if [ -z "$(git status --porcelain=v1 --untracked-files=normal 2>/dev/null)" ]; then
    worktree=clean
  else
    worktree=dirty
  fi
  route_count=$(
    [ -f "$routes_file" ] && awk '/^  - scope:/ { n++ } END { print n + 0 }' "$routes_file" || echo 0
  )
  contract_count=$(
    [ -f "$contracts_file" ] && awk '/^  - id:/ { n++ } END { print n + 0 }' "$contracts_file" || echo 0
  )

  printf 'AUDIT: full\n'
  printf 'MODE: %s\n' "$mode"
  printf 'SNAPSHOT: %s\n' "$snapshot"
  printf 'WORKTREE: %s\n' "$worktree"
  printf 'INTENT-ROWS: routes=%s contracts=%s\n' "$route_count" "$contract_count"

  sh "$brief_script" map

  if [ -f "$routes_file" ]; then
    awk '/^  - scope:/ { line=$0; sub(/^[^:]*: */, "", line); sub(/[[:space:]]+#.*$/, "", line); print "ROUTE: " line }' "$routes_file"
  fi
  if [ -f "$contracts_file" ]; then
    awk '/^  - id:/ { line=$0; sub(/^[^:]*: */, "", line); sub(/[[:space:]]+#.*$/, "", line); print "CONTRACT: " line }' "$contracts_file"
  fi

  git ls-files 2>/dev/null | awk '
    {
      low=tolower($0)
      if (low ~ /(^|\/)(architecture|adr|adrs|decisions)(\/|\.|$)/ ||
          low ~ /(^|\/)(codeowners|readme\.md|openapi[^\/]*|asyncapi[^\/]*|[^\/]*schema[^\/]*)$/)
        print "SOURCE: " $0
      if (low ~ /(^|\/)(makefile|justfile|taskfile\.ya?ml|package\.json|pyproject\.toml|cargo\.toml|go\.mod)$/ ||
          low ~ /^\.github\/workflows\//)
        print "CHECK-SOURCE: " $0
    }
  '

  printf 'STATE-VALIDATION:\n'
  if ! sh "$validate_script" --audit; then
    printf 'AUDIT-FINDING: tracked intent failed mechanical validation\n'
  fi
  printf 'NEXT: inspect critical reliance in bounded batches; unrouted boundaries are not findings by themselves\n'
  exit 0
fi

if [ "$cmd" = "recurrence" ]; then
  n=${1:-30}
  case "$n" in *[!0-9]*|'') usage ;; esac
  routed_scopes=$(
    [ -f "$routes_file" ] &&
      awk '/^  - scope:/ { s=$0; sub(/^[^:]*: */, "", s); sub(/[[:space:]]+#.*$/, "", s); print s }' "$routes_file"
  )
  grouped=$(mktemp "${TMPDIR:-/tmp}/git-intent-recurrence.XXXXXX") || exit 2
  trap 'rm -f "$grouped"' EXIT HUP INT TERM
  for commit in $(git rev-list --first-parent -n "$n" HEAD 2>/dev/null); do
    board=$(git log -1 --format='%(trailers:key=Intent-Board,valueonly)' "$commit" 2>/dev/null | sed '/^$/d' | head -1)
    board_digest=$(git log -1 --format='%(trailers:key=Intent-Board-Digest,valueonly)' "$commit" 2>/dev/null | sed '/^$/d' | head -1)
    [ -z "$board" ] || board="$board@$board_digest"
    [ -n "$board" ] || board=$commit
    git log -1 --format='%(trailers:key=Intent-Scope,valueonly,separator=%x0a)' "$commit" 2>/dev/null |
      sed '/^$/d' | while IFS= read -r scope; do printf '%s\t%s\n' "$board" "$scope"; done
  done | sort -u >"$grouped"
  cut -f2 "$grouped" | sort | uniq -c |
    while read -r count id; do
      [ "$count" -ge 2 ] || continue
      case "$id" in area.*|pkg.*) ;; *) continue ;; esac
      governed=0
      for s in $routed_scopes; do
        [ "$s" = "$id" ] && { governed=1; break; }
      done
      [ "$governed" -eq 1 ] || echo "RECURRENT: $id $count"
    done
  exit 0
fi

# Emit every route path matcher, one per line.
route_matchers() {
  [ -f "$routes_file" ] || return 0
  awk '
    /^  - scope:/ { on=1; next }
    on && /^    paths:/ {
      line=$0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
      n=split(line, a, /[[:space:]]+/)
      for (i=1; i<=n; i++) if (a[i] != "") print a[i]
    }
  ' "$routes_file"
}

# Paths changed since <base>, plus staged, unstaged, and untracked work.
changed_paths() {
  base=${1:-}
  {
    [ -z "$base" ] || git diff --name-only "$base...HEAD" -- 2>/dev/null
    git diff --name-only HEAD -- 2>/dev/null
    git diff --name-only --cached -- 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sed '/^$/d' | sort -u
}

pathset=$(mktemp "${TMPDIR:-/tmp}/git-intent-seed.XXXXXX") || exit 2
trap 'rm -f "$pathset"' EXIT HUP INT TERM
if [ "${1:-}" = "--paths" ]; then
  shift
  [ "$#" -ge 1 ] || usage
  for p do printf '%s\n' "$p"; done | sed '/^$/d' | sort -u >"$pathset"
else
  changed_paths "${1:-}" >"$pathset"
fi

have_routes=0
[ -f "$routes_file" ] && have_routes=1

{
  route_matchers | awk '{ print "M\t" $0 }'
  awk '{ print "P\t" $0 }' "$pathset"
} | awk -F'\t' -v have_routes="$have_routes" '
  $1 == "M" { rm[++nr]=$2; next }
  $1 == "P" { pp[++np]=$2; next }
  function hit(p, m) { return p == m || index(p, m "/") == 1 }
  END {
    nu = 0; nrf = 0
    for (i=1; i<=np; i++) {
      p = pp[i]
      if (p == ".intent" || index(p, ".intent/") == 1) continue
      matched = 0
      for (j=1; j<=nr; j++) if (hit(p, rm[j])) { matched = 1; break }
      if (matched) continue
      ix = index(p, "/")
      if (ix > 0) {
        d = substr(p, 1, ix - 1)
        if (substr(d, 1, 1) == ".") rootfiles[++nrf] = d
        else if (!(d in seen)) { seen[d] = 1; dirs[++nu] = d }
      } else {
        rootfiles[++nrf] = p
      }
    }
    if (nu == 0 && nrf == 0) { print "DISCOVER: 0 — every path is already routed"; exit 0 }
    for (i=1; i<nu; i++) for (j=i+1; j<=nu; j++) if (dirs[j] < dirs[i]) { t=dirs[i]; dirs[i]=dirs[j]; dirs[j]=t }
    if (have_routes)
      print "# discovered candidate rows — append only after authority resolution"
    else {
      print "version: 1"
      print "routes:"
    }
    for (i=1; i<=nu; i++) {
      d = dirs[i]
      s = tolower(d); gsub(/[^a-z0-9_-]/, "-", s)
      print "  - scope: area." s
      print "    paths: [" d "]"
      print "    domain: [user:task:REPLACE-with-current-request-locator]"
    }
    if (nrf > 0) {
      flist = ""
      for (i=1; i<=nrf && i<=24; i++) flist = flist (i>1 ? ", " : "") rootfiles[i]
      print "  - scope: area.root"
      print "    paths: [" flist "]"
      print "    domain: [user:task:REPLACE-with-current-request-locator]"
    }
  }
'
