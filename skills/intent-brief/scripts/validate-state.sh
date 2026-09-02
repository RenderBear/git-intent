#!/bin/sh
# Validate tracked git-intent state. Domains are semantic: validation checks
# identity, references, and material, never filesystem membership. Ignored
# runtime planning is deliberately outside this validator.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "${1:-}" in --landing|--audit) shift ;; esac

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-state.XXXXXX") || exit 2
domains="$tmp_root/domains"
contracts="$tmp_root/contracts"
constraints="$tmp_root/constraints"
observations="$tmp_root/observations"
audits="$tmp_root/audits"
violations="$tmp_root/violations"
files="$tmp_root/files"
: >"$domains"; : >"$contracts"; : >"$constraints"; : >"$observations"; : >"$audits"; : >"$violations"; : >"$files"
cleanup() { rm -rf "$tmp_root"; }
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL %s\n' "$*"
  printf '%s\n' "$*" >>"$violations"
}

git ls-files --cached --others --exclude-standard -- '.intent/' 2>/dev/null |
  grep '\.ya\{0,1\}ml$' | sort -u >"$files" || true
for named do printf '%s\n' "$named" >>"$files"; done
sort -u "$files" -o "$files"

if [ ! -s "$files" ]; then
  echo "no intent state — nothing to validate"
  exit 0
fi

parse_domains() {
  awk -v file="$1" '
    function val(line) { sub(/^[^:]*: */,"",line); sub(/[[:space:]]+#.*$/, "", line); return line }
    function emit() { if(id!="") print "D|" file "|" id "|" description "|" authority "|" parent "|" material }
    /^[a-z_]+:/ {
      key=$0; sub(/:.*/,"",key)
      if(key!="version" && key!="domains") print "E|" file "|top|unknown top-level field " key
      next
    }
    /^  - id:/ { emit(); delete seen; id=val($0); description=authority=parent=material=""; next }
    id!="" && /^    [a-z_]+:/ {
      key=$0; sub(/^    /,"",key); sub(/:.*/,"",key); seen[key]++
      if(seen[key]>1) print "E|" file "|" id "|duplicate field " key
      value=val($0)
      if(key=="description") description=value
      else if(key=="authority") authority=value
      else if(key=="parent") parent=value
      else if(key=="material") { material=value; if(value !~ /^\[.*\]$/) print "E|" file "|" id "|material must be an inline list" }
      else print "E|" file "|" id "|unknown domain field " key
    }
    END { emit() }
  ' "$1"
}

parse_contracts() {
  awk -v file="$1" '
    function val(line) { sub(/^[^:]*: */,"",line); sub(/[[:space:]]+#.*$/, "", line); return line }
    function emit() { if(id!="") print "C|" file "|" id "|" assertion "|" authority "|" between "|" surfaces "|" material "|" verifies }
    /^[a-z_]+:/ {
      key=$0; sub(/:.*/,"",key)
      if(key!="version" && key!="contracts") print "E|" file "|top|unknown top-level field " key
      next
    }
    /^  - id:/ { emit(); delete seen; id=val($0); assertion=authority=between=surfaces=material=verifies=""; next }
    id!="" && /^    [a-z_]+:/ {
      key=$0; sub(/^    /,"",key); sub(/:.*/,"",key); seen[key]++
      if(seen[key]>1) print "E|" file "|" id "|duplicate field " key
      value=val($0)
      if(key=="assertion") assertion=value
      else if(key=="authority") authority=value
      else if(key=="between" || key=="surfaces" || key=="material" || key=="verifies") {
        if(value !~ /^\[.*\]$/) print "E|" file "|" id "|" key " must be an inline list"
        if(key=="between") between=value
        else if(key=="surfaces") surfaces=value
        else if(key=="material") material=value
        else verifies=value
      } else print "E|" file "|" id "|unknown contract field " key
    }
    END { emit() }
  ' "$1"
}

parse_constraints() {
  awk -v file="$1" '
    function val(line) { sub(/^[^:]*: */,"",line); sub(/[[:space:]]+#.*$/, "", line); return line }
    function emit() { if(id!="") print "N|" file "|" id "|" assertion "|" authority "|" applies "|" surfaces "|" material "|" verifies }
    /^[a-z_]+:/ {
      key=$0; sub(/:.*/,"",key)
      if(key!="version" && key!="constraints") print "E|" file "|top|unknown top-level field " key
      next
    }
    /^  - id:/ { emit(); delete seen; id=val($0); assertion=authority=applies=surfaces=material=verifies=""; next }
    id!="" && /^    [a-z_]+:/ {
      key=$0; sub(/^    /,"",key); sub(/:.*/,"",key); seen[key]++
      if(seen[key]>1) print "E|" file "|" id "|duplicate field " key
      value=val($0)
      if(key=="assertion") assertion=value
      else if(key=="authority") authority=value
      else if(key=="applies_to" || key=="surfaces" || key=="material" || key=="verifies") {
        if(value !~ /^\[.*\]$/) print "E|" file "|" id "|" key " must be an inline list"
        if(key=="applies_to") applies=value
        else if(key=="surfaces") surfaces=value
        else if(key=="material") material=value
        else verifies=value
      } else print "E|" file "|" id "|unknown constraint field " key
    }
    END { emit() }
  ' "$1"
}

parse_observation() {
  awk -v file="$1" '
    function val(line) { sub(/^[^:]*: */,"",line); sub(/[[:space:]]+#.*$/, "", line); return line }
    /^[a-z_]+:/ {
      key=$0; sub(/:.*/,"",key); seen[key]++
      if(seen[key]>1) print "E|" file "|observation|duplicate field " key
      value=val($0)
      if(key=="id") id=value
      else if(key=="ground") ground=value
      else if(key=="statement") statement=value
      else if(key=="evidence") { evidence=value; if(value !~ /^\[.*\]$/) print "E|" file "|observation|evidence must be an inline list" }
      else if(key=="relates_to") { relates=value; if(value !~ /^\[.*\]$/) print "E|" file "|observation|relates_to must be an inline list" }
      else if(key!="version") print "E|" file "|observation|unknown field " key
    }
    END { print "O|" file "|" id "|" ground "|" statement "|" evidence "|" relates }
  ' "$1"
}

parse_audit() {
  awk -v file="$1" '
    function val(line) { sub(/^[^:]*: */,"",line); sub(/[[:space:]]+#.*$/, "", line); return line }
    function emit() { if(fid!="") print "F|" file "|" fid "|" summary "|" evidence "|" proposed "|" disposition "|" authority }
    /^[a-z_]+:/ {
      emit(); fid=""
      key=$0; sub(/:.*/,"",key); seen[key]++; if(seen[key]>1) print "E|" file "|audit|duplicate field " key
      value=val($0)
      if(key=="id") id=value
      else if(key=="ground") ground=value
      else if(key=="tree") tree=value
      else if(key=="mode") mode=value
      else if(key=="domains" || key=="paths") {
        if(value !~ /^\[.*\]$/) print "E|" file "|audit|" key " must be an inline list"
        if(key=="domains") domains=value; else paths=value
      }
      else if(key=="findings") { findings=1; if(value!="" && value!="[]") print "E|" file "|audit|findings must be a list or []" }
      else if(key!="version") print "E|" file "|audit|unknown field " key
      next
    }
    /^  - id:/ { emit(); fid=val($0); summary=evidence=proposed=disposition=authority=""; next }
    fid!="" && /^    [a-z_]+:/ {
      key=$0; sub(/^    /,"",key); sub(/:.*/,"",key); fseen[fid SUBSEP key]++
      if(fseen[fid SUBSEP key]>1) print "E|" file "|" fid "|duplicate field " key
      value=val($0)
      if(key=="summary") summary=value
      else if(key=="evidence") { evidence=value; if(value !~ /^\[.*\]$/) print "E|" file "|" fid "|evidence must be an inline list" }
      else if(key=="proposed") proposed=value
      else if(key=="disposition") disposition=value
      else if(key=="authority") authority=value
      else print "E|" file "|" fid "|unknown finding field " key
    }
    END { emit(); print "A|" file "|" id "|" ground "|" tree "|" mode "|" findings "|" domains "|" paths }
  ' "$1"
}

while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -f "$file" ] || { fail "$file does not exist"; continue; }
  grep -q '^version: 1$' "$file" || fail "$file must declare version: 1"
  case "$file" in
    .intent/config.yml|*/.intent/config.yml)
      if ! error=$(sh "$script_dir/resolve-config.sh" 2>&1 >/dev/null); then
        fail "$file $(printf '%s' "$error" | sed 's/^git-intent: //')"
      fi
      ;;
    .intent/DOMAINS.yml|*/.intent/DOMAINS.yml)
      grep -q '^domains:$' "$file" || fail "$file must contain a domains list"
      grep -q '^  - id:' "$file" || fail "$file contains no domains; remove it"
      parse_domains "$file" >>"$domains"
      ;;
    .intent/CONTRACTS.yml|*/.intent/CONTRACTS.yml)
      grep -q '^contracts:$' "$file" || fail "$file must contain a contracts list"
      grep -q '^  - id:' "$file" || fail "$file contains no contracts; remove it"
      parse_contracts "$file" >>"$contracts"
      ;;
    .intent/CONSTRAINTS.yml|*/.intent/CONSTRAINTS.yml)
      grep -q '^constraints:$' "$file" || fail "$file must contain a constraints list"
      grep -q '^  - id:' "$file" || fail "$file contains no constraints; remove it"
      parse_constraints "$file" >>"$constraints"
      ;;
    .intent/audits/*.yml|*/.intent/audits/*.yml)
      parse_audit "$file" >>"$audits"
      ;;
    .intent/observations/*.yml|*/.intent/observations/*.yml)
      parse_observation "$file" >>"$observations"
      ;;
    *) fail "$file is not a version-1 config, domain, contract, constraint, audit, or observation file" ;;
  esac
done <"$files"

awk -F'|' '$1=="E" { print $2 "|" $3 "|" $4 }' "$domains" "$contracts" "$constraints" "$observations" "$audits" |
while IFS='|' read -r file id message; do fail "$file:$id $message"; done

normalise_refs() { printf '%s' "$1" | tr -d '[],' | tr ' ' '\n' | sed '/^$/d'; }
valid_id() { case "$1" in ''|.*|*..*|*.) return 1 ;; *[!a-zA-Z0-9._-]*) return 1 ;; *) return 0 ;; esac; }

check_authority() {
  locator=$1 label=$2
  case "$locator" in
    user:task:*|user:url:http://*|user:url:https://*|design:task:*|design:url:http://*|design:url:https://*) ;;
    architecture:repo:*|design:repo:*)
      path=${locator#*:repo:}; path=${path%%#*}; [ -e "$path" ] || fail "$label authority target '$path' does not exist" ;;
    *) fail "$label authority is not an inspectable user:, design:, or architecture: locator" ;;
  esac
}

check_material() {
  locator=$1 label=$2
  case "$locator" in
    repo:*|architecture:*|adr:*|schema:*)
      path=${locator#*:}; path=${path%%#*}; [ -e "$path" ] || fail "$label material '$path' does not exist" ;;
    task:*|url:http://*|url:https://*) ;;
    *) fail "$label material '$locator' must use repo:, architecture:, adr:, schema:, task:, or url:" ;;
  esac
}

check_surface() {
  locator=$1 label=$2
  case "$locator" in
    repo:*) path=${locator#repo:}; path=${path%%#*}; [ -e "$path" ] || fail "$label surface '$path' does not exist" ;;
    interface:?*) ;;
    *) fail "$label surface '$locator' must use repo: or interface:" ;;
  esac
}

check_verifier() {
  locator=$1 label=$2
  case "$locator" in
    command:*) path=${locator#command:}; [ -f "$path" ] || fail "$label verifier '$path' does not exist"; [ -x "$path" ] || fail "$label command verifier '$path' is not executable" ;;
    test:*) path=${locator#test:}; path=${path%%::*}; [ -f "$path" ] || fail "$label verifier '$path' does not exist" ;;
    schema:*) path=${locator#schema:}; path=${path%%#*}; [ -f "$path" ] || fail "$label verifier '$path' does not exist" ;;
    *) fail "$label verifier '$locator' must use command:, test:, or schema:" ;;
  esac
}

check_evidence() {
  locator=$1 label=$2 at=${3:-}
  case "$locator" in
    repo:*)
      path=${locator#repo:}; path=${path%%#*}
      if [ -n "$at" ] && [ "$at" != unborn ] && [ "$at" != empty ]; then
        git cat-file -e "$at:$path" 2>/dev/null || fail "$label evidence '$path' does not exist at $at"
      else
        [ -e "$path" ] || fail "$label evidence '$path' does not exist"
      fi
      ;;
    commit:*) ref=${locator#commit:}; git rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 || fail "$label evidence commit '$ref' does not resolve" ;;
    interface:?*|task:*|url:http://*|url:https://*) ;;
    *) fail "$label evidence '$locator' must use repo:, commit:, interface:, task:, or url:" ;;
  esac
}

domain_ids="$tmp_root/domain-ids"
awk -F'|' '$1=="D" { print $3 }' "$domains" >"$domain_ids"
sort "$domain_ids" | uniq -d | while IFS= read -r id; do [ -z "$id" ] || fail "duplicate domain '$id'"; done

edges="$tmp_root/domain-edges"; : >"$edges"
awk -F'|' '$1=="D" { print }' "$domains" |
while IFS='|' read -r _ file id description authority parent material; do
  valid_id "$id" || fail "$file invalid domain id '$id'"
  [ -n "$description" ] || fail "$file:$id missing description"
  check_authority "$authority" "$file:$id"
  if [ -n "$parent" ]; then
    grep -qxF "$parent" "$domain_ids" || fail "$file:$id references missing parent '$parent'"
    printf '%s|%s\n' "$id" "$parent" >>"$edges"
  fi
  for locator in $(normalise_refs "$material"); do check_material "$locator" "$file:$id"; done
done

awk -F'|' '$1=="A" { print }' "$audits" |
while IFS='|' read -r _ file id ground tree mode findings selected paths; do
  valid_id "$id" || fail "$file invalid audit id '$id'"
  base=$(basename "$file"); base=${base%.*}; [ "$base" = "$id" ] || fail "$file filename must be $id.yml"
  case "$mode" in scope|full) ;; *) fail "$file invalid audit mode '$mode'" ;; esac
  [ "$findings" = 1 ] || fail "$file missing findings"
  [ -n "$ground" ] || fail "$file missing ground"
  [ -n "$tree" ] || fail "$file missing tree"
  if [ "$ground" != unborn ]; then git rev-parse -q --verify "$ground^{commit}" >/dev/null 2>&1 || fail "$file ground '$ground' does not resolve"; fi
  if [ "$tree" != empty ]; then git rev-parse -q --verify "$tree^{tree}" >/dev/null 2>&1 || fail "$file tree '$tree' does not resolve"; fi
  for domain in $(normalise_refs "$selected"); do grep -qxF "$domain" "$domain_ids" || fail "$file references missing domain '$domain'"; done
  count=0
  for path in $(normalise_refs "$paths"); do
    count=$((count + 1))
    case "$path" in /*|../*|*/../*|*'/..') fail "$file has invalid audit path '$path'"; continue ;; esac
    if [ "$tree" != empty ]; then git cat-file -e "$tree:$path" 2>/dev/null || fail "$file audit path '$path' does not exist in tree $tree"; fi
  done
  [ "$mode" != scope ] || [ "$count" -gt 0 ] || fail "$file scoped audit requires at least one path"
done

awk -F'|' '$1=="F" { print }' "$audits" |
while IFS='|' read -r _ file id summary evidence proposed disposition authority; do
  valid_id "$id" || fail "$file invalid finding id '$id'"
  [ -n "$summary" ] || fail "$file:$id missing summary"
  audit_tree=$(awk -F'|' -v f="$file" '$1=="A" && $2==f { print $5; exit }' "$audits")
  count=0; for locator in $(normalise_refs "$evidence"); do count=$((count + 1)); check_evidence "$locator" "$file:$id" "$audit_tree"; done
  [ "$count" -gt 0 ] || fail "$file:$id requires evidence"
  case "$proposed" in domain|contract|constraint|observation|none) ;; *) fail "$file:$id invalid proposed value '$proposed'" ;; esac
  case "$disposition" in adoptable|needs-authority|needs-verifier|observation-only|no-action) ;; *) fail "$file:$id invalid disposition '$disposition'" ;; esac
  [ -z "$authority" ] || check_authority "$authority" "$file:$id"
done

if [ -s "$edges" ] && ! awk -F'|' '
  function visit(n, i,v) { if(visiting[n]) return 1; if(done[n]) return 0; visiting[n]=1; for(i=1;i<=count[n];i++){v=edge[n,i]; if(visit(v)) return 1} visiting[n]=0; done[n]=1; return 0 }
  { edge[$1,++count[$1]]=$2; nodes[$1]=nodes[$2]=1 }
  END { for(n in nodes) if(visit(n)) exit 1 }
' "$edges"; then fail "domain parent graph contains a cycle"; fi

contract_ids="$tmp_root/contract-ids"
awk -F'|' '$1=="C" { print $3 }' "$contracts" >"$contract_ids"
sort "$contract_ids" | uniq -d | while IFS= read -r id; do [ -z "$id" ] || fail "duplicate contract '$id'"; done
awk -F'|' '$1=="C" { print }' "$contracts" |
while IFS='|' read -r _ file id assertion authority between surfaces material verifies; do
  valid_id "$id" || fail "$file invalid contract id '$id'"
  [ -n "$assertion" ] || fail "$file:$id missing assertion"
  check_authority "$authority" "$file:$id"
  count=0; seen_between=""
  for domain in $(normalise_refs "$between"); do
    count=$((count + 1)); grep -qxF "$domain" "$domain_ids" || fail "$file:$id references missing domain '$domain'"
    case " $seen_between " in *" $domain "*) fail "$file:$id repeats domain '$domain'" ;; esac; seen_between="$seen_between $domain"
  done
  [ "$count" -ge 2 ] || fail "$file:$id requires at least two domains in between"
  count=0; for locator in $(normalise_refs "$surfaces"); do count=$((count + 1)); check_surface "$locator" "$file:$id"; done
  [ "$count" -gt 0 ] || fail "$file:$id requires at least one surface"
  count=0; for locator in $(normalise_refs "$material"); do count=$((count + 1)); check_material "$locator" "$file:$id"; done
  [ "$count" -gt 0 ] || fail "$file:$id requires defining material"
  count=0; for locator in $(normalise_refs "$verifies"); do count=$((count + 1)); check_verifier "$locator" "$file:$id"; done
  [ "$count" -gt 0 ] || fail "$file:$id requires executable verification"
done

constraint_ids="$tmp_root/constraint-ids"
awk -F'|' '$1=="N" { print $3 }' "$constraints" >"$constraint_ids"
sort "$constraint_ids" | uniq -d | while IFS= read -r id; do [ -z "$id" ] || fail "duplicate constraint '$id'"; done
awk -F'|' '$1=="N" { print }' "$constraints" |
while IFS='|' read -r _ file id assertion authority applies surfaces material verifies; do
  valid_id "$id" || fail "$file invalid constraint id '$id'"
  [ -n "$assertion" ] || fail "$file:$id missing assertion"
  check_authority "$authority" "$file:$id"
  count=0; for domain in $(normalise_refs "$applies"); do count=$((count + 1)); grep -qxF "$domain" "$domain_ids" || fail "$file:$id references missing domain '$domain'"; done
  [ "$count" -gt 0 ] || fail "$file:$id requires at least one domain in applies_to"
  for locator in $(normalise_refs "$surfaces"); do check_surface "$locator" "$file:$id"; done
  count=0; for locator in $(normalise_refs "$material"); do count=$((count + 1)); check_material "$locator" "$file:$id"; done
  [ "$count" -gt 0 ] || fail "$file:$id requires defining material"
  for locator in $(normalise_refs "$verifies"); do check_verifier "$locator" "$file:$id"; done
done

awk -F'|' '$1=="O" { print }' "$observations" |
while IFS='|' read -r _ file id ground statement evidence relates; do
  valid_id "$id" || fail "$file invalid observation id '$id'"
  base=$(basename "$file"); base=${base%.*}; [ "$base" = "$id" ] || fail "$file filename must be $id.yml"
  [ -n "$statement" ] || fail "$file:$id missing statement"
  [ -n "$ground" ] || fail "$file:$id missing ground"
  if [ "$ground" != unborn ]; then git rev-parse -q --verify "$ground^{commit}" >/dev/null 2>&1 || fail "$file:$id ground '$ground' does not resolve"; fi
  count=0; for locator in $(normalise_refs "$evidence"); do count=$((count + 1)); check_evidence "$locator" "$file:$id" "$ground"; done
  [ "$count" -gt 0 ] || fail "$file:$id requires evidence"
  for ref in $(normalise_refs "$relates"); do
    case "$ref" in
      domain:*) grep -qxF "${ref#domain:}" "$domain_ids" || fail "$file:$id relates to missing '$ref'" ;;
      contract:*) grep -qxF "${ref#contract:}" "$contract_ids" || fail "$file:$id relates to missing '$ref'" ;;
      constraint:*) grep -qxF "${ref#constraint:}" "$constraint_ids" || fail "$file:$id relates to missing '$ref'" ;;
      *) fail "$file:$id relates_to '$ref' must name domain:, contract:, or constraint:" ;;
    esac
  done
done

if [ -s "$violations" ]; then
  count=$(wc -l <"$violations" | tr -d ' ')
  echo "$count intent state violation(s)"
  exit 1
fi
echo "intent state valid"
