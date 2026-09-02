#!/bin/sh
# Deterministic brief mechanics: reach derivation, digest freshness, verifier
# selection, and trailer honesty. Reach measures semantic governance only;
# coordination is a separate runtime choice.

set -u

usage() {
  cat >&2 <<'EOF'
usage:
  brief-support.sh digest <scope> [<scope>...]
      Emit the digest: a checksum of every matching route, contract, and
      active decision. Operational configuration is deliberately excluded.
      Also writes a content-addressed snapshot under visible `intent-work/` so a
      later STALE can be explained row by row.
  brief-support.sh map
      Emit the derived map: one BOUNDARY row per top-level seam and declared
      package root. Identifiers derive only from names present in the tree
      (lowercase-slugged) — no clustering, no heuristics — so the map of any
      commit's tree is reconstructible. Canonical test directories attach to
      the boundary of the code they exercise and never form their own. The
      map organizes and informs; it carries zero authority and never enters
      the digest. Never committed; a richer indexer may enrich the advisory
      pointers but never alter identifiers or boundary membership. Dotfiles
      inherit their parent boundary; root dotfiles belong to area.root.
  brief-support.sh rows <scope> [<scope>...]
      Compile the governing rows for the given scopes — the same set the
      digest hashes — as labeled brief rows: DOMAIN selects an acceptable
      outcome, CONSTRAINT excludes incompatible shapes, CONTRACT names
      verification that must pass before landing, OWNER locates missing
      authority, DECISION changes current direction, LEASE changes
      scheduling. Ends with ROWS: <n>; nine or more rows means narrow the
      unit or repair an over-broad route, never take a prefix.
  brief-support.sh observe [--explain] <expected-digest> <scope> [<scope>...]
      Recompute the digest and report OBSERVED or STALE (exit 1 on STALE) —
      the freshness check. With --explain, a STALE result also lists which
      governing rows were added, removed, or changed relative to the
      snapshot — rows this unit's own landings changed may be adopted by
      refreshing the digest; any foreign row forces recompilation.
  brief-support.sh message <subject> [--unit <id> ...] [--scope <scope> ...]
                   [--board <board-id>]
      Emit a complete landed-commit message with a tool-owned trailer block:
      one Intent-Unit trailer per --unit, one Intent-Scope trailer per
      --scope, and for --board the Intent-Board and Intent-Board-Digest trailers
      plus the unit table derived from the ephemeral workboard. Use it wherever the unit
      lands on the first-parent line — git merge --no-ff -m
      "$(brief-support.sh message ...)" locally, as a direct commit for a
      single-commit REACH: local unit, or as the squash-commit message when
      the repository squash-merges. Never format trailers by hand; separate
      -m arguments insert blank lines that break trailer parsing.
  brief-support.sh trailer <commit>
      Verify the commit's Intent-Scope trailer(s) against its first-parent
      diff. Verification is containment: every changed path must fall under a
      claimed governed scope (routes first) or a claimed derived boundary of
      that commit's tree. A commit may claim several identifiers (one trailer
      per scope).
  brief-support.sh probe [<base-ref>]
  brief-support.sh probe --paths <path> [<path>...]
  brief-support.sh probe --root
      Classify each contract the diff reaches for the verifier short-circuit.
      ELIGIBLE contracts list the verifiers to run: all green means the change
      did not cross the contract's meaning, by the contract's own operational
      definition, and lands light. A contract is INELIGIBLE when the diff
      touches its verifier files (you can't grade your own exam — the
      verification-strength gate applies) or .intent/CONTRACTS.yml itself
      (structural). The probe classifies; the agent runs the verifiers.
  brief-support.sh verifiers [<base-ref>]
  brief-support.sh verifiers --paths <path> [<path>...]
  brief-support.sh verifiers --root
      Emit each executable verifier locator required by the affected
      contracts as `VERIFY: <contract> <locator>`, de-duplicated. Atomic
      landing executes these locators against the prospective tree.
  brief-support.sh reach [<base-ref>]
  brief-support.sh reach --paths <path> [<path>...]
  brief-support.sh reach --root
      Compute reach from the two layers of the address space: the governance
      intersection (declared routes, contract surfaces, defining material,
      verifier files, consumer edges from route references and workboard
      relies_on) is what can gate; the derived map supplies the organizing
      topology facts (boundaries touched, spread) and never gates. Emits the
      facts plus a binding verdict:
        REACH: local    — no declared reliance intersected; proceed directly
        REACH: bounded  — contracts intersected, all probe-eligible; run their
                          verifiers, green lands light
        REACH: open     — a governed boundary is open because defining
                          material or a verifier changed
        REACH: gated    — .intent/CONTRACTS.yml changed breakingly; structural
                          authority applies
      A purely additive contract-record diff is an EXTENSION: fact instead of
      gated, and a rename-following record diff is a MOVE: fact. Extension
      authority follows configured escalation; a move preserves meaning. A mixed record diff takes its
      strictest class. Derived boundaries and spread are reported as topology
      facts but never increase semantic reach. Every goal is direct by
      default; intent-coordinate activates separately only for a useful live
      coordination frontier. Output binds or is omitted. Depth is never
      computed; containment is.
EOF
  exit 2
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runtime_script="$script_dir/../../intent-coordinate/scripts/runtime-support.sh"

[ "$#" -ge 1 ] || usage
cmd=$1
shift

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git-intent: not inside a Git repository" >&2
  exit 2
}
cd "$root" || exit 2

routes_file=.intent/ROUTES.yml
contracts_file=.intent/CONTRACTS.yml

# Emit "scope<TAB>path" for every route path matcher.
route_paths() {
  [ -f "$routes_file" ] || return 0
  awk '
    /^  - scope:/ { scope=$0; sub(/^[^:]*: */, "", scope); sub(/[[:space:]]+#.*$/, "", scope); next }
    scope != "" && /^    paths:/ {
      line=$0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
      n=split(line, a, /[[:space:]]+/)
      for (i=1; i<=n; i++) if (a[i] != "") print scope "\t" a[i]
    }
  ' "$routes_file"
}

# Emit "id<TAB>path" for every contract surface (repo: prefix stripped).
contract_surface_paths() {
  [ -f "$contracts_file" ] || return 0
  awk '
    /^  - id:/ { id=$0; sub(/^[^:]*: */, "", id); sub(/[[:space:]]+#.*$/, "", id); next }
    id != "" && /^    surfaces:/ {
      line=$0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
      n=split(line, a, /[[:space:]]+/)
      for (i=1; i<=n; i++) {
        if (a[i] == "") continue
        p = a[i]; sub(/^repo:/, "", p); sub(/#.*$/, "", p)
        print id "\t" p
      }
    }
  ' "$contracts_file"
}

# Emit "id<TAB>file" for every file-backed defining-material entry. Touching
# defining material opens the boundary: it redefines the assertion rather than
# implementing inside it.
contract_material_paths() {
  [ -f "$contracts_file" ] || return 0
  awk '
    /^  - id:/ { id=$0; sub(/^[^:]*: */, "", id); sub(/[[:space:]]+#.*$/, "", id); next }
    id != "" && /^    material:/ {
      line=$0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
      n=split(line, a, /[[:space:]]+/)
      for (i=1; i<=n; i++) {
        if (a[i] == "") continue
        if (index(a[i], "task:") == 1 || index(a[i], "url:") == 1) continue
        p = a[i]; sub(/^[a-z]+:/, "", p); sub(/#.*$/, "", p)
        print id "\t" p
      }
    }
  ' "$contracts_file"
}

# Emit "id<TAB>locator<TAB>file" for every contract verifier. The file column
# is the resolvable path behind the locator ("" for contract: references,
# whose backing file is CONTRACTS.yml itself and already structural).
contract_verifier_rows() {
  [ -f "$contracts_file" ] || return 0
  awk '
    /^  - id:/ { id=$0; sub(/^[^:]*: */, "", id); sub(/[[:space:]]+#.*$/, "", id); next }
    id != "" && /^    verifies:/ {
      line=$0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
      n=split(line, a, /[[:space:]]+/)
      for (i=1; i<=n; i++) {
        if (a[i] == "") continue
        f = a[i]
        if (index(f, "contract:") == 1) { print id "\t" a[i] "\t"; continue }
        sub(/^[a-z]+:/, "", f); sub(/#.*$/, "", f); sub(/::.*$/, "", f)
        print id "\t" a[i] "\t" f
      }
    }
  ' "$contracts_file"
}

# Emit "scope<TAB>contract-id" for every route's contract: reference — the
# declared consumer edges from routing.
route_contract_refs() {
  [ -f "$routes_file" ] || return 0
  awk '
    /^  - scope:/ { scope=$0; sub(/^[^:]*: */, "", scope); sub(/[[:space:]]+#.*$/, "", scope); next }
    scope != "" && /^    contracts:/ {
      line=$0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
      n=split(line, a, /[[:space:]]+/)
      for (i=1; i<=n; i++) if (index(a[i], "contract:") == 1) print scope "\t" substr(a[i], 10)
    }
  ' "$routes_file"
}

# Emit "unit<TAB>contract-id" for every workboard relies_on edge — the
# declared consumer edges from live coordination.
workboard_relies_rows() {
  runtime=$(sh "$runtime_script" root 2>/dev/null) || return 0
  [ -d "$runtime/boards" ] || return 0
  for f in "$runtime"/boards/*.yml; do
    [ -f "$f" ] || continue
    awk '
      /^  - id:/ { u=$0; sub(/^[^:]*: */, "", u); sub(/[[:space:]]+#.*$/, "", u); next }
      u != "" && /^    relies_on:/ {
        line=$0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
        n=split(line, a, /[[:space:]]+/)
        for (i=1; i<=n; i++) if (a[i] != "") print u "\t" a[i]
      }
    ' "$f"
  done
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

# Resolve the input path set (diff by default, --paths for an intended touch
# set) into the file named by $1; remaining args follow reach/probe conventions.
collect_paths() {
  out=$1
  shift
  if [ "${1:-}" = "--paths" ]; then
    shift
    [ "$#" -ge 1 ] || usage
    for p do printf '%s\n' "$p"; done | sed '/^$/d' | sort -u >"$out"
  elif [ "${1:-}" = "--root" ]; then
    git ls-tree -r --name-only HEAD -- 2>/dev/null | sed '/^$/d' | sort -u >"$out"
  else
    changed_paths "${1:-}" >"$out"
  fi
}

# ---- The derived map --------------------------------------------------------
# Identifiers derive only from names present in the tree: top-level seams as
# area.<slug>, declared package roots as pkg.<slug>. Canonical test directories
# attach to the boundary of the code they exercise and never form their own.
# `.intent/` is outside the map. The map organizes and informs — zero
# authority, never committed, never in the digest.

slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g'; }

is_test_dir() {
  case "$1" in tests|test|spec|__tests__) return 0 ;; *) return 1 ;; esac
}

# Every derived identifier containing the given path, one per line. Hidden
# files inherit their containing boundary; top-level hidden files/directories
# belong to area.root. Only .intent/ is outside the address space.
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
        for m in package.json pyproject.toml Cargo.toml go.mod; do
          if [ -f "$dir/$m" ]; then printf 'pkg.%s\n' "$(slug "${dir##*/}")"; break; fi
        done
        case "$dir" in */*) dir=${dir%/*} ;; *) break ;; esac
      done
      ;;
    *) printf 'area.root\n' ;;
  esac
}

do_map() {
  git ls-files -- 2>/dev/null | awk -F/ '
    $1 == ".intent" { next }
    NF > 1 {
      d = $1
      if (substr(d, 1, 1) == ".") rootfiles = 1
      else dirs[d] = 1
      next
    }
    { rootfiles = 1 }
    END {
      n = 0; for (d in dirs) k[++n] = d
      for (i=1; i<n; i++) for (j=i+1; j<=n; j++) if (k[j] < k[i]) { t=k[i]; k[i]=k[j]; k[j]=t }
      for (i=1; i<=n; i++) print k[i]
      if (rootfiles) print "."
    }
  ' | while IFS= read -r d; do
    if [ "$d" = "." ]; then
      printf 'BOUNDARY: area.root .\n'
    elif is_test_dir "$d"; then
      printf 'ATTACH: %s — canonical test paths attach to the boundary they exercise, never their own\n' "$d"
    else
      printf 'BOUNDARY: area.%s %s\n' "$(slug "$d")" "$d"
    fi
  done
  git ls-files -- 2>/dev/null | awk -F/ '
    NF > 2 && ($NF == "package.json" || $NF == "pyproject.toml" || $NF == "Cargo.toml" || $NF == "go.mod") {
      dir = $0; sub(/\/[^\/]*$/, "", dir)
      if (substr(dir, 1, 1) == ".") next
      if (!(dir in seen)) { seen[dir] = 1; print dir }
    }
  ' | sort | while IFS= read -r dir; do
    printf 'BOUNDARY: pkg.%s %s\n' "$(slug "${dir##*/}")" "$dir"
  done
}

# Classify the contract-record diff mechanically: extension (purely additive),
# move (every removed line maps to an added line along the diff's own rename
# map), or breaking. A mixed diff takes its strictest class. With no diff to
# measure the caller treats the answer as possibly breaking; landing refines.
classify_record_diff() {
  base=${1:-}
  df=$(mktemp "${TMPDIR:-/tmp}/git-intent-class.XXXXXX") || { echo breaking; return; }
  rn=$(mktemp "${TMPDIR:-/tmp}/git-intent-class.XXXXXX") || { rm -f "$df"; echo breaking; return; }
  {
    [ -z "$base" ] || git diff "$base...HEAD" -- "$contracts_file" 2>/dev/null
    git diff HEAD -- "$contracts_file" 2>/dev/null
  } >"$df"
  {
    [ -z "$base" ] || git diff -M --name-status --diff-filter=R "$base...HEAD" -- 2>/dev/null
    git diff -M --name-status --diff-filter=R HEAD -- 2>/dev/null
  } | awk -F'\t' '$1 ~ /^R/ { print $2 "\t" $3 }' | sort -u >"$rn"
  awk -v renames="$rn" '
    function lrep(s, o, n,   out, ix) {
      out = ""
      while ((ix = index(s, o)) > 0) { out = out substr(s, 1, ix-1) n; s = substr(s, ix + length(o)) }
      return out s
    }
    BEGIN {
      nr = 0
      while ((getline line < renames) > 0) {
        ix = index(line, "\t")
        if (ix > 0) { nr++; oldp[nr] = substr(line, 1, ix-1); newp[nr] = substr(line, ix+1) }
      }
    }
    /^--- / || /^\+\+\+ / { next }
    /^-/ { rem[++nrem] = substr($0, 2); next }
    /^\+/ { add[++nadd] = substr($0, 2); next }
    END {
      if (nadd + nrem == 0) { print "none"; exit }
      if (nrem == 0) { print "extension"; exit }
      if (nr == 0) { print "breaking"; exit }
      for (k = 1; k <= nadd; k++) used[k] = 0
      for (i = 1; i <= nrem; i++) {
        line = rem[i]
        for (j = 1; j <= nr; j++) line = lrep(line, oldp[j], newp[j])
        found = 0
        for (k = 1; k <= nadd; k++) if (!used[k] && add[k] == line) { used[k] = 1; found = 1; break }
        if (!found) { print "breaking"; exit }
      }
      print "move"
    }
  ' "$df"
  rm -f "$df" "$rn"
}

do_probe() {
  pathset=$(mktemp "${TMPDIR:-/tmp}/git-intent-probe.XXXXXX") || exit 2
  trap 'rm -f "$pathset"' EXIT HUP INT TERM
  collect_paths "$pathset" "$@"
  {
    contract_surface_paths | awk -F'\t' '{ print "K\t" $1 "\t" $2 }'
    contract_material_paths | awk -F'\t' '{ print "D\t" $1 "\t" $2 }'
    contract_verifier_rows | awk -F'\t' '{ print "V\t" $1 "\t" $2 "\t" $3 }'
    awk '{ print "P\t" $0 }' "$pathset"
  } | awk -F'\t' '
    $1 == "K" { cs[++nc]=$2; cm[nc]=$3; next }
    $1 == "D" { ds[++nd]=$2; dm[nd]=$3; next }
    $1 == "V" { vs[++nv]=$2; vl[nv]=$3; vf[nv]=$4; next }
    $1 == "P" { pp[++np]=$2; next }
    function hit(p, m) { return p == m || index(p, m "/") == 1 }
    END {
      structural = 0
      for (i=1; i<=np; i++) {
        p = pp[i]
        if (p == ".intent/CONTRACTS.yml") structural = 1
        if (index(p, ".intent/") == 1) continue
        for (j=1; j<=nc; j++) if (hit(p, cm[j])) touched[cs[j]] = 1
        for (j=1; j<=nd; j++) if (hit(p, dm[j])) { touched[ds[j]] = 1; badm[ds[j]] = dm[j] }
        for (j=1; j<=nv; j++) if (vf[j] != "" && hit(p, vf[j])) { touched[vs[j]] = 1; badv[vs[j]] = vf[j] }
      }
      nt = 0; for (id in touched) tk[++nt] = id
      for (i=1; i<nt; i++) for (j=i+1; j<=nt; j++) if (tk[j] < tk[i]) { t=tk[i]; tk[i]=tk[j]; tk[j]=t }
      for (i=1; i<=nt; i++) {
        id = tk[i]
        vlist = ""
        for (j=1; j<=nv; j++) if (vs[j] == id) vlist = vlist (vlist == "" ? "" : " ") vl[j]
        if (structural) {
          print "PROBE: " id " INELIGIBLE (.intent/CONTRACTS.yml changed) — structural gate applies"
        } else if (id in badm) {
          print "PROBE: " id " INELIGIBLE (diff touches defining material " badm[id] ") — boundary open, structural gate applies"
        } else if (id in badv) {
          print "PROBE: " id " INELIGIBLE (diff touches verifier " badv[id] ") — verification-strength gate applies"
        } else {
          print "PROBE: " id " ELIGIBLE — " vlist
        }
      }
    }
  '
}

# Emit the verifier locators required by every contract affected by the path
# set. Unlike probe, this includes open contracts: a changed verifier cannot
# grade its own authority, but the prospective tree must still prove that its
# operational checks are green before landing.
do_verifiers() {
  pathset=$(mktemp "${TMPDIR:-/tmp}/git-intent-verifiers.XXXXXX") || exit 2
  trap 'rm -f "$pathset"' EXIT HUP INT TERM
  collect_paths "$pathset" "$@"
  {
    contract_surface_paths | awk -F'\t' '{ print "K\t" $1 "\t" $2 }'
    contract_material_paths | awk -F'\t' '{ print "D\t" $1 "\t" $2 }'
    contract_verifier_rows | awk -F'\t' '{ print "V\t" $1 "\t" $2 "\t" $3 }'
    awk '{ print "P\t" $0 }' "$pathset"
  } | awk -F'\t' '
    $1 == "K" { cs[++nc]=$2; cm[nc]=$3; next }
    $1 == "D" { ds[++nd]=$2; dm[nd]=$3; next }
    $1 == "V" { vs[++nv]=$2; vl[nv]=$3; vf[nv]=$4; next }
    $1 == "P" { pp[++np]=$2; next }
    function hit(p, m) { return p == m || index(p, m "/") == 1 }
    END {
      structural = 0
      for (i=1; i<=np; i++) {
        p = pp[i]
        if (p == ".intent/CONTRACTS.yml") structural = 1
        if (index(p, ".intent/") == 1) continue
        for (j=1; j<=nc; j++) if (hit(p, cm[j])) touched[cs[j]] = 1
        for (j=1; j<=nd; j++) if (hit(p, dm[j])) touched[ds[j]] = 1
        for (j=1; j<=nv; j++) if (vf[j] != "" && hit(p, vf[j])) touched[vs[j]] = 1
      }
      for (id in touched) wanted[id] = 1
      if (structural) for (j=1; j<=nv; j++) wanted[vs[j]] = 1
      changed = 1
      while (changed) {
        changed = 0
        for (j=1; j<=nv; j++) if (vs[j] in wanted && index(vl[j], "contract:") == 1) {
          ref = substr(vl[j], 10)
          if (!(ref in wanted)) { wanted[ref] = 1; changed = 1 }
        }
      }
      for (j=1; j<=nv; j++) if (vs[j] in wanted && index(vl[j], "contract:") != 1) {
        key = vs[j] SUBSEP vl[j]
        if (!(key in emitted)) {
          emitted[key] = 1
          print "VERIFY: " vs[j] " " vl[j]
        }
      }
    }
  ' | sort
}

do_reach() {
  pathset=$(mktemp "${TMPDIR:-/tmp}/git-intent-reach.XXXXXX") || exit 2
  trap 'rm -f "$pathset"' EXIT HUP INT TERM
  paths_mode=0
  root_mode=0
  base_ref=""
  if [ "${1:-}" = "--paths" ]; then
    paths_mode=1
  elif [ "${1:-}" = "--root" ]; then
    root_mode=1
  else
    base_ref="${1:-}"
  fi
  collect_paths "$pathset" "$@"
  # Record classifier: only a measured diff can prove a record change additive
  # or rename-following; the static half stays "possibly breaking".
  record_class=""
  if grep -qxF '.intent/CONTRACTS.yml' "$pathset" 2>/dev/null; then
    if [ "$root_mode" -eq 1 ]; then
      record_class=extension
    elif [ "$paths_mode" -eq 0 ]; then
      record_class=$(classify_record_diff "$base_ref")
      case "$record_class" in extension|move) ;; *) record_class="" ;; esac
    fi
  fi
  {
    route_paths | awk -F'\t' '{ print "M\t" $1 "\t" $2 }'
    contract_surface_paths | awk -F'\t' '{ print "K\t" $1 "\t" $2 }'
    contract_material_paths | awk -F'\t' '{ print "D\t" $1 "\t" $2 }'
    contract_verifier_rows | awk -F'\t' '{ print "V\t" $1 "\t" $2 "\t" $3 }'
    route_contract_refs | awk -F'\t' '{ print "RC\t" $1 "\t" $2 }'
    workboard_relies_rows | awk -F'\t' '{ print "PU\t" $1 "\t" $2 }'
    awk '{ print "P\t" $0 }' "$pathset"
  } | awk -F'\t' -v record_class="$record_class" '
    $1 == "M" { rs[++nr]=$2; rm[nr]=$3; next }
    $1 == "K" { cs[++nc]=$2; cm[nc]=$3; next }
    $1 == "D" { ds[++nd]=$2; dm[nd]=$3; next }
    $1 == "V" { vs[++nv]=$2; vl[nv]=$3; vf[nv]=$4; next }
    $1 == "RC" { rcs[++nrc]=$2; rcc[nrc]=$3; next }
    $1 == "PU" { pus[++npu]=$2; puc[npu]=$3; next }
    $1 == "P" { pp[++np]=$2; next }
    function hit(p, m) { return p == m || index(p, m "/") == 1 }
    function bslug(d,   s) { s = tolower(d); gsub(/[^a-z0-9_-]/, "-", s); return s }
    function testdir(d) { return d == "tests" || d == "test" || d == "spec" || d == "__tests__" }
    END {
      structural = 0; unrouted = 0; rootf = 0; ntd = 0
      for (i=1; i<=np; i++) {
        p = pp[i]
        if (p == ".intent/CONTRACTS.yml") structural = 1
        if (index(p, ".intent/") == 1) continue
        matched = 0
        for (j=1; j<=nr; j++) if (hit(p, rm[j])) { scopes[rs[j]] = 1; matched = 1 }
        for (j=1; j<=nc; j++) if (hit(p, cm[j])) touched[cs[j]] = 1
        for (j=1; j<=nd; j++) if (hit(p, dm[j])) { touched[ds[j]] = 1; badm[ds[j]] = dm[j] }
        for (j=1; j<=nv; j++) if (vf[j] != "" && hit(p, vf[j])) { touched[vs[j]] = 1; badv[vs[j]] = vf[j] }
        if (!matched) {
          unrouted++
          ix = index(p, "/")
          if (ix > 0) {
            d = substr(p, 1, ix - 1)
            if (substr(d, 1, 1) == ".") rootf = 1
            else if (testdir(d)) tdirs[d] = 1
            else udirs[d] = 1
          } else rootf = 1
        }
      }
      ns = 0; for (s in scopes) sk[++ns] = s
      nt = 0; for (c in touched) tk[++nt] = c
      # Derived boundaries: identifiers from names in the tree. Canonical test
      # directories attach to the boundary the change exercises — they form
      # their own boundary only when there is nothing to attach to.
      nb = 0
      for (d in udirs) bk[++nb] = "area." bslug(d)
      if (rootf) bk[++nb] = "area.root"
      if (nb == 0 && ns == 0) for (d in tdirs) bk[++nb] = "area." bslug(d)
      for (i=1; i<ns; i++) for (j=i+1; j<=ns; j++) if (sk[j] < sk[i]) { t=sk[i]; sk[i]=sk[j]; sk[j]=t }
      for (i=1; i<nt; i++) for (j=i+1; j<=nt; j++) if (tk[j] < tk[i]) { t=tk[i]; tk[i]=tk[j]; tk[j]=t }
      for (i=1; i<nb; i++) for (j=i+1; j<=nb; j++) if (bk[j] < bk[i]) { t=bk[i]; bk[i]=bk[j]; bk[j]=t }
      slist = ""; for (i=1; i<=ns; i++) slist = slist (i>1 ? " " : "") sk[i]
      klist = ""; for (i=1; i<=nt; i++) klist = klist (i>1 ? " " : "") tk[i]
      blist = ""; for (i=1; i<=nb; i++) blist = blist (i>1 ? " " : "") bk[i]
      spread = (nb >= 3 || (nb >= 2 && unrouted >= 5))
      # Output binds or is omitted: a fact line appears only when the fact is
      # present.
      if (ns) print "SCOPES: " ns " — " slist
      if (nb) print "BOUNDARIES: " nb " — " blist " (derived, zero authority)"
      if (nt) print "DECLARED CONTRACTS: " nt " — " klist
      if (unrouted) print "UNROUTED: " unrouted
      if (spread) print "SPREAD: " unrouted " unrouted path(s) across " nb " derived boundar" (nb == 1 ? "y" : "ies") " — topology fact only; semantic reach remains local without declared reliance"
      if (structural) print "STRUCTURAL: .intent/CONTRACTS.yml changed — contract records are never probeable"
      if (structural && record_class == "extension")
        print "EXTENSION: contract-record diff is purely additive — resolve establishment authority, re-verify consumers, require every new verifier green"
      if (structural && record_class == "move")
        print "MOVE: contract-record diff rewrites path anchors along the rename map — meaning preserved; require verifiers green at their new paths"
      nopen = 0
      for (i=1; i<=nt; i++) {
        id = tk[i]
        vlist = ""
        for (j=1; j<=nv; j++) if (vs[j] == id) vlist = vlist (vlist == "" ? "" : " ") vl[j]
        if (structural || (id in badm) || (id in badv)) {
          nopen++
          if (structural) reason = ".intent/CONTRACTS.yml changed"
          else if (id in badm) reason = "defining material " badm[id] " changed"
          else reason = "verifier " badv[id] " changed"
          consumers = ""
          for (j=1; j<=nrc; j++) if (rcc[j] == id) consumers = consumers " scope:" rcs[j]
          for (j=1; j<=npu; j++) if (puc[j] == id) consumers = consumers " unit:" pus[j]
          print "OPEN: " id " (" reason ")" (consumers != "" ? " — consumers:" consumers : " — no declared consumers")
        } else {
          print "PROBE: " id " ELIGIBLE — " vlist
        }
      }
      if (structural && record_class == "") reach = "gated"
      else if (structural) reach = "open"
      else if (nopen > 0) reach = "open"
      else if (nt > 0) reach = "bounded"
      else reach = "local"
      print "NEXT: intent-land — coordination activates separately only for a useful live frontier"
      print "REACH: " reach
    }
  '
}

# Serialize the governing content for the given scopes in deterministic order.
# Operational configuration is excluded: a different target branch or
# resolver does not change the meaning of a route, contract, or decision.
governing_content() {
  scopes_csv=$1
  printf 'git-intent digest v1\n'
  if [ -f "$routes_file" ]; then
    awk -v want="$scopes_csv" '
      BEGIN { n = split(want, w, ",") }
      function m(s, i) {
        for (i=1; i<=n; i++)
          if (s == w[i] || index(s, w[i] ".") == 1 || index(w[i], s ".") == 1) return 1
        return 0
      }
      /^  - scope:/ { s=$0; sub(/^[^:]*: */, "", s); sub(/[[:space:]]+#.*$/, "", s); on=m(s) }
      on { print }
    ' "$routes_file"
  fi
  refs=""
  if [ -f "$routes_file" ]; then
    refs=$(awk -v want="$scopes_csv" '
      BEGIN { n = split(want, w, ",") }
      function m(s, i) {
        for (i=1; i<=n; i++)
          if (s == w[i] || index(s, w[i] ".") == 1 || index(w[i], s ".") == 1) return 1
        return 0
      }
      /^  - scope:/ { s=$0; sub(/^[^:]*: */, "", s); sub(/[[:space:]]+#.*$/, "", s); on=m(s) }
      on && /^    contracts:/ {
        line=$0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
        k=split(line, a, /[[:space:]]+/)
        for (i=1; i<=k; i++) if (index(a[i], "contract:") == 1) print substr(a[i], 10)
      }
    ' "$routes_file" | sort -u | tr '\n' ',' | sed 's/,$//')
  fi
  if [ -f "$contracts_file" ]; then
    awk -v want="$scopes_csv" -v ids="$refs" '
      BEGIN { n = split(want, w, ","); ni = split(ids, idl, ",") }
      function m(s, i) {
        for (i=1; i<=n; i++)
          if (s == w[i] || index(s, w[i] ".") == 1 || index(w[i], s ".") == 1) return 1
        return 0
      }
      function ref(c, i) { for (i=1; i<=ni; i++) if (c == idl[i]) return 1; return 0 }
      function flush() { if (on) printf "%s", buf; buf = ""; on = 0 }
      /^  - id:/ {
        flush()
        cid=$0; sub(/^[^:]*: */, "", cid); sub(/[[:space:]]+#.*$/, "", cid)
        on = ref(cid); buf = $0 "\n"; inblock = 1; next
      }
      inblock {
        if (/^    scope:/) {
          s=$0; sub(/^[^:]*: */, "", s); sub(/[[:space:]]+#.*$/, "", s)
          if (m(s)) on = 1
        }
        buf = buf $0 "\n"
      }
      END { flush() }
    ' "$contracts_file"
  fi
  old_ifs=$IFS; IFS=','
  for scope in $scopes_csv; do
    IFS=$old_ifs
    scope_root=${scope%%.*}
    dir=".intent/decisions/$scope_root"
    [ -d "$dir" ] || continue
    for f in $(ls "$dir"/*.yml 2>/dev/null | sort); do
      dscope=$(sed -n 's/^    scope:[[:space:]]*//p' "$f" | head -1)
      case "$dscope" in
        "$scope"|"$scope".*) cat "$f" ;;
        *) case "$scope" in "$dscope".*) cat "$f" ;; esac ;;
      esac
    done
  done
  IFS=$old_ifs
}

compute_digest() {
  set -- $(governing_content "$1" | cksum)
  printf '%s-%s\n' "$1" "$2"
}

# Ephemeral, content-addressed snapshots of governing serializations; a local
# runtime substrate like leases and workboards, never committed.
observations_dir() {
  runtime=$(sh "$runtime_script" ensure 2>/dev/null) || return 1
  printf '%s/observations\n' "$runtime"
}

# Emit "row-identity<TAB>flattened-content" per governing row, sorted.
rows_flat() {
  awk '
    function flush() { if (key != "") print key "\t" buf }
    /^  - scope:/ || /^  - id:/ {
      flush()
      key = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", key)
      buf = ""
      next
    }
    key != "" { line = $0; gsub(/\t/, " ", line); buf = buf line "\\n" }
    END { flush() }
  ' "$1" | sort
}

do_digest() {
  [ "$#" -ge 1 ] || usage
  scopes_csv=$(printf '%s,' "$@" | sed 's/,$//')
  digest=$(compute_digest "$scopes_csv")
  if obs=$(observations_dir); then
    mkdir -p "$obs" 2>/dev/null &&
      governing_content "$scopes_csv" >"$obs/$digest" 2>/dev/null || true
  fi
  printf 'DIGEST: %s\n' "$digest"
}

# Compile the governing rows for the given scopes — the same serialization
# the digest hashes — as labeled brief rows, plus intersecting live leases.
do_rows() {
  [ "$#" -ge 1 ] || usage
  scopes_csv=$(printf '%s,' "$@" | sed 's/,$//')
  rows=$(
    governing_content "$scopes_csv" | awk '
      function emit_list(label, who, line,   n, a, i) {
        sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
        n = split(line, a, /[[:space:]]+/)
        for (i = 1; i <= n; i++) if (a[i] != "") print label " " who " — " a[i]
      }
      function list_flat(line,   n, a, i, out) {
        sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
        n = split(line, a, /[[:space:]]+/); out = ""
        for (i = 1; i <= n; i++) if (a[i] != "") out = out (out == "" ? "" : " ") a[i]
        return out
      }
      function val(line) { sub(/^[^:]*: */, "", line); sub(/[[:space:]]+#.*$/, "", line); return line }
      function flushc() {
        if (cid != "")
          print "CONTRACT " cid " — " cassert (cverify == "" ? "" : " (verify: " cverify ")")
        cid = ""
      }
      function flushd() {
        if (did != "") print "DECISION " did " (" dkind ") — " dtext
        did = ""
      }
      /^decisions:/ { flushc(); flushd(); mode = "D"; next }
      /^  - scope:/ && mode != "D" { flushc(); mode = "R"; rscope = val($0); next }
      /^  - id:/ {
        if (mode == "D") { flushd(); did = val($0); dkind = ""; dtext = "" }
        else { flushc(); mode = "C"; cid = val($0); cassert = ""; cverify = "" }
        next
      }
      mode == "R" && /^    domain:/       { emit_list("DOMAIN", rscope, $0); next }
      mode == "R" && /^    architecture:/ { emit_list("CONSTRAINT", rscope, $0); next }
      mode == "R" && /^    owners:/       { emit_list("OWNER", rscope, $0); next }
      mode == "R" && /^    contracts:/ {
        line = $0; sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
        n = split(line, a, /[[:space:]]+/)
        for (i = 1; i <= n; i++)
          if (a[i] != "" && index(a[i], "contract:") != 1)
            print "CONTRACT " rscope " — " a[i]
        next
      }
      mode == "C" && /^    assertion:/ { cassert = val($0); next }
      mode == "C" && /^    verifies:/  { cverify = list_flat($0); next }
      did != "" && /^    decision:/ { dtext = val($0); next }
      did != "" && /^    kind:/     { dkind = val($0); next }
      END { flushc(); flushd() }
    '
  )
  leases=""
  if runtime=$(sh "$runtime_script" root 2>/dev/null); then
    for f in "$runtime"/leases/*.yml; do
      [ -f "$f" ] || continue
      lunit=$(sed -n 's/^unit:[[:space:]]*//p' "$f" | head -1)
      lscope=$(sed -n 's/^scope:[[:space:]]*//p' "$f" | head -1)
      [ -n "$lscope" ] || continue
      old_ifs=$IFS; IFS=','
      for scope in $scopes_csv; do
        IFS=$old_ifs
        rel=0
        case "$lscope" in "$scope"|"$scope".*) rel=1 ;; esac
        case "$scope" in "$lscope".*) rel=1 ;; esac
        if [ "$rel" -eq 1 ]; then
          leases=$(printf '%s\nLEASE %s — %s' "$leases" "$lunit" "$lscope")
          break
        fi
      done
      IFS=$old_ifs
    done
  fi
  all=$(printf '%s\n%s\n' "$rows" "$leases" | sed '/^$/d')
  n=0
  if [ -n "$all" ]; then
    printf '%s\n' "$all"
    n=$(printf '%s\n' "$all" | wc -l | tr -d ' ')
  fi
  if [ "$n" -ge 9 ]; then
    printf 'ROWS: %s — exceeds the eight-row cap; narrow the unit or repair an over-broad route\n' "$n"
  else
    printf 'ROWS: %s\n' "$n"
  fi
}

do_observe() {
  explain=0
  if [ "${1:-}" = "--explain" ]; then
    explain=1
    shift
  fi
  [ "$#" -ge 2 ] || usage
  expected=$1
  shift
  scopes_csv=$(printf '%s,' "$@" | sed 's/,$//')
  actual=$(compute_digest "$scopes_csv")
  if [ "$actual" = "$expected" ]; then
    printf 'OBSERVED %s\n' "$actual"
    return 0
  fi
  printf 'STALE expected %s got %s — recompile the brief and re-verify\n' "$expected" "$actual"
  if [ "$explain" -eq 1 ]; then
    snap=""
    if obs=$(observations_dir); then snap="$obs/$expected"; fi
    if [ -n "$snap" ] && [ -f "$snap" ]; then
      new_content=$(mktemp "${TMPDIR:-/tmp}/git-intent-observe.XXXXXX") || exit 1
      old_rows=$(mktemp "${TMPDIR:-/tmp}/git-intent-observe.XXXXXX") || exit 1
      new_rows=$(mktemp "${TMPDIR:-/tmp}/git-intent-observe.XXXXXX") || exit 1
      trap 'rm -f "$new_content" "$old_rows" "$new_rows"' EXIT HUP INT TERM
      governing_content "$scopes_csv" >"$new_content"
      rows_flat "$snap" >"$old_rows"
      rows_flat "$new_content" >"$new_rows"
      awk -F'\t' '
        FILENAME == ARGV[1] { old[$1] = $2; next }
        { new[$1] = $2 }
        END {
          for (k in new) if (!(k in old)) print "EXPLAIN: added " k
          for (k in old) if (!(k in new)) print "EXPLAIN: removed " k
          for (k in new) if ((k in old) && old[k] != new[k]) print "EXPLAIN: changed " k
        }
      ' "$old_rows" "$new_rows" | sort
      echo "EXPLAIN: rows changed only by this unit's own landings may be adopted by re-running digest; any foreign row forces recompilation"
    else
      echo "EXPLAIN: no snapshot for $expected — recompile and re-read all governing rows"
    fi
  fi
  exit 1
}

do_message() {
  [ "$#" -ge 1 ] || usage
  subject=$1
  shift
  units=""
  scopes=""
  board=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --unit) [ "$#" -ge 2 ] || usage; units="$units $2"; shift 2 ;;
      --scope) [ "$#" -ge 2 ] || usage; scopes="$scopes $2"; shift 2 ;;
      --board) [ "$#" -ge 2 ] || usage; board=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$units" ] || [ -n "$board" ] || usage
  if [ -n "$units" ] && [ -z "$scopes" ]; then
    echo "git-intent: message with --unit requires at least one --scope" >&2
    exit 2
  fi
  board_file=""
  if [ -n "$board" ]; then
    runtime=$(sh "$runtime_script" root) || exit 2
    board_file="$runtime/boards/$board.yml"
    [ -f "$board_file" ] || {
      echo "git-intent: no workboard '$board' to stamp (expected $board_file)" >&2
      exit 2
    }
  fi
  printf '%s\n\n' "$subject"
  if [ -n "$board_file" ]; then
    awk '
      BEGIN { print "Units:" }
      function flush() { if (id != "") print "  " id (deps == "" ? "" : " <- " deps) }
      /^  - id:/ {
        flush()
        id = $0; sub(/^[^:]*: */, "", id); sub(/[[:space:]]+#.*$/, "", id); deps = ""
        next
      }
      id != "" && /^    dependencies:/ {
        deps = $0; sub(/^[^:]*: */, "", deps); gsub(/[][,]/, " ", deps)
        gsub(/[[:space:]]+/, " ", deps); sub(/^ /, "", deps); sub(/ $/, "", deps)
      }
      END { flush() }
    ' "$board_file"
    printf '\n'
  fi
  for u in $units; do printf 'Intent-Unit: %s\n' "$u"; done
  for s in $scopes; do printf 'Intent-Scope: %s\n' "$s"; done
  if [ -n "$board" ]; then
    printf 'Intent-Board: %s\n' "$board"
    set -- $(cksum <"$board_file")
    printf 'Intent-Board-Digest: %s-%s\n' "$1" "$2"
  fi
}

do_trailer() {
  [ "$#" -eq 1 ] || usage
  commit=$1
  claimed=$(git log -1 --format='%(trailers:key=Intent-Scope,valueonly,separator=%x0a)' "$commit" 2>/dev/null | sed '/^$/d')
  if [ -z "$claimed" ]; then
    printf 'TRAILER: missing Intent-Scope on %s\n' "$commit"
    exit 1
  fi
  claims=$(printf '%s\n' "$claimed" | tr '\n' ',' | sed 's/,$//')
  if git rev-parse -q --verify "$commit^" >/dev/null 2>&1; then
    diff_paths=$(git diff --name-only "$commit^" "$commit")
  else
    diff_paths=$(git diff-tree --no-commit-id --name-only -r --root "$commit")
  fi
  result=$(
    {
      route_paths | awk -F'\t' '{ print "M\t" $1 "\t" $2 }'
      printf '%s\n' "$diff_paths" | sed '/^$/d' | while IFS= read -r p; do
        ids=$(derived_ids_for_path "$p" | tr '\n' ',' | sed 's/,$//')
        printf 'P\t%s\t%s\n' "$p" "$ids"
      done
    } | awk -F'\t' -v claims="$claims" '
      BEGIN { ncl = split(claims, cl, ",") }
      $1 == "M" { rs[++nr]=$2; rm[nr]=$3; next }
      $1 == "P" { pp[++np]=$2; pd[np]=$3; next }
      function related(a, b) { return a == b || index(a, b ".") == 1 || index(b, a ".") == 1 }
      function claimed_scope(s, i) { for (i=1; i<=ncl; i++) if (related(s, cl[i])) return 1; return 0 }
      function testpath(p,   d, ix) {
        ix = index(p, "/"); if (ix == 0) return 0
        d = substr(p, 1, ix - 1)
        return (d == "tests" || d == "test" || d == "spec" || d == "__tests__")
      }
      END {
        # Containment, not row equality: a changed path must fall under a
        # claimed governed scope (routes first) or a claimed derived boundary
        # of the commit tree. Test paths attach to the boundary they
        # exercise; .intent/ is outside the address space.
        bad = ""
        for (i=1; i<=np; i++) {
          p = pp[i]
          if (index(p, ".intent/") == 1) continue
          routed = 0; covered = 0; want = ""
          for (j=1; j<=nr; j++)
            if (p == rm[j] || index(p, rm[j] "/") == 1) {
              routed = 1; want = rs[j]
              if (claimed_scope(rs[j])) covered = 1
            }
          if (routed) {
            if (!covered) bad = bad " " p "->" want
            continue
          }
          if (testpath(p)) continue
          nd = split(pd[i], dl, ",")
          for (k=1; k<=nd; k++) if (dl[k] != "" && claimed_scope(dl[k])) { covered = 1; break }
          if (!covered) bad = bad " " p "->" (nd > 0 && dl[1] != "" ? dl[1] : "unaddressed")
        }
        disp = claims; gsub(/,/, " ", disp)
        if (bad != "") { print "FAIL claim " disp " but diff routes to" bad; exit 1 }
        print "OK " disp
      }
    '
  ) || { printf 'TRAILER: %s\n' "$result"; exit 1; }
  printf 'TRAILER: %s\n' "$result"
}

case "$cmd" in
  probe) do_probe "$@" ;;
  verifiers) do_verifiers "$@" ;;
  reach) do_reach "$@" ;;
  map) do_map "$@" ;;
  digest) do_digest "$@" ;;
  rows) do_rows "$@" ;;
  observe) do_observe "$@" ;;
  message) do_message "$@" ;;
  trailer) do_trailer "$@" ;;
  *) usage ;;
esac
