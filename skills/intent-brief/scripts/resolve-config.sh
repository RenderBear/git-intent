#!/bin/sh
# Resolve the two repository-level choices git-intent cannot safely invent:
# how consequential ambiguity is resolved, and which local branch is the
# integration target. Planning remains an agent/runtime concern.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git-intent: not inside a Git repository" >&2
  exit 2
}
config="$root/.intent/config.yml"

current_branch() {
  if [ -n "${GIT_INTENT_INTEGRATION_TARGET:-}" ]; then
    printf '%s\n' "$GIT_INTENT_INTEGRATION_TARGET"
    return 0
  fi
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [ -n "$branch" ] || {
    echo "git-intent: integration_branch is not configured and HEAD is detached" >&2
    exit 2
  }
  printf '%s\n' "$branch"
}

current_source() {
  if [ -n "${GIT_INTENT_INTEGRATION_TARGET:-}" ]; then printf 'captured\n'; else printf 'current\n'; fi
}

emit() {
  resolution=$1
  branch=$2
  source=$3
  branch_source=$4

  unborn=0
  if ! git show-ref --verify -q "refs/heads/$branch"; then
    symbolic=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    if { [ "$symbolic" = "$branch" ] && ! git rev-parse -q --verify HEAD >/dev/null 2>&1; } ||
       { [ "${GIT_INTENT_ALLOW_UNBORN:-0}" = 1 ] && [ "${GIT_INTENT_INTEGRATION_TARGET:-}" = "$branch" ]; }; then
      unborn=1
    else
      echo "git-intent: configured integration branch '$branch' does not exist locally" >&2
      exit 2
    fi
  fi

  printf 'resolution: %s\n' "$resolution"
  printf 'integration_branch: %s\n' "$branch"
  printf 'source: %s\n' "$source"
  printf 'integration_branch_resolved: %s\n' "$branch"
  printf 'branch_source: %s\n' "$branch_source"
  [ "$unborn" -eq 0 ] || printf 'integration_branch_unborn: true\n'
}

if [ ! -e "$config" ]; then
  emit assisted "$(current_branch)" default "$(current_source)"
  exit 0
fi

[ -f "$config" ] || {
  echo "git-intent: .intent/config.yml is not a regular file" >&2
  exit 2
}

version=$(sed -n 's/^version:[[:space:]]*//p' "$config")
resolution=$(sed -n 's/^resolution:[[:space:]]*//p' "$config")
integration_branch=$(sed -n 's/^integration_branch:[[:space:]]*//p' "$config")
unknown=$(awk -F: '/^[a-z_]+:/ && $1 != "version" && $1 != "resolution" && $1 != "integration_branch" { print $1 }' "$config")

[ "$version" = "1" ] || {
  echo "git-intent: .intent/config.yml must declare version: 1" >&2
  exit 2
}

[ -n "$resolution" ] || resolution=assisted
case "$resolution" in
  assisted|auto) ;;
  *)
    echo "git-intent: .intent/config.yml has invalid resolution '$resolution' (use assisted or auto)" >&2
    exit 2
    ;;
esac

if [ -n "$unknown" ]; then
  echo "git-intent: .intent/config.yml has unknown field '$unknown'" >&2
  exit 2
fi

if [ -n "$integration_branch" ]; then
  emit "$resolution" "$integration_branch" .intent/config.yml config
else
  emit "$resolution" "$(current_branch)" .intent/config.yml "$(current_source)"
fi
