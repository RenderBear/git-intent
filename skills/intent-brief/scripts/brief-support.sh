#!/bin/sh
# Deterministic brief mechanics: derived path addressing, domain-governance
# projection, causal digest freshness, verifier selection, and trailer honesty.
# Choosing semantic domains and interpreting constraints remain model work.

set -u

usage() {
  cat >&2 <<'EOF'
usage:
  brief-support.sh map
  brief-support.sh rows <domain> [<domain>...]
  brief-support.sh digest <domain> [<domain>...]
  brief-support.sh observe <expected-digest> <domain> [<domain>...]
  brief-support.sh reach [<base-ref>|--root] [--paths <path>...]
                         [--domain <id>]... [--interface <name>]...
  brief-support.sh verifiers [<base-ref>|--root] [--paths <path>...]
                             [--domain <id>]... [--interface <name>]...
      Reach and verifier selection combine mechanical path/interface
      intersections with semantic domains selected by the caller. Contracts
      are executable boundary promises. Constraints always emit REVIEW and
      may additionally emit executable VERIFY rows.
  brief-support.sh message <subject> --unit <id>... --scope <derived-scope>...
                           [--domain <id>...] [--plan <plan-id>]
  brief-support.sh trailer <commit>
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

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runtime_script="$script_dir/../../intent-coordinate/scripts/runtime-support.sh"
domains_file=.intent/DOMAINS.yml
contracts_file=.intent/CONTRACTS.yml
constraints_file=.intent/CONSTRAINTS.yml

slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g'; }
normalise_refs() { printf '%s' "$1" | tr -d '[],' | tr ' ' '\n' | sed '/^$/d'; }

domain_rows() {
  [ -f "$domains_file" ] || return 0
  awk '
    function val(line){sub(/^[^:]*: */,"",line); sub(/[[:space:]]+#.*$/, "", line); gsub(/\|/,"%7C",line); return line}
    function emit(){if(id!="") print id "|" parent "|" description "|" material "|" authority}
    /^  - id:/ {emit(); id=val($0); parent=description=material=authority=""; next}
    id!="" && /^    parent:/ {parent=val($0); next}
    id!="" && /^    description:/ {description=val($0); next}
    id!="" && /^    material:/ {material=val($0); next}
    id!="" && /^    authority:/ {authority=val($0); next}
    END{emit()}
  ' "$domains_file"
}

contract_rows() {
  [ -f "$contracts_file" ] || return 0
  awk '
    function val(line){sub(/^[^:]*: */,"",line); sub(/[[:space:]]+#.*$/, "", line); gsub(/\|/,"%7C",line); return line}
    function emit(){if(id!="") print id "|" between "|" surfaces "|" material "|" verifies "|" assertion "|" authority}
    /^  - id:/ {emit(); id=val($0); between=surfaces=material=verifies=assertion=authority=""; next}
    id!="" && /^    between:/ {between=val($0); next}
    id!="" && /^    surfaces:/ {surfaces=val($0); next}
    id!="" && /^    material:/ {material=val($0); next}
    id!="" && /^    verifies:/ {verifies=val($0); next}
    id!="" && /^    assertion:/ {assertion=val($0); next}
    id!="" && /^    authority:/ {authority=val($0); next}
    END{emit()}
  ' "$contracts_file"
}

constraint_rows() {
  [ -f "$constraints_file" ] || return 0
  awk '
    function val(line){sub(/^[^:]*: */,"",line); sub(/[[:space:]]+#.*$/, "", line); gsub(/\|/,"%7C",line); return line}
    function emit(){if(id!="") print id "|" applies "|" surfaces "|" material "|" verifies "|" assertion "|" authority}
    /^  - id:/ {emit(); id=val($0); applies=surfaces=material=verifies=assertion=authority=""; next}
    id!="" && /^    applies_to:/ {applies=val($0); next}
    id!="" && /^    surfaces:/ {surfaces=val($0); next}
    id!="" && /^    material:/ {material=val($0); next}
    id!="" && /^    verifies:/ {verifies=val($0); next}
    id!="" && /^    assertion:/ {assertion=val($0); next}
    id!="" && /^    authority:/ {authority=val($0); next}
    END{emit()}
  ' "$constraints_file"
}

is_test_dir() { case "$1" in tests|test|spec|__tests__) return 0 ;; *) return 1 ;; esac; }

derived_ids_for_path() {
  p=$1
  case "$p" in .intent|.intent/*) return 0 ;; esac
  case "$p" in
    */*)
      top=${p%%/*}
      case "$top" in .*) printf 'area.root\n'; return 0 ;; esac
      printf 'area.%s\n' "$(slug "$top")"
      dir=${p%/*}
      while :; do
        for marker in package.json pyproject.toml Cargo.toml go.mod; do
          if [ -f "$dir/$marker" ]; then printf 'pkg.%s\n' "$(slug "${dir##*/}")"; break; fi
        done
        case "$dir" in */*) dir=${dir%/*} ;; *) break ;; esac
      done
      ;;
    *) printf 'area.root\n' ;;
  esac
}

# Enumerate mechanical scopes already present in a committed tree without
# consulting semantic governance or the current checkout. Package scopes come
# from package-root marker paths; area scopes come from repository topology.
scopes_for_tree() {
  ref=$1
  git ls-tree -r --name-only "$ref" -- 2>/dev/null | while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in .intent|.intent/*) continue ;; esac
    case "$p" in
      */*)
        top=${p%%/*}
        if [ "${top#.}" != "$top" ]; then printf 'area.root\n'
        else printf 'area.%s\n' "$(slug "$top")"
        fi
        name=${p##*/}
        case "$name" in
          package.json|pyproject.toml|Cargo.toml|go.mod)
            dir=${p%/*}
            printf 'pkg.%s\n' "$(slug "${dir##*/}")"
            ;;
        esac
        ;;
      *) printf 'area.root\n' ;;
    esac
  done | sort -u
}

do_map() {
  git ls-files -- 2>/dev/null | awk -F/ '
    $1==".intent" {next}
    NF>1 {if(substr($1,1,1)==".") root=1; else dirs[$1]=1; next}
    {root=1}
    END {n=0; for(d in dirs) a[++n]=d; for(i=1;i<n;i++)for(j=i+1;j<=n;j++)if(a[j]<a[i]){t=a[i];a[i]=a[j];a[j]=t}; for(i=1;i<=n;i++)print a[i]; if(root)print "."}
  ' | while IFS= read -r dir; do
    if [ "$dir" = . ]; then printf 'BOUNDARY: area.root .\n'
    elif is_test_dir "$dir"; then printf 'ATTACH: %s — canonical test paths attach to code boundaries\n' "$dir"
    else printf 'BOUNDARY: area.%s %s\n' "$(slug "$dir")" "$dir"
    fi
  done
}

changed_paths() {
  base=${1:-}
  {
    if [ -n "$base" ]; then git diff --name-only "$base" HEAD -- 2>/dev/null
    else git diff --name-only HEAD -- 2>/dev/null; git diff --name-only --cached -- 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null
    fi
  } | sed '/^$/d' | sort -u
}

collect_inputs() {
  path_file=$1; domain_file=$2; interface_file=$3; base_file=$4; shift 4
  : >"$path_file"; : >"$domain_file"; : >"$interface_file"; : >"$base_file"
  explicit_paths=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) printf '%s\n' --root >"$base_file"; shift ;;
      --domain) [ "$#" -ge 2 ] || usage; printf '%s\n' "$2" >>"$domain_file"; shift 2 ;;
      --interface) [ "$#" -ge 2 ] || usage; printf '%s\n' "$2" >>"$interface_file"; shift 2 ;;
      --paths)
        explicit_paths=1; shift
        while [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; do printf '%s\n' "$1" >>"$path_file"; shift; done
        ;;
      --*) usage ;;
      *) [ ! -s "$base_file" ] || usage; printf '%s\n' "$1" >"$base_file"; shift ;;
    esac
  done
  if [ "$explicit_paths" -eq 0 ]; then
    base=$(sed -n '1p' "$base_file")
    if [ "$base" = --root ]; then git ls-tree -r --name-only HEAD -- 2>/dev/null >"$path_file"
    else changed_paths "$base" >"$path_file"
    fi
  fi
  sort -u "$path_file" -o "$path_file"; sort -u "$domain_file" -o "$domain_file"; sort -u "$interface_file" -o "$interface_file"
}

expand_domains() {
  selected=$1; expanded=$2
  cp "$selected" "$expanded"
  rows=$(mktemp "${TMPDIR:-/tmp}/git-intent-domains.XXXXXX") || exit 2
  domain_rows >"$rows"
  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    while IFS= read -r domain; do
      [ -n "$domain" ] || continue
      if ! cut -d'|' -f1 "$rows" | grep -qxF "$domain"; then
        rm -f "$rows"; echo "git-intent: unknown semantic domain '$domain'" >&2; return 1
      fi
      parent=$(awk -F'|' -v d="$domain" '$1==d {print $2; exit}' "$rows")
      if [ -n "$parent" ] && ! grep -qxF "$parent" "$expanded"; then printf '%s\n' "$parent" >>"$expanded"; changed=1; fi
    done <"$expanded"
    sort -u "$expanded" -o "$expanded"
  done
  rm -f "$rows"
}

path_hits() {
  wanted=$1; locators=$2
  for locator in $(normalise_refs "$locators"); do
    case "$locator" in task:*|url:*|interface:*) continue ;; esac
    path=${locator#*:}; path=${path%%#*}; path=${path%%::*}
    while IFS= read -r changed; do
      [ -n "$changed" ] || continue
      [ "$changed" = "$path" ] && return 0
      case "$changed" in "$path"/*) return 0 ;; esac
      case "$path" in "$changed"/*) return 0 ;; esac
    done <"$wanted"
  done
  return 1
}

interface_hits() {
  wanted=$1; surfaces=$2
  for locator in $(normalise_refs "$surfaces"); do
    case "$locator" in interface:*) grep -qxF "${locator#interface:}" "$wanted" && return 0 ;; esac
  done
  return 1
}

domain_hits() {
  expanded=$1; refs=$2
  for domain in $(normalise_refs "$refs"); do grep -qxF "$domain" "$expanded" && return 0; done
  return 1
}

governance_change_class() {
  paths=$1; base=$2
  if ! grep -Eq '^\.intent/(DOMAINS|CONTRACTS|CONSTRAINTS)\.yml$' "$paths"; then echo none; return; fi
  if [ -z "$base" ] || [ "$base" = --root ]; then
    # A new untracked governance file is additive. Any edit to an existing one
    # is conservatively gated until the prospective-tree diff can classify it.
    existing_change=0
    for f in .intent/DOMAINS.yml .intent/CONTRACTS.yml .intent/CONSTRAINTS.yml; do
      git ls-files --error-unmatch "$f" >/dev/null 2>&1 || continue
      git diff --quiet HEAD -- "$f" 2>/dev/null || existing_change=1
    done
    [ "$existing_change" -eq 0 ] && echo open || echo gated
    return
  fi
  if git diff --unified=0 "$base" HEAD -- .intent/DOMAINS.yml .intent/CONTRACTS.yml .intent/CONSTRAINTS.yml 2>/dev/null |
      grep '^-' | grep -v '^---' >/dev/null 2>&1; then echo gated; else echo open; fi
}

compile_affected() {
  paths=$1; selected=$2; interfaces=$3; out=$4
  : >"$out"
  contract_rows | while IFS='|' read -r id refs surfaces material verifies assertion authority; do
    level=""
    if domain_hits "$selected" "$refs" || path_hits "$paths" "$surfaces" || interface_hits "$interfaces" "$surfaces"; then level=bounded; fi
    if path_hits "$paths" "$material" || path_hits "$paths" "$verifies"; then level=open; fi
    [ -z "$level" ] || printf 'contract|%s|%s|%s|%s\n' "$id" "$level" "$verifies" "$assertion"
  done >>"$out"
  constraint_rows | while IFS='|' read -r id refs surfaces material verifies assertion authority; do
    level=""
    if domain_hits "$selected" "$refs" || path_hits "$paths" "$surfaces" || interface_hits "$interfaces" "$surfaces"; then level=bounded; fi
    if path_hits "$paths" "$material" || path_hits "$paths" "$verifies"; then level=open; fi
    [ -z "$level" ] || printf 'constraint|%s|%s|%s|%s\n' "$id" "$level" "$verifies" "$assertion"
  done >>"$out"
}

with_inputs() {
  mode=$1; shift
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-brief.XXXXXX") || exit 2
  trap 'rm -rf "$tmp"' EXIT HUP INT TERM
  paths="$tmp/paths"; selected="$tmp/selected"; interfaces="$tmp/interfaces"; base_file="$tmp/base"; expanded="$tmp/expanded"; affected="$tmp/affected"
  collect_inputs "$paths" "$selected" "$interfaces" "$base_file" "$@"
  expand_domains "$selected" "$expanded" || exit 2
  compile_affected "$paths" "$expanded" "$interfaces" "$affected"
  base=$(sed -n '1p' "$base_file")
  [ "$base" != --root ] || base=""

  if [ "$mode" = verifiers ]; then
    while IFS='|' read -r kind id level verifies assertion; do
      if [ "$kind" = constraint ]; then printf 'REVIEW: constraint:%s %s\n' "$id" "$assertion"; fi
      for verifier in $(normalise_refs "$verifies"); do printf 'VERIFY: %s:%s %s\n' "$kind" "$id" "$verifier"; done
    done <"$affected"
    return
  fi

  scopes="$tmp/scopes"; base_scopes="$tmp/base-scopes"; : >"$scopes"; : >"$base_scopes"
  while IFS= read -r path; do derived_ids_for_path "$path"; done <"$paths" | sort -u >"$scopes"
  while IFS= read -r scope; do [ -z "$scope" ] || printf 'TOPOLOGY: %s\n' "$scope"; done <"$scopes"
  comparison_base=$base
  if [ -z "$comparison_base" ]; then comparison_base=$(git rev-parse -q --verify HEAD 2>/dev/null || true); fi
  if [ -n "$comparison_base" ]; then
    scopes_for_tree "$comparison_base" >"$base_scopes"
    while IFS= read -r scope; do
      [ -n "$scope" ] || continue
      # Canonical test directories attach to code boundaries and are not new
      # semantic topology by themselves.
      case "$scope" in area.tests|area.test|area.spec|area.__tests__) continue ;; esac
      grep -qxF "$scope" "$base_scopes" || printf 'TOPOLOGY-NEW: %s\n' "$scope"
    done <"$scopes"
  fi
  while IFS='|' read -r kind id level verifies assertion; do
    printf 'AFFECTED: %s:%s (%s)\n' "$kind" "$id" "$level"
    [ "$kind" != constraint ] || printf 'REVIEW: constraint:%s %s\n' "$id" "$assertion"
  done <"$affected"

  structural=$(governance_change_class "$paths" "$base")
  case "$structural" in
    gated) echo "GOVERNANCE: existing accepted record changed or removed"; verdict=gated ;;
    open) echo "GOVERNANCE: additive record establishment"; verdict=open ;;
    *)
      if grep -q '|open|' "$affected"; then verdict=open
      elif [ -s "$affected" ]; then verdict=bounded
      else verdict=local
      fi
      ;;
  esac
  printf 'REACH: %s\n' "$verdict"
}

governing_content() {
  selected=$(mktemp "${TMPDIR:-/tmp}/git-intent-selected.XXXXXX") || exit 2
  expanded=$(mktemp "${TMPDIR:-/tmp}/git-intent-expanded.XXXXXX") || { rm -f "$selected"; exit 2; }
  : >"$selected"; for domain do printf '%s\n' "$domain" >>"$selected"; done; sort -u "$selected" -o "$selected"
  expand_domains "$selected" "$expanded" || { rm -f "$selected" "$expanded"; return 2; }
  domain_rows | while IFS='|' read -r id parent description material authority; do
    grep -qxF "$id" "$expanded" && printf 'DOMAIN|%s|%s|%s|%s|%s\n' "$id" "$parent" "$description" "$material" "$authority"
  done
  contract_rows | while IFS='|' read -r id refs surfaces material verifies assertion authority; do
    domain_hits "$expanded" "$refs" && printf 'CONTRACT|%s|%s|%s|%s|%s|%s|%s\n' "$id" "$refs" "$surfaces" "$material" "$verifies" "$assertion" "$authority"
  done
  constraint_rows | while IFS='|' read -r id refs surfaces material verifies assertion authority; do
    domain_hits "$expanded" "$refs" && printf 'CONSTRAINT|%s|%s|%s|%s|%s|%s|%s\n' "$id" "$refs" "$surfaces" "$material" "$verifies" "$assertion" "$authority"
  done
  rm -f "$selected" "$expanded"
}

do_rows() {
  content=$(governing_content "$@") || exit 2
  printf '%s\n' "$content" | awk -F'|' '
    $1=="DOMAIN" {print "DOMAIN " $2 " — " $4; n++}
    $1=="CONTRACT" {print "CONTRACT " $2 " — " $7; n++}
    $1=="CONSTRAINT" {print "CONSTRAINT " $2 " — " $7; n++}
    END {print "ROWS: " n+0}
  '
}

compute_digest() { governing_content "$@" | sort | git hash-object --stdin; }
do_digest() { printf 'DIGEST: %s\n' "$(compute_digest "$@")"; }
do_observe() {
  [ "$#" -ge 1 ] || usage; expected=$1; shift; actual=$(compute_digest "$@")
  if [ "$actual" = "$expected" ]; then echo "OBSERVED: $actual"; else echo "STALE: expected $expected actual $actual"; return 1; fi
}

do_message() {
  [ "$#" -ge 1 ] || usage; subject=$1; shift
  units=""; scopes=""; domains=""; plan=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --unit) [ "$#" -ge 2 ] || usage; units="$units $2"; shift 2 ;;
      --scope) [ "$#" -ge 2 ] || usage; scopes="$scopes $2"; shift 2 ;;
      --domain) [ "$#" -ge 2 ] || usage; domains="$domains $2"; shift 2 ;;
      --plan) [ "$#" -ge 2 ] || usage; plan=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$units" ] && [ -n "$scopes" ] || usage
  plan_file=""
  if [ -n "$plan" ]; then
    runtime=$(sh "$runtime_script" root) || exit 2; plan_file="$runtime/plans/$plan.yml"
    [ -f "$plan_file" ] || { echo "git-intent: no plan '$plan' to stamp" >&2; exit 2; }
  fi
  printf '%s\n\n' "$subject"
  for unit in $units; do printf 'Intent-Unit: %s\n' "$unit"; done
  for scope in $scopes; do printf 'Intent-Scope: %s\n' "$scope"; done
  for domain in $domains; do printf 'Intent-Domain: %s\n' "$domain"; done
  if [ -n "$plan_file" ]; then
    printf 'Intent-Plan: %s\n' "$plan"
    set -- $(cksum <"$plan_file"); printf 'Intent-Plan-Digest: %s-%s\n' "$1" "$2"
  fi
}

do_trailer() {
  [ "$#" -eq 1 ] || usage; commit=$1
  claimed=$(git log -1 --format='%(trailers:key=Intent-Scope,valueonly,separator=%x0a)' "$commit" 2>/dev/null | sed '/^$/d')
  [ -n "$claimed" ] || { echo "TRAILER: missing Intent-Scope on $commit"; return 1; }
  domains=$(git log -1 --format='%(trailers:key=Intent-Domain,valueonly,separator=%x0a)' "$commit" 2>/dev/null | sed '/^$/d')
  for domain in $domains; do domain_rows | cut -d'|' -f1 | grep -qxF "$domain" || { echo "TRAILER: unknown Intent-Domain $domain"; return 1; }; done
  if git rev-parse -q --verify "$commit^" >/dev/null 2>&1; then diff_paths=$(git diff --name-only "$commit^" "$commit")
  else diff_paths=$(git diff-tree --no-commit-id --name-only -r --root "$commit"); fi
  bad=""
  for path in $diff_paths; do
    case "$path" in .intent|.intent/*) continue ;; esac
    top=${path%%/*}; is_test_dir "$top" && continue
    covered=0
    ids=$(derived_ids_for_path "$path")
    for claim in $claimed; do
      for id in $ids; do
        [ "$claim" = "$id" ] && covered=1
        case "$claim" in "$id".*) covered=1 ;; esac
        case "$id" in "$claim".*) covered=1 ;; esac
      done
    done
    [ "$covered" -eq 1 ] || bad="$bad $path"
  done
  [ -z "$bad" ] || { echo "TRAILER: claimed scopes do not contain:$bad"; return 1; }
  echo "TRAILER: OK $(printf '%s' "$claimed" | tr '\n' ' ')"
}

case "$cmd" in
  map) [ "$#" -eq 0 ] || usage; do_map ;;
  rows) do_rows "$@" ;;
  digest) do_digest "$@" ;;
  observe) do_observe "$@" ;;
  reach) with_inputs reach "$@" ;;
  verifiers) with_inputs verifiers "$@" ;;
  message) do_message "$@" ;;
  trailer) do_trailer "$@" ;;
  *) usage ;;
esac
