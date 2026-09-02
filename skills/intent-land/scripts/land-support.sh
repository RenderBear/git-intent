#!/bin/sh
# Construct and verify a prospective landing before atomically advancing the
# integration ref. The target branch is never moved on a failed preflight.

set -eu

usage() {
  cat >&2 <<'EOF'
usage:
  land-support.sh direct <subject> --unit <id>... --scope <scope>...
                  --paths <path>... [--check <locator>]... [--allow-open]
                  [--board <id>]
  land-support.sh merge <branch> <subject> --unit <id>... --scope <scope>...
                  [--check <locator>]... [--allow-open] [--board <id>]

Check locators are executable `command:path` wrappers or supported `test:`
locators. `--allow-open` states that intent-land has already resolved the
authority gate for an open or breaking contract transition.
EOF
  exit 2
}

[ "$#" -ge 2 ] || usage
mode=$1
shift
merge_branch=""
case "$mode" in
  direct) subject=$1; shift ;;
  merge) [ "$#" -ge 2 ] || usage; merge_branch=$1; subject=$2; shift 2 ;;
  *) usage ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git-intent: not inside a Git repository" >&2
  exit 2
}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
brief_dir="$script_dir/../../intent-brief/scripts"
coordinate_dir="$script_dir/../../intent-coordinate/scripts"
audit_dir="$script_dir/../../intent-audit/scripts"
runtime=$(sh "$coordinate_dir/runtime-support.sh" root) || exit 2

units=""
scopes=""
paths=""
checks=""
board=""
allow_open=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --unit) [ "$#" -ge 2 ] || usage; units="$units $2"; shift 2 ;;
    --scope) [ "$#" -ge 2 ] || usage; scopes="$scopes $2"; shift 2 ;;
    --board) [ "$#" -ge 2 ] || usage; board=$2; shift 2 ;;
    --check) [ "$#" -ge 2 ] || usage; checks="$checks
$2"; shift 2 ;;
    --allow-open) allow_open=1; shift ;;
    --paths)
      shift
      while [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; do
        paths="$paths
$1"
        shift
      done
      ;;
    *) usage ;;
  esac
done

[ -n "$units" ] || { echo "git-intent: landing requires at least one unit id" >&2; exit 2; }
[ -n "$scopes" ] || { echo "git-intent: landing requires at least one scope" >&2; exit 2; }
[ "$mode" != direct ] || [ -n "$paths" ] || { echo "git-intent: direct landing requires --paths" >&2; exit 2; }

target=$(sh "$brief_dir/resolve-config.sh" | sed -n 's/^integration_branch_resolved:[[:space:]]*//p')
[ -n "$target" ] || { echo "git-intent: no integration branch resolved" >&2; exit 2; }
current=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[ "$current" = "$target" ] || {
  echo "git-intent: atomic landing must run in the integration worktree ('$target', currently '${current:-detached}')" >&2
  exit 2
}
unborn=0
old=$(git rev-parse -q --verify "refs/heads/$target^{commit}" 2>/dev/null || true)
if [ -z "$old" ]; then
  if ! git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    unborn=1
  else
    echo "git-intent: integration branch '$target' has no commit" >&2
    exit 2
  fi
fi
[ "$mode" != merge ] || [ "$unborn" -eq 0 ] || {
  echo "git-intent: an unborn integration branch requires a direct first landing" >&2
  exit 2
}

git diff --cached --quiet -- || {
  echo "git-intent: staged changes exist; preserve or unstage them before atomic landing" >&2
  exit 2
}
if [ "$mode" = merge ] && [ -n "$(git status --porcelain)" ]; then
  echo "git-intent: merge landing requires a clean integration worktree" >&2
  exit 2
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/git-intent-land.XXXXXX")
verify_dir="$tmp/verify"
worktree_added=0
cleanup() {
  if [ "$worktree_added" -eq 1 ]; then
    git -C "$root" worktree remove --force "$verify_dir" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

message_args=""
for unit in $units; do message_args="$message_args --unit $unit"; done
for scope in $scopes; do message_args="$message_args --scope $scope"; done
[ -z "$board" ] || message_args="$message_args --board $board"
# Arguments are identifiers validated by the message generator and contain no
# whitespace by schema. shellcheck disable=SC2086
sh "$brief_dir/brief-support.sh" message "$subject" $message_args >"$tmp/message"

if [ "$mode" = direct ]; then
  index="$tmp/index"
  if [ "$unborn" -eq 1 ]; then
    GIT_INDEX_FILE="$index" git read-tree --empty
  else
    GIT_INDEX_FILE="$index" git read-tree "$old^{tree}"
  fi
  printf '%s\n' "$paths" | sed '/^$/d' | while IFS= read -r path; do
    case "$path" in /*|../*|*/../*|*'/..') echo "git-intent: invalid landing path '$path'" >&2; exit 2 ;; esac
    GIT_INDEX_FILE="$index" git add -A -- "$path"
  done
  tree=$(GIT_INDEX_FILE="$index" git write-tree)
  if [ "$unborn" -eq 0 ]; then
    [ "$tree" != "$(git rev-parse "$old^{tree}")" ] || {
      echo "git-intent: selected paths produce no change" >&2
      exit 2
    }
    candidate=$(git commit-tree "$tree" -p "$old" -F "$tmp/message")
  else
    candidate=$(git commit-tree "$tree" -F "$tmp/message")
  fi
else
  branch_ref=$(git rev-parse -q --verify "refs/heads/$merge_branch^{commit}" 2>/dev/null) || {
    echo "git-intent: merge branch '$merge_branch' does not exist locally" >&2
    exit 2
  }
  merge_output=$(git merge-tree --write-tree "$old" "$branch_ref" 2>&1) || {
    printf '%s\n' "$merge_output" >&2
    echo "git-intent: prospective merge conflicts; integration branch unchanged" >&2
    exit 1
  }
  tree=$(printf '%s\n' "$merge_output" | sed -n '1p')
  candidate=$(git commit-tree "$tree" -p "$old" -p "$branch_ref" -F "$tmp/message")
fi

git worktree add --quiet --detach "$verify_dir" "$candidate"
worktree_added=1

if [ "$unborn" -eq 1 ]; then
  reach=$(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" reach --root)
else
  reach=$(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" reach "$old")
fi
printf '%s\n' "$reach"
verdict=$(printf '%s\n' "$reach" | sed -n 's/^REACH:[[:space:]]*//p')
case "$verdict" in
  local|bounded) ;;
  open)
    if printf '%s\n' "$reach" | grep -q '^MOVE:'; then :
    elif [ "$allow_open" -ne 1 ]; then
      echo "git-intent: open contract boundary requires resolved authority (--allow-open)" >&2
      exit 1
    fi
    ;;
  gated)
    [ "$allow_open" -eq 1 ] || {
      echo "git-intent: breaking contract transition requires resolved authority (--allow-open)" >&2
      exit 1
    }
    ;;
  *) echo "git-intent: could not classify prospective reach" >&2; exit 2 ;;
esac

(cd "$verify_dir" && GIT_INTENT_INTEGRATION_TARGET="$target" GIT_INTENT_ALLOW_UNBORN="$unborn" sh "$brief_dir/validate-state.sh" --landing)
(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" trailer "$candidate")

runtime=$(sh "$coordinate_dir/runtime-support.sh" ensure) || exit 2
receipts="$runtime/receipts/$tree"
mkdir -p "$receipts"

run_locator() {
  locator=$1
  key=$(printf '%s' "$locator" | cksum | awk '{ print $1 "-" $2 }')
  receipt="$receipts/$key"
  if [ -f "$receipt" ]; then
    echo "CHECK: cached — $locator"
    return 0
  fi

  echo "CHECK: running — $locator"
  case "$locator" in
    command:*)
      path=${locator#command:}
      [ -f "$verify_dir/$path" ] && [ -x "$verify_dir/$path" ] || {
        echo "git-intent: command verifier '$path' is missing or not executable" >&2
        return 1
      }
      (cd "$verify_dir" && "./$path")
      ;;
    test:*)
      spec=${locator#test:}
      path=${spec%%::*}
      case "$path" in
        *.sh) (cd "$verify_dir" && sh "$path") ;;
        *.py) (cd "$verify_dir" && python3 -m pytest "$spec") ;;
        *)
          [ -x "$verify_dir/$path" ] || {
            echo "git-intent: test verifier '$locator' is not directly executable; use a command: wrapper" >&2
            return 1
          }
          (cd "$verify_dir" && "./$path")
          ;;
      esac
      ;;
    schema:*)
      path=${locator#schema:}; path=${path%%#*}
      [ -x "$verify_dir/$path" ] || {
        echo "git-intent: schema verifier '$locator' needs an executable command: wrapper" >&2
        return 1
      }
      (cd "$verify_dir" && "./$path")
      ;;
    *)
      echo "git-intent: unsupported check locator '$locator'" >&2
      return 1
      ;;
  esac
  printf 'tree: %s\ncheck: %s\n' "$tree" "$locator" >"$receipt"
}

if [ "$unborn" -eq 1 ]; then
  verifier_rows=$(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" verifiers --root)
else
  verifier_rows=$(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" verifiers "$old")
fi
printf '%s\n' "$verifier_rows" | sed -n 's/^VERIFY: [^ ]* //p' | while IFS= read -r locator; do
  [ -n "$locator" ] || continue
  case "$locator" in
    contract:*)
      echo "git-intent: nested contract verifier '$locator' must resolve to an executable verifier before landing" >&2
      exit 1
      ;;
    *) run_locator "$locator" ;;
  esac
done

printf '%s\n' "$checks" | sed '/^$/d' | while IFS= read -r locator; do
  run_locator "$locator"
done

# Compare-and-swap is the atomic boundary: if another landing advanced the
# target during verification, this fails and the verified candidate remains
# dangling rather than overwriting newer work.
if [ "$unborn" -eq 1 ]; then
  zero=0000000000000000000000000000000000000000
  git update-ref "refs/heads/$target" "$candidate" "$zero"
else
  git update-ref "refs/heads/$target" "$candidate" "$old"
fi
if [ "$mode" = direct ]; then
  git read-tree "$candidate"
else
  git read-tree --reset -u "$candidate"
fi

for unit in $units; do
  if [ -f "$runtime/leases/$unit.yml" ]; then
    sh "$coordinate_dir/lease-support.sh" release "$unit" >/dev/null
  fi
done

if [ -n "$board" ] && [ -f "$runtime/boards/$board.yml" ]; then
  board_state=$(sh "$coordinate_dir/workboard-status.sh" "$board" 2>/dev/null || true)
  if ! printf '%s\n' "$board_state" | grep -Eq ' (active|waiting|dispatchable) '; then
    rm -f "$runtime/boards/$board.yml"
  fi
fi

echo "LANDED: $candidate -> $target (prospective tree verified before ref update)"
recurrence=$(sh "$audit_dir/audit-support.sh" recurrence 2>/dev/null || true)
if [ -n "$recurrence" ]; then
  printf '%s\n' "$recurrence" | sed 's/^RECURRENT:/ADOPTION-SUGGESTION:/'
fi
