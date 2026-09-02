#!/bin/sh
# Validate tracked git-intent state. Runtime leases are deliberately out of scope.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

landing=0
audit=0
if [ "${1:-}" = "--landing" ]; then
  landing=1
  shift
elif [ "${1:-}" = "--audit" ]; then
  audit=1
  shift
fi

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-brief.XXXXXX") || exit 2
parsed="$tmp_root/parsed"
exceptions_state="$tmp_root/exceptions"
routes="$tmp_root/routes"
contracts_state="$tmp_root/contracts"
contract_ids="$tmp_root/contract-ids"
ids="$tmp_root/ids"
active_ids="$tmp_root/active-ids"
edges="$tmp_root/edges"
violations="$tmp_root/violations"
all_files="$tmp_root/all-files"
targets="$tmp_root/targets"
audit_findings="$tmp_root/audit-findings"
audit_verifiers="$tmp_root/audit-verifiers"
: >"$audit_findings"
: >"$audit_verifiers"
: >"$parsed"
: >"$exceptions_state"
: >"$routes"
: >"$contracts_state"
: >"$contract_ids"
: >"$ids"
: >"$active_ids"
: >"$edges"
: >"$violations"
: >"$all_files"
: >"$targets"
cleanup() {
  rm -f "$parsed" "$exceptions_state" "$routes" "$contracts_state" "$contract_ids" "$ids" "$active_ids" "$edges" "$violations" "$all_files" "$targets" "$audit_findings" "$audit_verifiers" "$tmp_root/config-error"
  rmdir "$tmp_root" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL %s\n' "$*"
  printf '%s\n' "$*" >>"$violations"
}

# Audit findings are contradictions to disposition, never schema errors: they
# are reported, counted, and left to the landing gate's machinery.
audit_finding() {
  printf 'AUDIT: %s\n' "$*"
  printf '%s\n' "$*" >>"$audit_findings"
}

git ls-files --cached --others --exclude-standard -- '.intent/' 2>/dev/null |
  grep '\.ya\{0,1\}ml$' >"$all_files" || true
if [ "$#" -gt 0 ]; then
  for file in "$@"; do printf '%s\n' "$file" >>"$targets"; done
else
  cp "$all_files" "$targets"
fi

# Include explicitly named files while retaining a complete id reference index.
cat "$targets" >>"$all_files"
sort -u "$all_files" -o "$all_files"

if [ ! -s "$all_files" ]; then
  echo "no intent state — nothing to validate"
  exit 0
fi

parse_decisions() {
  file=$1
  awk -v file="$file" '
    function val(line) {
      sub(/^[^:]*: */, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
        sub(/^./, "", line); sub(/.$/, "", line)
      }
      gsub(/\|/, "%7C", line)
      return line
    }
    function emit() {
      if (id == "") return
      print "R|" file "|" id "|" decision "|" kind "|" authority "|" status "|" source "|" scope "|" introduced "|" observed "|" supersedes "|" superseded_by "|" status_source "|" anchors
    }
    /^  - id:/ {
      emit(); delete seen
      id=val($0); decision=kind=authority=status=source=scope=introduced=observed=supersedes=superseded_by=status_source=anchors=""
      next
    }
    id != "" && /^    [a-z_]+:/ {
      key=$0; sub(/^    /, "", key); sub(/:.*/, "", key)
      seen[key]++
      if (seen[key] > 1) print "E|" file "|" id "|duplicate field " key
      value=val($0)
      if (key == "decision") decision=value
      else if (key == "kind") kind=value
      else if (key == "authority") authority=value
      else if (key == "status") status=value
      else if (key == "source") source=value
      else if (key == "scope") scope=value
      else if (key == "introduced") introduced=value
      else if (key == "observed_ids") {
        observed=value
        if (value !~ /^\[.*\]$/) print "E|" file "|" id "|observed_ids must be an inline list"
      }
      else if (key == "supersedes") {
        supersedes=value
        if (value !~ /^\[.*\]$/) print "E|" file "|" id "|supersedes must be an inline list"
      }
      else if (key == "superseded_by") {
        superseded_by=value
        if (value !~ /^\[.*\]$/) print "E|" file "|" id "|superseded_by must be an inline list"
      }
      else if (key == "status_source") status_source=value
      else if (key == "at" || key == "interfaces" || key == "concerns") {
        if (key == "at") anchors=value
        if (value !~ /^\[.*\]$/) print "E|" file "|" id "|" key " must be an inline list when present"
      }
      else if (key != "author") print "E|" file "|" id "|unknown decision field " key
    }
    END { emit() }
  ' "$file"
}

parse_exceptions() {
  file=$1
  awk -v file="$file" '
    function val(line) {
      sub(/^[^:]*: */, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
        sub(/^./, "", line); sub(/.$/, "", line)
      }
      gsub(/\|/, "%7C", line)
      return line
    }
    function emit() {
      if (requirement == "") return
      if (section == "exceptions")
        print "X|" file "|" unit "|" requirement "|" substitute "|" source "|" exit_target "|" expires
    }
    /^[a-z_]+:/ {
      emit(); requirement=""
      key=$0; sub(/:.*/, "", key)
      top_seen[key]++
      if (top_seen[key] > 1) print "E|" file "|exceptions|duplicate top-level field " key
      value=val($0)
      if (key == "version") section=""
      else if (key == "unit") { unit=value; section="" }
      else if (key == "exceptions") {
        section="exceptions"; exceptions_seen=1
        if (value != "") print "E|" file "|exceptions|omit exceptions when empty; otherwise use a list"
      }
      else {
        section=""
        print "E|" file "|exceptions|unknown top-level field " key
      }
      next
    }
    /^  - requirement:/ {
      emit(); delete seen
      if (section != "exceptions")
        print "E|" file "|exceptions|requirement entry must be under exceptions"
      requirement=val($0); substitute=source=exit_target=expires=""
      next
    }
    requirement != "" && /^    [a-z_]+:/ {
      key=$0; sub(/^    /, "", key); sub(/:.*/, "", key)
      seen[key]++
      if (seen[key] > 1) print "E|" file "|" requirement "|duplicate field " key
      value=val($0)
      if (section == "exceptions" && key == "substitute") substitute=value
      else if (section == "exceptions" && key == "source") source=value
      else if (section == "exceptions" && key == "exit") exit_target=value
      else if (section == "exceptions" && key == "expires") expires=value
      else print "E|" file "|" requirement "|unknown " section " field " key
      next
    }
    /^[[:space:]]*-[[:space:]]/ {
      print "E|" file "|exceptions|only requirement entries are allowed"
      next
    }
    /^[[:space:]]*[a-z_]+:/ {
      key=$0; sub(/^[[:space:]]*/, "", key); sub(/:.*/, "", key)
      print "E|" file "|exceptions|field " key " is outside a requirement entry"
    }
    END {
      emit()
      print "H|" file "|" unit "|" exceptions_seen
    }
  ' "$file"
}

parse_routes() {
  file=$1
  awk -v file="$file" '
    function val(line) {
      sub(/^[^:]*: */, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      gsub(/\|/, "%7C", line)
      return line
    }
    function emit() {
      if (scope == "") return
      print "T|" file "|" scope "|" paths "|" interfaces "|" domain "|" architecture "|" contracts "|" owners
    }
    /^  - scope:/ {
      emit(); delete seen
      scope=val($0); paths=interfaces=domain=architecture=contracts=owners=""
      next
    }
    scope != "" && /^    [a-z_]+:/ {
      key=$0; sub(/^    /, "", key); sub(/:.*/, "", key)
      seen[key]++
      if (seen[key] > 1) print "E|" file "|" scope "|duplicate field " key
      value=val($0)
      if (value !~ /^\[.*\]$/) print "E|" file "|" scope "|" key " must be an inline list"
      if (key == "paths") paths=value
      else if (key == "interfaces") interfaces=value
      else if (key == "domain") domain=value
      else if (key == "architecture") architecture=value
      else if (key == "contracts") contracts=value
      else if (key == "owners") owners=value
      else print "E|" file "|" scope "|unknown route field " key
    }
    END { emit() }
  ' "$file"
}

parse_contracts() {
  file=$1
  awk -v file="$file" '
    function val(line) {
      sub(/^[^:]*: */, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
        sub(/^./, "", line); sub(/.$/, "", line)
      }
      gsub(/\|/, "%7C", line)
      return line
    }
    function emit() {
      if (id == "") return
      print "C|" file "|" id "|" assertion "|" authority "|" scope "|" surfaces "|" material "|" verifies
    }
    /^  - id:/ {
      emit(); delete seen
      id=val($0); assertion=authority=scope=surfaces=material=verifies=""
      next
    }
    id != "" && /^    [a-z_]+:/ {
      key=$0; sub(/^    /, "", key); sub(/:.*/, "", key)
      seen[key]++
      if (seen[key] > 1) print "E|" file "|" id "|duplicate field " key
      value=val($0)
      if (key == "assertion") assertion=value
      else if (key == "authority") authority=value
      else if (key == "scope") scope=value
      else if (key == "surfaces" || key == "material" || key == "verifies" || key == "tags") {
        if (value !~ /^\[.*\]$/) print "E|" file "|" id "|" key " must be an inline list"
        if (key == "surfaces") surfaces=value
        else if (key == "material") material=value
        else if (key == "verifies") verifies=value
      }
      else print "E|" file "|" id "|unknown contract field " key
    }
    END { emit() }
  ' "$file"
}

while IFS= read -r file; do
  [ -n "$file" ] || continue
  if [ ! -f "$file" ]; then
    fail "$file does not exist"
    continue
  fi
  grep -q '^version: 1$' "$file" || fail "$file must declare version: 1"
  case "$file" in
    .intent/ROUTES.yml|*/.intent/ROUTES.yml)
      grep -q '^routes:$' "$file" || fail "$file must contain a routes list"
      grep -q '^  - scope:' "$file" || fail "$file contains no routes; remove it"
      parse_routes "$file" >>"$routes"
      ;;
    .intent/CONTRACTS.yml|*/.intent/CONTRACTS.yml)
      grep -q '^contracts:$' "$file" || fail "$file must contain a contracts list"
      grep -q '^  - id:' "$file" || fail "$file contains no contracts; remove it"
      parse_contracts "$file" >>"$contracts_state"
      ;;
    .intent/config.yml|*/.intent/config.yml)
      config_error="$tmp_root/config-error"
      if ! sh "$script_dir/resolve-config.sh" >/dev/null 2>"$config_error"; then
        fail "$file $(sed 's/^git-intent: //' "$config_error" | tr '\n' ' ')"
      fi
      ;;
    .intent/exceptions/*|*/.intent/exceptions/*)
      grep -q '^unit:' "$file" || fail "$file must declare unit"
      grep -q '^exceptions:$' "$file" || fail "$file must contain exceptions"
      parse_exceptions "$file" >>"$exceptions_state"
      ;;
    .intent/decisions/*|*/.intent/decisions/*|.intent/proposals/*|*/.intent/proposals/*|.intent/history/*|*/.intent/history/*)
      grep -q '^decisions:$' "$file" || fail "$file must contain a decisions list"
      case "$file" in
        .intent/decisions/*|*/.intent/decisions/*|.intent/proposals/*|*/.intent/proposals/*)
          entries=$(grep -c '^  - id:' "$file" || true)
          [ "$entries" -eq 1 ] || fail "$file contains $entries decisions; active and proposal files contain exactly one"
          ;;
      esac
      parse_decisions "$file" >>"$parsed"
      ;;
    *) fail "$file is not a v1 intent config, route, contract, decision, exception, proposal, or history file" ;;
  esac
done <"$all_files"

awk -F'|' '$1 == "E" { print $2 "|" $3 "|" $4 }' "$parsed" "$exceptions_state" "$routes" "$contracts_state" |
while IFS='|' read -r file id message; do
  fail "$file:$id $message"
done

awk -F'|' '$1 == "R" { print $3 }' "$parsed" >"$ids"
awk -F'|' '$1 == "R" && $7 == "active" { print $3 }' "$parsed" >"$active_ids"
awk -F'|' '$1 == "C" { print $3 }' "$contracts_state" >"$contract_ids"
sort "$ids" | uniq -d | while IFS= read -r id; do
  [ -n "$id" ] && fail "$id appears more than once across intent state"
done
sort "$contract_ids" | uniq -d | while IFS= read -r id; do
  [ -n "$id" ] && fail "$id appears more than once in .intent/CONTRACTS.yml"
done

normalise_refs() {
  printf '%s' "$1" | tr -d '[],' | tr ' ' '\n' | sed '/^$/d'
}

check_repo_locator() {
  locator=$1
  label=$2
  case "$locator" in
    repo:*)
      path=${locator#repo:}; path=${path%%#*}
      [ -f "$path" ] || fail "$label repository target '$path' does not exist"
      ;;
    task:*|url:http://*|url:https://*) ;;
    *) fail "$label must use repo:, task:, or url:" ;;
  esac
}

check_source() {
  authority=$1
  source=$2
  label=$3
  case "$authority" in
    user_explicit)
      case "$source" in user:task:*|user:url:http://*|user:url:https://*) ;; *) fail "$label user_explicit source '$source' must be inspectable user:task: or user:url:" ;; esac
      ;;
    accepted_design)
      case "$source" in
        design:repo:*)
          path=${source#design:repo:}; path=${path%%#*}
          [ -f "$path" ] || fail "$label design source '$path' does not exist"
          ;;
        design:task:*|design:url:http://*|design:url:https://*) ;;
        *) fail "$label accepted_design source must be inspectable design:repo:, design:task:, or design:url:" ;;
      esac
      ;;
    architecture)
      case "$source" in
        architecture:repo:*)
          path=${source#architecture:repo:}; path=${path%%#*}
          [ -f "$path" ] || fail "$label architecture source '$path' does not exist"
          ;;
        *) fail "$label architecture source must use architecture:repo:" ;;
      esac
      ;;
    implementation)
      case "$source" in
        commit:*)
          ref=${source#commit:}
          git rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 || fail "$label commit source '$ref' does not resolve"
          ;;
        task:*|url:http://*|url:https://*) ;;
        *) fail "$label implementation source must use commit:, task:, or url:" ;;
      esac
      ;;
  esac
}

check_integration_source() {
  integration_source_value=$1
  integration_source_label=$2
  case "$integration_source_value" in
    design:repo:*)
      path=${integration_source_value#design:repo:}; path=${path%%#*}
      [ -f "$path" ] || fail "$integration_source_label integration source '$path' does not exist"
      ;;
    architecture:repo:*)
      path=${integration_source_value#architecture:repo:}; path=${path%%#*}
      [ -f "$path" ] || fail "$integration_source_label integration source '$path' does not exist"
      ;;
    commit:*)
      ref=${integration_source_value#commit:}
      git rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 || fail "$integration_source_label integration commit '$ref' does not resolve"
      ;;
    user:task:*|user:url:http://*|user:url:https://*|design:task:*|design:url:http://*|design:url:https://*|task:*|url:http://*|url:https://*) ;;
    *) fail "$integration_source_label status_source is not an inspectable locator" ;;
  esac
}

check_contract_authority() {
  contract_authority=$1
  contract_label=$2
  case "$contract_authority" in
    architecture:repo:*)
      path=${contract_authority#architecture:repo:}; path=${path%%#*}
      [ -f "$path" ] || fail "$contract_label authority target '$path' does not exist"
      ;;
    design:repo:*)
      path=${contract_authority#design:repo:}; path=${path%%#*}
      [ -f "$path" ] || fail "$contract_label authority target '$path' does not exist"
      ;;
    user:task:*|user:url:http://*|user:url:https://*|design:task:*|design:url:http://*|design:url:https://*) ;;
    *) fail "$contract_label authority must use architecture:repo:, design:repo:, design:task:, design:url:, user:task:, or user:url:" ;;
  esac
}

awk -F'|' '$1 == "C" { print }' "$contracts_state" |
while IFS='|' read -r marker file contract_id assertion authority scope surfaces material verifies; do
  case "$contract_id" in
    ''|.*|*..*|*.) fail "$file invalid contract id '$contract_id'" ;;
  esac
  [ -n "$assertion" ] || fail "$file:$contract_id missing assertion"
  [ "${#assertion}" -le 180 ] || fail "$file:$contract_id assertion exceeds 180 characters"
  case "$scope" in
    ''|.*|*..*|*.) fail "$file:$contract_id invalid scope '$scope'" ;;
  esac
  check_contract_authority "$authority" "$file:$contract_id"
  surface_count=0
  for surface in $(normalise_refs "$surfaces"); do
    surface_count=$((surface_count + 1))
    case "$surface" in
      repo:*)
        path=${surface#repo:}; path=${path%%#*}
        [ -e "$path" ] || fail "$file:$contract_id surface '$path' does not exist"
        ;;
      *) fail "$file:$contract_id surface '$surface' must use repo:" ;;
    esac
  done
  [ "$surface_count" -ge 1 ] || fail "$file:$contract_id requires at least one surface"
  [ "$surface_count" -le 24 ] || fail "$file:$contract_id has $surface_count surfaces; maximum is 24"

  material_count=0
  for artifact in $(normalise_refs "$material"); do
    material_count=$((material_count + 1))
    case "$artifact" in
      schema:*|design:*|architecture:*|repo:*)
        path=${artifact#*:}; path=${path%%#*}
        [ -f "$path" ] || fail "$file:$contract_id material '$path' does not exist"
        ;;
      task:*|url:http://*|url:https://*) ;;
      *) fail "$file:$contract_id material '$artifact' must use schema:, design:, architecture:, repo:, task:, or url:" ;;
    esac
  done
  [ "$material_count" -le 8 ] || fail "$file:$contract_id has $material_count material entries; maximum is 8"

  verify_count=0
  for verifier in $(normalise_refs "$verifies"); do
    verify_count=$((verify_count + 1))
    case "$verifier" in
      schema:*|test:*|command:*|contract:*)
        path=${verifier#*:}; path=${path%%#*}; path=${path%%::*}
        [ -f "$path" ] || fail "$file:$contract_id verifier target '$path' does not exist"
        case "$verifier" in command:*) [ -x "$path" ] || fail "$file:$contract_id command verifier '$path' is not executable" ;; esac
        ;;
      *) fail "$file:$contract_id verifier '$verifier' must use command:, schema:, test:, or contract:" ;;
    esac
    if [ "$audit" -eq 1 ]; then
      case "$verifier" in
        command:*|schema:*|test:*)
          printf 'AUDIT-VERIFY: %s — %s\n' "$contract_id" "$verifier"
          printf '%s\n' "$verifier" >>"$audit_verifiers"
          ;;
      esac
    fi
  done
  [ "$verify_count" -gt 0 ] || fail "$file:$contract_id requires at least one verifier"
  [ "$verify_count" -le 8 ] || fail "$file:$contract_id has $verify_count verifiers; maximum is 8"
done

awk -F'|' '$1 == "R" { print }' "$parsed" |
while IFS='|' read -r marker file id decision kind authority status source scope introduced observed supersedes superseded_by status_source anchors; do
  [ -n "$id" ] || fail "$file has an entry without id"
  [ -n "$decision" ] || fail "$file:$id missing decision"
  [ "${#decision}" -le 140 ] || fail "$file:$id decision exceeds 140 characters"
  [ -n "$kind" ] || fail "$file:$id missing kind"
  [ -n "$source" ] || fail "$file:$id missing source"
  [ -n "$scope" ] || fail "$file:$id missing scope"

  case "$kind" in
    domain_direction|architectural_constraint|implementation_choice) ;;
    *) fail "$file:$id invalid kind '$kind'" ;;
  esac
  case "$authority" in
    user_explicit|accepted_design|architecture|implementation) ;;
    *) fail "$file:$id invalid authority '$authority'" ;;
  esac
  case "$status" in
    active|superseded|obsolete|proposed) ;;
    *) fail "$file:$id invalid status '$status'" ;;
  esac

  case "$file" in
    .intent/decisions/*|*/.intent/decisions/*)
      [ "$status" = active ] || fail "$file:$id decision store requires status active"
      [ "$authority" != implementation ] || fail "$file:$id implementation authority is advisory and cannot be active"
      base=$(basename "$file"); base=${base%.*}
      [ "$base" = "$id" ] || fail "$file active decision filename must be $id.yml"
      scope_dir=$(basename "$(dirname "$file")")
      scope_root=${scope%%.*}
      [ "$scope_dir" = "$scope_root" ] || fail "$file:$id decision directory must be $scope_root for scope $scope"
      ;;
    .intent/proposals/*|*/.intent/proposals/*)
      [ "$status" = proposed ] || fail "$file:$id proposal store requires status proposed"
      base=$(basename "$file"); base=${base%.*}
      [ "$base" = "$id" ] || fail "$file proposal filename must be $id.yml"
      ;;
    .intent/history/*|*/.intent/history/*)
      case "$status" in superseded|obsolete) ;; *) fail "$file:$id history requires superseded or obsolete" ;; esac
      [ "$status" != superseded ] || [ -n "$superseded_by" ] || fail "$file:$id superseded history entry needs superseded_by"
      [ -n "$status_source" ] || fail "$file:$id history entry needs status_source"
      [ -z "$status_source" ] || check_integration_source "$status_source" "$file:$id"
      base=$(basename "$file"); base=${base%.*}
      scope_root=${scope%%.*}
      [ "$base" = "$scope_root" ] || fail "$file:$id history file must be $scope_root.yml for scope $scope"
      ;;
  esac

  check_source "$authority" "$source" "$file:$id"

  if [ -z "$introduced" ] || ! git rev-parse -q --verify "$introduced^{commit}" >/dev/null 2>&1; then
    fail "$file:$id introduced '$introduced' does not resolve"
  else
    case "$id" in *-*) prefix=${id%-*} ;; *) prefix=$id ;; esac
    case "$introduced" in "$prefix"*) ;; *) fail "$file:$id id is not derived from introduced stamp" ;; esac
  fi

  if [ "$audit" -eq 1 ] && [ "$status" = active ]; then
    for anchor in $(normalise_refs "$anchors"); do
      [ -e "$anchor" ] || audit_finding "$file:$id anchor '$anchor' does not exist"
    done
  fi

  for ref in $(normalise_refs "$observed"); do
    grep -qx "$ref" "$ids" || fail "$file:$id observed_ids references missing '$ref'"
  done
  for ref in $(normalise_refs "$supersedes"); do
    if grep -qx "$ref" "$ids"; then
      printf '%s|%s\n' "$id" "$ref" >>"$edges"
    else
      fail "$file:$id supersedes missing '$ref'"
    fi
  done
done

if [ -s "$edges" ]; then
  if ! awk -F'|' '
    function visit(n, i, v) {
      if (visiting[n]) return 1
      if (done[n]) return 0
      visiting[n]=1
      for (i=1; i<=count[n]; i++) { v=edge[n,i]; if (visit(v)) return 1 }
      visiting[n]=0; done[n]=1
      return 0
    }
    { edge[$1,++count[$1]]=$2; nodes[$1]=nodes[$2]=1 }
    END { for (n in nodes) if (visit(n)) exit 1 }
  ' "$edges"; then
    fail "supersedes graph contains a cycle"
  fi
fi

awk -F'|' '$1 == "H" { print }' "$exceptions_state" |
while IFS='|' read -r marker file unit exceptions_seen; do
  [ -n "$unit" ] || fail "$file missing unit"
  base=$(basename "$file"); base=${base%.*}
  [ "$base" = "$unit" ] || fail "$file exception filename must be $unit.yml"
  exception_count=$(awk -F'|' -v f="$file" '$1 == "X" && $2 == f { n++ } END { print n+0 }' "$exceptions_state")
  [ "$exception_count" -le 3 ] || fail "$file contains $exception_count exceptions; maximum is 3"
  [ "$exceptions_seen" != 1 ] || [ "$exception_count" -gt 0 ] || fail "$file must omit an empty exceptions section"
  [ "$exception_count" -gt 0 ] || fail "$file is empty; remove the exception file"
done

awk -F'|' '$1 == "T" { print $3 }' "$routes" | sort | uniq -d |
while IFS= read -r duplicate_scope; do
  [ -z "$duplicate_scope" ] || fail ".intent/ROUTES.yml duplicate scope '$duplicate_scope'"
done

awk -F'|' '$1 == "T" { print }' "$routes" |
while IFS='|' read -r marker file route_scope route_paths route_interfaces domain architecture contracts owners; do
  case "$route_scope" in
    ''|.*|*..*|*.) fail "$file invalid route scope '$route_scope'" ;;
  esac

  path_count=0
  for route_path in $(normalise_refs "$route_paths"); do
    path_count=$((path_count + 1))
    # Planned paths may be routed before they exist; existence is enforced at landing.
    if [ ! -e "$route_path" ]; then
      if [ "$landing" -eq 1 ]; then
        fail "$file:$route_scope route path '$route_path' does not exist"
      elif [ "$audit" -eq 1 ]; then
        audit_finding "$file:$route_scope route path '$route_path' does not exist"
      else
        echo "~ $file:$route_scope route path '$route_path' does not exist yet (planned path; must exist at landing)"
      fi
    fi
  done
  [ "$path_count" -le 24 ] || fail "$file:$route_scope has $path_count paths; maximum is 24"

  interface_count=0
  for route_interface in $(normalise_refs "$route_interfaces"); do
    interface_count=$((interface_count + 1))
  done
  [ "$interface_count" -le 16 ] || fail "$file:$route_scope has $interface_count interfaces; maximum is 16"
  [ $((path_count + interface_count)) -gt 0 ] || fail "$file:$route_scope requires at least one path or interface matcher"

  pointer_count=0
  for locator in $(normalise_refs "$domain"); do
    pointer_count=$((pointer_count + 1))
    case "$locator" in
      design:repo:*) path=${locator#design:repo:}; path=${path%%#*}; [ -f "$path" ] || fail "$file:$route_scope domain target '$path' does not exist" ;;
      design:task:*|design:url:http://*|design:url:https://*|user:task:*|user:url:http://*|user:url:https://*) ;;
      *) fail "$file:$route_scope domain locator '$locator' is invalid" ;;
    esac
  done
  for locator in $(normalise_refs "$architecture"); do
    pointer_count=$((pointer_count + 1))
    case "$locator" in
      architecture:repo:*) path=${locator#architecture:repo:}; path=${path%%#*}; [ -f "$path" ] || fail "$file:$route_scope architecture target '$path' does not exist" ;;
      *) fail "$file:$route_scope architecture locator '$locator' is invalid" ;;
    esac
  done
  for locator in $(normalise_refs "$contracts"); do
    pointer_count=$((pointer_count + 1))
    case "$locator" in
      contract:*)
        contract_id=${locator#contract:}
        grep -qx "$contract_id" "$contract_ids" || fail "$file:$route_scope references missing contract '$contract_id'"
        ;;
      command:*|schema:*|test:*)
        path=${locator#*:}; path=${path%%#*}; path=${path%%::*}
        [ -f "$path" ] || fail "$file:$route_scope contract target '$path' does not exist"
        ;;
      *) fail "$file:$route_scope contract locator '$locator' is invalid" ;;
    esac
  done
  for locator in $(normalise_refs "$owners"); do
    pointer_count=$((pointer_count + 1))
    case "$locator" in
      codeowners:*) path=${locator#codeowners:}; path=${path%%#*}; [ -f "$path" ] || fail "$file:$route_scope owner target '$path' does not exist" ;;
      task:*|url:http://*|url:https://*) ;;
      *) fail "$file:$route_scope owner locator '$locator' is invalid" ;;
    esac
  done
  [ "$pointer_count" -gt 0 ] || fail "$file:$route_scope route has no pointers"
  [ "$pointer_count" -le 12 ] || fail "$file:$route_scope has $pointer_count pointers; maximum is 12"
done

awk -F'|' '$1 == "X" { print }' "$exceptions_state" |
while IFS='|' read -r marker file unit requirement substitute exception_source exit_target expires; do
  [ -n "$requirement" ] || fail "$file has an exception without requirement"
  check_repo_locator "$requirement" "$file:$requirement"
  [ -n "$substitute" ] || fail "$file:$requirement exception requires substitute"
  [ "${#substitute}" -le 100 ] || fail "$file:$requirement substitute exceeds 100 characters"
  case "$exception_source" in
    design:repo:*)
      path=${exception_source#design:repo:}; path=${path%%#*}
      [ -f "$path" ] || fail "$file:$requirement exception source '$path' does not exist"
      ;;
    user:task:*|user:url:http://*|user:url:https://*|design:task:*|design:url:http://*|design:url:https://*) ;;
    *) fail "$file:$requirement exception requires an inspectable accepted source" ;;
  esac
  check_repo_locator "$exit_target" "$file:$requirement exit"
  if [ -n "$expires" ]; then
    case "$expires" in ????-??-??) ;; *) fail "$file:$requirement expires must be YYYY-MM-DD" ;; esac
    if [ "$landing" -eq 1 ] && [ "$expires" \< "$(date -u +%Y-%m-%d)" ]; then
      fail "$file:$requirement exception expired on $expires"
    elif [ "$audit" -eq 1 ] && [ "$expires" \< "$(date -u +%Y-%m-%d)" ]; then
      audit_finding "$file:$requirement exception expired on $expires"
    fi
  fi
done

if [ "$#" -eq 0 ]; then
  proposals=$(git ls-files '.intent/proposals/' 2>/dev/null | grep -c '\.ya\{0,1\}ml$' || true)
  [ "$proposals" -eq 0 ] || echo "~ $proposals concurrent proposal file(s) awaiting /intent-land"
fi

if [ -s "$violations" ]; then
  count=$(wc -l <"$violations" | tr -d ' ')
  echo "$count intent validation failure(s)"
  exit 1
fi

records=$(awk -F'|' '$1 == "R" { n++ } END { print n+0 }' "$parsed")
route_count=$(awk -F'|' '$1 == "T" { n++ } END { print n+0 }' "$routes")
contract_count=$(awk -F'|' '$1 == "C" { n++ } END { print n+0 }' "$contracts_state")
exceptions=$(awk -F'|' '$1 == "X" { n++ } END { print n+0 }' "$exceptions_state")
echo "intent state valid · $route_count route(s) · $contract_count contract(s) · $records decision record(s) · $exceptions exception(s)"
if [ "$audit" -eq 1 ]; then
  finding_count=$(wc -l <"$audit_findings" | tr -d ' ')
  verifier_count=$(sort -u "$audit_verifiers" | wc -l | tr -d ' ')
  echo "audit: $finding_count finding(s) · $verifier_count verifier(s) to run"
fi
exit 0
