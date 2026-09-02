#!/bin/sh
# Locate and maintain the ignored planning workspace shared by every linked
# worktree. It contains only active plans and leases. Deleting it cannot change
# repository meaning or landed Git history, but can discard live coordination.

set -u

usage() {
  cat >&2 <<'EOF'
usage:
  runtime-support.sh root
      Print the shared <primary-worktree>/.intent/runtime path.
  runtime-support.sh ensure
      Create the runtime workspace and its self-ignore marker, then print it.
  runtime-support.sh status
      Show plans and lease lifecycle.
  runtime-support.sh clean [--apply]
      Report completed plans and dead or quiescent leases. --apply removes
      only those items; live leases and incomplete plans remain.
EOF
  exit 2
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git-intent: not inside a non-bare Git worktree" >&2
  exit 2
}
primary_root=$(git worktree list --porcelain 2>/dev/null |
  awk '/^worktree / { sub(/^worktree /, ""); print; exit }')
[ -n "$primary_root" ] || primary_root=$repo_root
runtime_root="$primary_root/.intent/runtime"

[ "$#" -ge 1 ] || usage
cmd=$1
shift

case "$cmd" in
  root)
    [ "$#" -eq 0 ] || usage
    printf '%s\n' "$runtime_root"
    ;;
  ensure)
    [ "$#" -eq 0 ] || usage
    mkdir -p "$runtime_root"
    if [ ! -e "$runtime_root/.gitignore" ]; then
      printf '*\n' >"$runtime_root/.gitignore"
    fi
    printf '%s\n' "$runtime_root"
    ;;
  status)
    [ "$#" -eq 0 ] || usage
    printf 'RUNTIME: %s\n' "$runtime_root"
    if [ ! -d "$runtime_root" ]; then
      echo "STATUS: empty"
      exit 0
    fi

    plans=0
    for file in "$runtime_root"/plans/*.yml; do
      [ -f "$file" ] || continue
      plans=$((plans + 1))
      id=$(basename "$file" .yml)
      printf 'PLAN: %s\n' "$id"
      sh "$script_dir/workboard-status.sh" "$id" 2>&1 | sed 's/^/  /'
    done
    [ "$plans" -gt 0 ] || echo "PLANS: none"

    sh "$script_dir/lease-support.sh" list
    for file in "$runtime_root"/leases/*.yml; do
      [ -f "$file" ] || continue
      unit=$(sed -n 's/^unit:[[:space:]]*//p' "$file" | head -1)
      [ -n "$unit" ] || continue
      sh "$script_dir/lease-support.sh" fresh "$unit" 2>&1 || true
    done
    ;;
  clean)
    apply=0
    if [ "${1:-}" = "--apply" ]; then
      apply=1
      shift
    fi
    [ "$#" -eq 0 ] || usage
    [ -d "$runtime_root" ] || { echo "CLEAN: nothing to do"; exit 0; }

    if [ "$apply" -eq 1 ]; then
      sh "$script_dir/lease-support.sh" reap --apply
    else
      sh "$script_dir/lease-support.sh" reap
    fi

    for file in "$runtime_root"/plans/*.yml; do
      [ -f "$file" ] || continue
      id=$(basename "$file" .yml)
      if state=$(sh "$script_dir/workboard-status.sh" "$id" 2>/dev/null) && printf '%s\n' "$state" | awk '
        NR == 1 { next }
        NF && $2 != "landed" { incomplete=1 }
        END { exit incomplete }
      '; then
        if [ "$apply" -eq 1 ]; then
          rm -f "$file"
          printf 'CLEANED: completed plan %s\n' "$id"
        else
          printf 'CLEANABLE: completed plan %s\n' "$id"
        fi
      fi
    done

    if [ "$apply" -eq 1 ] && [ -d "$runtime_root" ]; then
      find "$runtime_root" -depth -type d -empty -exec rmdir {} \; 2>/dev/null || true
      payload=$(find "$runtime_root" -mindepth 1 ! -name .gitignore -print -quit 2>/dev/null || true)
      if [ -z "$payload" ]; then
        rm -f "$runtime_root/.gitignore"
        rmdir "$runtime_root" 2>/dev/null || true
      fi
    fi
    ;;
  *) usage ;;
esac
