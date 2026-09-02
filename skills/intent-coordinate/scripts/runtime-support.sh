#!/bin/sh
# Locate and maintain the visible, ignored runtime workspace shared by every
# linked worktree. Runtime state affects coordination and cache reuse only;
# deleting it cannot change repository meaning or landed Git history.

set -u

usage() {
  cat >&2 <<'EOF'
usage:
  runtime-support.sh root
      Print the shared <primary-worktree>/intent-work path.
  runtime-support.sh ensure
      Create the runtime workspace and its self-ignore marker, then print it.
  runtime-support.sh status
      Show workboards, lease lifecycle, and disposable cache counts.
  runtime-support.sh clean [--apply]
      Report completed boards, dead or quiescent leases, and disposable
      observation/receipt caches. --apply removes only those items; live
      leases and incomplete boards remain.
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
runtime_root="$primary_root/intent-work"

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

    boards=0
    for file in "$runtime_root"/boards/*.yml; do
      [ -f "$file" ] || continue
      boards=$((boards + 1))
      id=$(basename "$file" .yml)
      printf 'BOARD: %s\n' "$id"
      sh "$script_dir/workboard-status.sh" "$id" 2>&1 | sed 's/^/  /'
    done
    [ "$boards" -gt 0 ] || echo "BOARDS: none"

    sh "$script_dir/lease-support.sh" list
    for file in "$runtime_root"/leases/*.yml; do
      [ -f "$file" ] || continue
      unit=$(sed -n 's/^unit:[[:space:]]*//p' "$file" | head -1)
      [ -n "$unit" ] || continue
      sh "$script_dir/lease-support.sh" fresh "$unit" 2>&1 || true
    done
    for cache in observations receipts; do
      count=0
      if [ -d "$runtime_root/$cache" ]; then
        count=$(find "$runtime_root/$cache" -type f 2>/dev/null | wc -l | tr -d ' ')
      fi
      printf 'CACHE: %s %s file(s) — disposable\n' "$cache" "$count"
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

    for file in "$runtime_root"/boards/*.yml; do
      [ -f "$file" ] || continue
      id=$(basename "$file" .yml)
      if state=$(sh "$script_dir/workboard-status.sh" "$id" 2>/dev/null) && printf '%s\n' "$state" | awk '
        NR == 1 { next }
        NF && $2 != "landed" { incomplete=1 }
        END { exit incomplete }
      '; then
        if [ "$apply" -eq 1 ]; then
          rm -f "$file"
          printf 'CLEANED: completed board %s\n' "$id"
        else
          printf 'CLEANABLE: completed board %s\n' "$id"
        fi
      fi
    done

    for cache in observations receipts; do
      [ -d "$runtime_root/$cache" ] || continue
      count=$(find "$runtime_root/$cache" -type f 2>/dev/null | wc -l | tr -d ' ')
      [ "$count" -gt 0 ] || continue
      if [ "$apply" -eq 1 ]; then
        find "$runtime_root/$cache" -type f -delete
        printf 'CLEANED: %s %s cache file(s)\n' "$cache" "$count"
      else
        printf 'CLEANABLE: %s %s cache file(s)\n' "$cache" "$count"
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
