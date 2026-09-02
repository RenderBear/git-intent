#!/bin/sh
# Derive plan status from repository facts. A plan contains objectives,
# dependencies, and claims, never stored status. Landed comes from Intent-Unit
# trailers; active comes from live leases; readiness comes from dependencies.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runtime=$(sh "$script_dir/runtime-support.sh" root) || exit 2
plans_dir="$runtime/plans"

if [ "$#" -lt 1 ]; then
  if [ -d "$plans_dir" ] && ls "$plans_dir"/*.yml >/dev/null 2>&1; then
    echo "plans:"
    for f in "$plans_dir"/*.yml; do
      b=$(basename "$f")
      echo "  ${b%.yml}"
    done
  else
    echo "no plans"
  fi
  exit 0
fi

plan_id=$1
shift
pinned_only=0
if [ "${1:-}" = "--pinned" ]; then
  pinned_only=1
  shift
fi
[ "$#" -eq 0 ] || {
  echo "usage: workboard-status.sh [<plan> [--pinned]]" >&2
  exit 2
}

plan="$plans_dir/$plan_id.yml"
[ -f "$plan" ] || {
  echo "git-intent: no plan '$plan_id'" >&2
  exit 1
}

target=$(sed -n 's/^integration_target:[[:space:]]*//p' "$plan" | head -1)
[ -n "$target" ] || target=HEAD
git rev-parse -q --verify "$target" >/dev/null 2>&1 || target=HEAD

landed_file=$(mktemp "${TMPDIR:-/tmp}/git-intent-board-status.XXXXXX") || exit 2
trap 'rm -f "$landed_file"' EXIT HUP INT TERM
git log --first-parent "$target" --format='%(trailers:key=Intent-Unit,valueonly,separator=%x0a)' 2>/dev/null |
  sed '/^$/d' | sort -u >"$landed_file"

is_landed() { grep -qx "$1" "$landed_file"; }

units() {
  awk '
    /^  - id:/ {
      if (id != "") print id "|" deps
      id=$0; sub(/^[^:]*: */, "", id); sub(/[[:space:]]+#.*$/, "", id); deps=""
      next
    }
    id != "" && /^    dependencies:/ {
      deps=$0; sub(/^[^:]*: */, "", deps); gsub(/[][,]/, " ", deps)
      gsub(/[[:space:]]+/, " ", deps); sub(/^ /, "", deps); sub(/ $/, "", deps)
    }
    END { if (id != "") print id "|" deps }
  ' "$plan"
}

if [ "$pinned_only" -eq 1 ]; then
  units | while IFS='|' read -r uid udeps; do
    if is_landed "$uid"; then
      echo "PINNED: $uid (landed)"
    elif [ -f "$runtime/leases/$uid.yml" ]; then
      echo "PINNED: $uid (leased)"
    fi
  done
  exit 0
fi

printf '%-14s %-13s %s\n' UNIT STATE DEPENDENCIES
units | while IFS='|' read -r uid udeps; do
  if is_landed "$uid"; then
    state=landed
  elif [ -f "$runtime/leases/$uid.yml" ]; then
    state=active
  else
    state=dispatchable
    for dep in $udeps; do
      is_landed "$dep" || { state=waiting; break; }
    done
  fi
  printf '%-14s %-13s %s\n' "$uid" "$state" "${udeps:-—}"
done
