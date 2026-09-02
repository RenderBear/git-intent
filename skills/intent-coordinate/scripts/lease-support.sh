#!/bin/sh
# Deterministic lease mechanics: ephemeral dispatch leases in the shared
# ignored runtime, each carrying its unit's claim. Owns the YAML shape, the intersection
# check, and dissolution. Clocks schedule, causality decides: expiry carries
# no authority — it only schedules the conclusive liveness check, because a
# crashed worker emits no further commits and causal order alone cannot
# observe it. Reaping ends a reservation, never work: the branch and worktree
# remain, and a worker that wakes must re-lease, which forces the freshness
# check. Leases are a local substrate shared across linked worktrees only;
# they never enter a commit.

set -u

usage() {
  cat >&2 <<'EOF'
usage:
  lease-support.sh create <unit> [--scope <derived.scope>] [--paths <p>...]
                   [--interfaces <name>...] [--governance <ref>...]
                   [--domains <id>...] [--digest <hash>]
                   [--branch <b>] [--worktree <w>]
                   [--task <t>] [--owner <o>] [--integration-target <b>]
                   [--duration 2h]
      Mint the unit's lease — every dispatch, unconditionally; the recorded
      claim is what keeps concurrent plans visible to each other. Reports any
      intersecting live unit. Records the branch tip and the integration
      ground at grant. Never overwrites an existing lease.
  lease-support.sh renew <unit> [--duration 2h]
      Extend expiry from now and re-record the branch tip; preserves created.
  lease-support.sh release <unit>
      Delete exactly that unit's lease file.
  lease-support.sh list [--scope <derived.scope>] [--domain <id>]
      One line per lease with its expiry state.
  lease-support.sh fresh <unit>
      Coordination-side freshness: STALE when a landing on the resolved
      integration branch since the recorded ground intersects the claimed
      paths, interfaces, or claimed governance — re-lease against the new
      ground or release.
      FRESH otherwise. Exit 1 on STALE.
  lease-support.sh reap [--apply]
      The conclusive liveness check, scheduled by expiry and decided
      causally: DEAD when the branch is merged into the resolved integration
      branch (ancestry, never dates), when branch and worktree are both
      gone, or when the branch is gone after expiry; RENEW when expired but
      the tip advanced since grant or last renewal (the worker is alive);
      QUIESCENT when expired with the tip unmoved (reap — the reservation
      ends, the work remains). --apply deletes DEAD and QUIESCENT leases and
      renews RENEW ones.
EOF
  exit 2
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

[ "$#" -ge 1 ] || usage
cmd=$1
shift

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git-intent: not inside a Git repository" >&2
  exit 2
}
runtime=$(sh "$script_dir/runtime-support.sh" root) || exit 2
leases_dir="$runtime/leases"

now=$(date +%s)

# epoch -> UTC RFC 3339 (BSD date -r, GNU date -d @).
iso_utc() {
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null && return 0
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
}

# UTC RFC 3339 -> epoch (BSD date -j -f, GNU date -d); empty on failure.
epoch_utc() {
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null && return 0
  date -u -d "$1" +%s 2>/dev/null
}

# Duration like 2h, 30m, 90s, or bare seconds -> seconds.
duration_seconds() {
  case "$1" in
    *h) n=${1%h}; mul=3600 ;;
    *m) n=${1%m}; mul=60 ;;
    *s) n=${1%s}; mul=1 ;;
    *) n=$1; mul=1 ;;
  esac
  case "$n" in '' | *[!0-9]*)
    echo "git-intent: invalid duration '$1' (use 2h, 30m, or seconds)" >&2
    exit 2 ;;
  esac
  echo $((n * mul))
}

field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1; }

# Bracketed inline list -> space-separated words.
list_field() {
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1 | tr '[],' '   '
}

paths_related() {
  for p1 in $1; do
    for p2 in $2; do
      [ "$p1" = "$p2" ] && return 0
      case "$p1" in "$p2"/*) return 0 ;; esac
      case "$p2" in "$p1"/*) return 0 ;; esac
    done
  done
  return 1
}

words_shared() {
  for w1 in $1; do
    for w2 in $2; do
      [ "$w1" = "$w2" ] && return 0
    done
  done
  return 1
}

lease_expired() {
  exp=$(field "$1" expires)
  [ -n "$exp" ] || return 1
  e=$(epoch_utc "$exp") || return 1
  [ -n "$e" ] && [ "$e" -lt "$now" ]
}

do_create() {
  [ "$#" -ge 1 ] || usage
  unit=$1
  shift
  scope="" paths="" interfaces="" governance="" domains="" digest=""
  branch="" worktree="" task="" owner="" integration_target="" duration=2h
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scope) [ "$#" -ge 2 ] || usage; scope=$2; shift 2 ;;
      --duration) [ "$#" -ge 2 ] || usage; duration=$2; shift 2 ;;
      --branch) [ "$#" -ge 2 ] || usage; branch=$2; shift 2 ;;
      --worktree) [ "$#" -ge 2 ] || usage; worktree=$2; shift 2 ;;
      --task) [ "$#" -ge 2 ] || usage; task=$2; shift 2 ;;
      --owner) [ "$#" -ge 2 ] || usage; owner=$2; shift 2 ;;
      --integration-target) [ "$#" -ge 2 ] || usage; integration_target=$2; shift 2 ;;
      --digest) [ "$#" -ge 2 ] || usage; digest=$2; shift 2 ;;
      --paths)
        shift
        while [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; do paths="$paths $1"; shift; done ;;
      --interfaces)
        shift
        while [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; do interfaces="$interfaces $1"; shift; done ;;
      --governance)
        shift
        while [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; do governance="$governance $1"; shift; done ;;
      --domains)
        shift
        while [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; do domains="$domains $1"; shift; done ;;
      *) usage ;;
    esac
  done
  [ -n "$paths$interfaces$governance" ] || {
    echo "git-intent: lease requires a path, interface, or governance claim" >&2
    exit 2
  }
  if [ -n "$domains" ]; then
    [ -n "$digest" ] || { echo "git-intent: semantic domain claims require --digest" >&2; exit 2; }
    for domain in $domains; do
      case "$domain" in *[!a-zA-Z0-9._-]*|'') echo "git-intent: malformed semantic domain '$domain'" >&2; exit 2 ;; esac
    done
    # shellcheck disable=SC2086
    digest_row=$(sh "$script_dir/../../intent-brief/scripts/brief-support.sh" digest $domains 2>&1) || {
      printf 'git-intent: cannot validate lease digest: %s\n' "$digest_row" >&2
      exit 2
    }
    actual_digest=$(printf '%s\n' "$digest_row" | sed -n 's/^DIGEST:[[:space:]]*//p')
    [ "$digest" = "$actual_digest" ] || {
      echo "git-intent: lease governing digest is stale (expected $digest, current $actual_digest)" >&2
      exit 2
    }
  fi
  seconds=$(duration_seconds "$duration")
  [ -n "$branch" ] || branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  [ -n "$owner" ] || owner=$branch
  [ -n "$worktree" ] || worktree=$root
  [ -n "$task" ] || task=local:unspecified

  file="$leases_dir/$unit.yml"
  if [ -f "$file" ]; then
    echo "git-intent: live lease for '$unit' exists (owner $(field "$file" owner)) — renew or release it, never overwrite" >&2
    exit 2
  fi

  hits=""
  for f in "$leases_dir"/*.yml; do
    [ -f "$f" ] || continue
    hit=0
    paths_related "$paths" "$(list_field "$f" paths)" && hit=1
    [ "$hit" -eq 1 ] || { words_shared "$interfaces" "$(list_field "$f" interfaces)" && hit=1; }
    [ "$hit" -eq 1 ] || { words_shared "$governance" "$(list_field "$f" governance)" && hit=1; }
    [ "$hit" -eq 1 ] && hits="$hits $(field "$f" unit)"
  done

  created=$(iso_utc "$now")
  expires=$(iso_utc $((now + seconds)))
  tip=$(git rev-parse -q --verify "refs/heads/$branch" 2>/dev/null || echo "")
  ground=""
  target=$integration_target
  [ -n "$target" ] || target=$(sh "$script_dir/../../intent-brief/scripts/resolve-config.sh" 2>/dev/null |
    sed -n 's/^integration_branch_resolved:[[:space:]]*//p')
  if [ -n "$target" ] && ! git show-ref --verify -q "refs/heads/$target"; then
    echo "git-intent: integration target '$target' does not exist locally" >&2
    exit 2
  fi
  [ -z "$target" ] || ground=$(git rev-parse -q --verify "refs/heads/$target" 2>/dev/null || echo "")
  runtime=$(sh "$script_dir/runtime-support.sh" ensure) || exit 2
  leases_dir="$runtime/leases"
  mkdir -p "$leases_dir"
  plist=$(echo $paths | sed 's/ /, /g')
  ilist=$(echo $interfaces | sed 's/ /, /g')
  glist=$(echo $governance | sed 's/ /, /g')
  dlist=$(echo $domains | sed 's/ /, /g')
  {
    printf 'version: 1\n'
    printf 'unit: %s\n' "$unit"
    printf 'owner: %s\n' "$owner"
    printf 'branch: %s\n' "$branch"
    printf 'worktree: %s\n' "$worktree"
    printf 'task: %s\n' "$task"
    [ -z "$scope" ] || printf 'scope: %s\n' "$scope"
    [ -z "$ilist" ] || printf 'interfaces: [%s]\n' "$ilist"
    [ -z "$plist" ] || printf 'paths: [%s]\n' "$plist"
    [ -z "$glist" ] || printf 'governance: [%s]\n' "$glist"
    [ -z "$dlist" ] || printf 'domains: [%s]\n' "$dlist"
    [ -z "$digest" ] || printf 'governing_digest: %s\n' "$digest"
    [ -z "$tip" ] || printf 'tip: %s\n' "$tip"
    [ -z "$ground" ] || printf 'ground: %s\n' "$ground"
    [ -z "$target" ] || printf 'integration_target: %s\n' "$target"
    printf 'created: %s\n' "$created"
    printf 'renewed: %s\n' "$created"
    printf 'expires: %s\n' "$expires"
  } >"$file"
  if [ -n "$hits" ]; then
    echo "LEASE: $unit created — intersects$hits; expires $expires"
  else
    echo "LEASE: $unit created — no live unit intersects; expires $expires"
  fi
}

do_renew() {
  [ "$#" -ge 1 ] || usage
  unit=$1
  shift
  duration=2h
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --duration) [ "$#" -ge 2 ] || usage; duration=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  seconds=$(duration_seconds "$duration")
  file="$leases_dir/$unit.yml"
  [ -f "$file" ] || { echo "git-intent: no lease for '$unit'" >&2; exit 2; }
  renewed=$(iso_utc "$now")
  expires=$(iso_utc $((now + seconds)))
  branch=$(field "$file" branch)
  tip=""
  [ -z "$branch" ] || tip=$(git rev-parse -q --verify "refs/heads/$branch" 2>/dev/null || echo "")
  tmp=$(mktemp "${TMPDIR:-/tmp}/git-intent-lease.XXXXXX") || exit 2
  sed -e "s|^renewed:.*|renewed: $renewed|" -e "s|^expires:.*|expires: $expires|" \
    -e "s|^tip:.*|tip: ${tip:-unknown}|" "$file" >"$tmp" &&
    mv "$tmp" "$file"
  echo "LEASE: $unit renewed — expires $expires"
}

# Coordination-side freshness: a lease goes stale, not dead, when a landing
# on the integration branch since the recorded ground intersects its claim.
do_fresh() {
  [ "$#" -eq 1 ] || usage
  unit=$1
  file="$leases_dir/$unit.yml"
  [ -f "$file" ] || { echo "git-intent: no lease for '$unit'" >&2; exit 2; }
  ground=$(field "$file" ground)
  target=$(field "$file" integration_target)
  [ -n "$target" ] || target=$(sh "$script_dir/../../intent-brief/scripts/resolve-config.sh" 2>/dev/null |
    sed -n 's/^integration_branch_resolved:[[:space:]]*//p')
  if [ -z "$ground" ] || [ -z "$target" ] ||
    ! git rev-parse -q --verify "$ground^{commit}" >/dev/null 2>&1; then
    echo "FRESH: $unit — no recorded ground to compare; re-lease to record one"
    return 0
  fi
  landed=$(git diff --name-only "$ground" "refs/heads/$target" -- 2>/dev/null)
  [ -n "$landed" ] || { echo "FRESH: $unit — nothing landed since the recorded ground"; return 0; }
  claim_paths=$(list_field "$file" paths)
  claim_ifaces=$(list_field "$file" interfaces)
  claim_governance=$(list_field "$file" governance)
  claim_domains=$(list_field "$file" domains)
  hitp=""
  for lp in $landed; do
    for cp in $claim_paths; do
      [ "$lp" = "$cp" ] && { hitp=$lp; break 2; }
      case "$lp" in "$cp"/*) hitp=$lp; break 2 ;; esac
      case "$cp" in "$lp"/*) hitp=$lp; break 2 ;; esac
    done
  done
  if [ -z "$hitp" ] && [ -n "$claim_ifaces" ]; then
    for ifc in $claim_ifaces; do
      if git diff "$ground" "refs/heads/$target" -- 2>/dev/null | grep -qF "$ifc"; then
        hitp="interface:$ifc"
        break
      fi
    done
  fi
  if [ -z "$hitp" ] && [ -n "$claim_governance$claim_domains" ]; then
    if printf '%s\n' "$landed" | grep -Eq '^\.intent/(DOMAINS|CONTRACTS|CONSTRAINTS)\.ya?ml$'; then
      hitp="governance"
    fi
  fi
  if [ -n "$hitp" ]; then
    echo "STALE: $unit — intersecting landing touched $hitp; re-lease against the new ground or release"
    exit 1
  fi
  echo "FRESH: $unit — no intersecting landing since the recorded ground"
}

do_release() {
  [ "$#" -eq 1 ] || usage
  file="$leases_dir/$1.yml"
  [ -f "$file" ] || { echo "git-intent: no lease for '$1'" >&2; exit 2; }
  rm -f "$file"
  echo "released $1"
}

do_list() {
  want=""
  want_domain=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scope) [ "$#" -ge 2 ] || usage; want=$2; shift 2 ;;
      --domain) [ "$#" -ge 2 ] || usage; want_domain=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  found=0
  for f in "$leases_dir"/*.yml; do
    [ -f "$f" ] || continue
    lscope=$(field "$f" scope)
    if [ -n "$want" ]; then
      [ "$want" = "$lscope" ] || continue
    fi
    [ -z "$want_domain" ] || words_shared "$want_domain" "$(list_field "$f" domains)" || continue
    state=live
    lease_expired "$f" && state=expired
    found=1
    echo "LEASE: $(field "$f" unit) ${lscope:-<no scope>} — expires $(field "$f" expires) ($state)"
  done
  [ "$found" -eq 1 ] || echo "no leases"
}

# The conclusive liveness check. Expiry schedules it; every classification is
# causal: ancestry, ref existence, and tip advance — never the clock itself.
do_reap() {
  apply=0
  [ "${1:-}" != "--apply" ] || { apply=1; shift; }
  [ "$#" -eq 0 ] || usage
  found=0
  reaped=0
  renewed_n=0
  for f in "$leases_dir"/*.yml; do
    [ -f "$f" ] || continue
    found=1
    unit=$(field "$f" unit)
    branch=$(field "$f" branch)
    worktree=$(field "$f" worktree)
    tip=$(field "$f" tip)
    target=$(field "$f" integration_target)
    [ -n "$target" ] || target=$(sh "$script_dir/../../intent-brief/scripts/resolve-config.sh" 2>/dev/null |
      sed -n 's/^integration_branch_resolved:[[:space:]]*//p')
    dead=""
    branch_exists=0
    [ -n "$branch" ] && git show-ref --verify -q "refs/heads/$branch" && branch_exists=1
    if [ "$branch_exists" -eq 1 ]; then
      if [ -n "$target" ] && [ "$branch" != "$target" ] &&
        git merge-base --is-ancestor "$branch" "$target" 2>/dev/null; then
        dead="branch merged into $target"
      fi
    else
      if [ -n "$worktree" ] && [ ! -d "$worktree" ]; then
        dead="branch and worktree gone"
      elif lease_expired "$f"; then
        dead="branch missing, lease expired"
      fi
    fi
    if [ -n "$dead" ]; then
      echo "DEAD: $unit ($dead)"
      if [ "$apply" -eq 1 ]; then
        rm -f "$f"
        reaped=$((reaped + 1))
      fi
    elif lease_expired "$f"; then
      current_tip=""
      [ "$branch_exists" -eq 1 ] && current_tip=$(git rev-parse -q --verify "refs/heads/$branch" 2>/dev/null || echo "")
      if [ -n "$current_tip" ] && [ -n "$tip" ] && [ "$current_tip" != "$tip" ]; then
        echo "RENEW: $unit — tip advanced since grant; the worker is alive"
        if [ "$apply" -eq 1 ]; then
          sh "$0" renew "$unit" >/dev/null
          renewed_n=$((renewed_n + 1))
        fi
      else
        echo "QUIESCENT: $unit — expired, tip unmoved; reap ends the reservation, the work remains"
        if [ "$apply" -eq 1 ]; then
          rm -f "$f"
          reaped=$((reaped + 1))
        fi
      fi
    else
      echo "LIVE: $unit"
    fi
  done
  [ "$found" -eq 1 ] || echo "no leases"
  [ "$apply" -eq 0 ] || echo "reaped $reaped lease(s), renewed $renewed_n"
}

case "$cmd" in
  create) do_create "$@" ;;
  renew) do_renew "$@" ;;
  release) do_release "$@" ;;
  list) do_list "$@" ;;
  fresh) do_fresh "$@" ;;
  reap) do_reap "$@" ;;
  *) usage ;;
esac
