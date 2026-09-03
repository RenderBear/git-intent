#!/bin/sh
# Construct and verify a prospective landing before atomically advancing the
# integration ref. The target branch is never moved on a failed preflight.

set -eu

usage() {
  cat >&2 <<'EOF'
usage:
  land-support.sh direct <subject> --unit <id>... --scope <scope>...
                  --paths <path>... [--domain <id>]... [--interface <name>]...
                  [--governance <ref>]... [--reviewed constraint:<id>]...
                  --boundary-review <no-record|audit:id|recorded>
                  [--check <locator>]... [--allow-open] [--plan <id>]
  land-support.sh merge <branch> <subject> --unit <id>... --scope <scope>...
                  [--domain <id>]... [--interface <name>]...
                  [--governance <ref>]... [--reviewed constraint:<id>]...
                  --boundary-review <no-record|audit:id|recorded>
                  [--check <locator>]... [--allow-open] [--plan <id>]

Check locators are executable `command:path` wrappers or supported `test:`
locators. `--allow-open` states that intent-land has already resolved the
authority gate for an open or gated governance transition. `no-record` states
that the durable-meaning review found no new governance to adopt. `audit:id`
names a fresh scoped audit with only no-action or observation findings.
`recorded` requires the owning domain, contract, or constraint references via
`--governance`.
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
domains=""
interfaces=""
governance=""
reviewed=""
boundary_review=""
plan=""
allow_open=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --unit) [ "$#" -ge 2 ] || usage; units="$units $2"; shift 2 ;;
    --scope) [ "$#" -ge 2 ] || usage; scopes="$scopes $2"; shift 2 ;;
    --domain) [ "$#" -ge 2 ] || usage; domains="$domains $2"; shift 2 ;;
    --interface) [ "$#" -ge 2 ] || usage; interfaces="$interfaces $2"; shift 2 ;;
    --governance) [ "$#" -ge 2 ] || usage; governance="$governance $2"; shift 2 ;;
    --reviewed) [ "$#" -ge 2 ] || usage; reviewed="$reviewed $2"; shift 2 ;;
    --boundary-review)
      [ "$#" -ge 2 ] || usage
      [ -z "$boundary_review" ] || { echo "git-intent: pass exactly one --boundary-review" >&2; exit 2; }
      boundary_review=$2
      shift 2
      ;;
    --plan) [ "$#" -ge 2 ] || usage; plan=$2; shift 2 ;;
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
[ -n "$boundary_review" ] || { echo "git-intent: landing requires exactly one --boundary-review disposition" >&2; exit 2; }
case "$boundary_review" in
  no-record|recorded) ;;
  audit:*)
    audit_id=${boundary_review#audit:}
    case "$audit_id" in ''|*[!a-zA-Z0-9._-]*) echo "git-intent: invalid boundary audit id '$audit_id'" >&2; exit 2 ;; esac
    ;;
  *) echo "git-intent: invalid --boundary-review '$boundary_review'" >&2; exit 2 ;;
esac
[ "$boundary_review" != recorded ] || [ -n "$governance" ] || {
  echo "git-intent: --boundary-review recorded requires at least one --governance reference" >&2
  exit 2
}

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
[ "$mode" != direct ] || [ "$unborn" -eq 1 ] || {
  echo "git-intent: direct landing is reserved for the first commit on an unborn integration branch; use a work branch and merge" >&2
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
for domain in $domains; do message_args="$message_args --domain $domain"; done
[ -z "$plan" ] || message_args="$message_args --plan $plan"
# Arguments are identifiers validated by the message generator and contain no
# whitespace by schema. shellcheck disable=SC2086
sh "$brief_dir/brief-support.sh" message "$subject" $message_args >"$tmp/message"
printf 'Intent-Boundary: %s\n' "$boundary_review" >>"$tmp/message"
for ref in $governance; do printf 'Intent-Governance: %s\n' "$ref" >>"$tmp/message"; done

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

reach_args=""
for domain in $domains; do reach_args="$reach_args --domain $domain"; done
for interface in $interfaces; do reach_args="$reach_args --interface $interface"; done
if [ "$unborn" -eq 1 ]; then
  # shellcheck disable=SC2086
  reach=$(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" reach --root $reach_args)
else
  # shellcheck disable=SC2086
  reach=$(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" reach "$old" $reach_args)
fi
printf '%s\n' "$reach"
verdict=$(printf '%s\n' "$reach" | sed -n 's/^REACH:[[:space:]]*//p')
case "$verdict" in
  local|bounded) ;;
  open)
    if [ "$allow_open" -ne 1 ]; then
      echo "git-intent: open governance boundary requires resolved authority (--allow-open)" >&2
      exit 1
    fi
    ;;
  gated)
    [ "$allow_open" -eq 1 ] || {
      echo "git-intent: gated governance transition requires resolved authority (--allow-open)" >&2
      exit 1
    }
    ;;
  *) echo "git-intent: could not classify prospective reach" >&2; exit 2 ;;
esac

(cd "$verify_dir" && GIT_INTENT_INTEGRATION_TARGET="$target" GIT_INTENT_ALLOW_UNBORN="$unborn" sh "$brief_dir/validate-state.sh" --landing)
(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" trailer "$candidate")

governance_exists() {
  ref=$1
  kind=${ref%%:*}
  id=${ref#*:}
  [ "$id" != "$ref" ] && [ -n "$id" ] || return 1
  case "$kind" in
    domain) file=.intent/DOMAINS.yml ;;
    contract) file=.intent/CONTRACTS.yml ;;
    constraint) file=.intent/CONSTRAINTS.yml ;;
    *) return 1 ;;
  esac
  [ -f "$verify_dir/$file" ] &&
    sed -n 's/^  - id:[[:space:]]*//p' "$verify_dir/$file" |
    sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' |
    grep -qxF "$id"
}

case "$boundary_review" in
  no-record)
    if printf '%s\n' "$reach" | grep -q '^GOVERNANCE:'; then
      echo "git-intent: governance changed; use --boundary-review recorded with --governance references" >&2
      exit 1
    fi
    echo "BOUNDARY-REVIEW: no-record"
    ;;
  audit:*)
    if printf '%s\n' "$reach" | grep -q '^GOVERNANCE:'; then
      echo "git-intent: governance changed; use --boundary-review recorded with --governance references" >&2
      exit 1
    fi
    audit_id=${boundary_review#audit:}
    audit_file="$verify_dir/.intent/audits/$audit_id.yml"
    [ -f "$audit_file" ] || { echo "git-intent: boundary audit '$audit_id' is absent from the candidate" >&2; exit 1; }
    audit_mode=$(sed -n 's/^mode:[[:space:]]*//p' "$audit_file" | head -1 |
      sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')
    [ "$audit_mode" = scope ] || {
      echo "git-intent: boundary review requires a scoped audit" >&2
      exit 1
    }
    if sed -n 's/^    disposition:[[:space:]]*//p' "$audit_file" |
        sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' |
        grep -Eq '^(adoptable|needs-authority|needs-verifier)$'; then
      echo "git-intent: boundary audit '$audit_id' has adoptable or unresolved findings" >&2
      exit 1
    fi
    (cd "$verify_dir" && sh "$audit_dir/audit-support.sh" fresh "$audit_id" HEAD) || {
      echo "git-intent: boundary audit '$audit_id' is not fresh for the candidate" >&2
      exit 1
    }
    echo "BOUNDARY-REVIEW: audit:$audit_id — no governance adoption required"
    ;;
  recorded)
    for ref in $governance; do
      governance_exists "$ref" || {
        echo "git-intent: boundary governance '$ref' is not an accepted candidate record" >&2
        exit 1
      }
    done
    echo "BOUNDARY-REVIEW: recorded —$(printf ' %s' $governance)"
    ;;
esac

run_locator() {
  locator=$1
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
}

if [ "$unborn" -eq 1 ]; then
  # shellcheck disable=SC2086
  verifier_rows=$(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" verifiers --root $reach_args)
else
  # shellcheck disable=SC2086
  verifier_rows=$(cd "$verify_dir" && sh "$brief_dir/brief-support.sh" verifiers "$old" $reach_args)
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

printf '%s\n' "$verifier_rows" | sed -n 's/^REVIEW: \([^ ]*\) .*/\1/p' | while IFS= read -r constraint; do
  found=0
  for accepted in $reviewed; do [ "$accepted" = "$constraint" ] && found=1; done
  [ "$found" -eq 1 ] || {
    echo "git-intent: affected semantic $constraint requires --reviewed $constraint after prospective-tree review" >&2
    exit 1
  }
  echo "REVIEW: accepted — $constraint"
done

printf '%s\n' "$checks" | sed '/^$/d' | while IFS= read -r locator; do
  run_locator "$locator"
done

# A coordinated landing must be backed by live leases whose combined claims
# cover the branch, integration target, changed paths, domains, and governance.
if [ -n "$plan" ]; then
  plan_file="$runtime/plans/$plan.yml"
  [ -f "$plan_file" ] || { echo "git-intent: no runtime plan '$plan'" >&2; exit 1; }
  sh "$coordinate_dir/workboard-support.sh" validate "$plan" >/dev/null || exit 1
  lease_files=""
  for unit in $units; do
    lease_file="$runtime/leases/$unit.yml"
    [ -f "$lease_file" ] || { echo "git-intent: coordinated unit '$unit' has no live lease" >&2; exit 1; }
    sh "$coordinate_dir/lease-support.sh" fresh "$unit" >/dev/null || exit 1
    lease_target=$(sed -n 's/^integration_target:[[:space:]]*//p' "$lease_file" | head -1)
    [ "$lease_target" = "$target" ] || { echo "git-intent: lease '$unit' targets '$lease_target', not '$target'" >&2; exit 1; }
    if [ "$mode" = merge ]; then
      lease_branch=$(sed -n 's/^branch:[[:space:]]*//p' "$lease_file" | head -1)
      [ "$lease_branch" = "$merge_branch" ] || { echo "git-intent: lease '$unit' belongs to '$lease_branch', not '$merge_branch'" >&2; exit 1; }
    fi
    lease_files="$lease_files $lease_file"
  done

  actual_paths=$(if [ "$unborn" -eq 1 ]; then git -C "$verify_dir" diff-tree --no-commit-id --name-only -r --root HEAD; else git -C "$verify_dir" diff --name-only "$old" HEAD; fi)
  for changed in $actual_paths; do
    covered=0
    for lease_file in $lease_files; do
      claim_paths=$(sed -n 's/^paths:[[:space:]]*//p' "$lease_file" | head -1 | tr '[],' '   ')
      for claim in $claim_paths; do
        [ "$changed" = "$claim" ] && covered=1
        case "$changed" in "$claim"/*) covered=1 ;; esac
      done
    done
    [ "$covered" -eq 1 ] || { echo "git-intent: coordinated path '$changed' is outside the combined lease claims" >&2; exit 1; }
  done
  for requested in $interfaces; do
    found=0; for lease_file in $lease_files; do
      values=$(sed -n 's/^interfaces:[[:space:]]*//p' "$lease_file" | head -1 | tr '[],' '   ')
      for value in $values; do [ "$value" = "$requested" ] && found=1; done
    done
    [ "$found" -eq 1 ] || { echo "git-intent: interface '$requested' is absent from the combined lease claims" >&2; exit 1; }
  done
  for requested in $domains; do
    found=0; for lease_file in $lease_files; do
      values=$(sed -n 's/^domains:[[:space:]]*//p' "$lease_file" | head -1 | tr '[],' '   ')
      for value in $values; do [ "$value" = "$requested" ] && found=1; done
    done
    [ "$found" -eq 1 ] || { echo "git-intent: domain '$requested' is absent from the combined lease context" >&2; exit 1; }
  done
  for requested in $governance; do
    found=0; for lease_file in $lease_files; do
      values=$(sed -n 's/^governance:[[:space:]]*//p' "$lease_file" | head -1 | tr '[],' '   ')
      for value in $values; do [ "$value" = "$requested" ] && found=1; done
    done
    [ "$found" -eq 1 ] || { echo "git-intent: governance '$requested' is absent from the combined lease claims" >&2; exit 1; }
  done
fi

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

if [ -n "$plan" ] && [ -f "$runtime/plans/$plan.yml" ]; then
  plan_state=$(sh "$coordinate_dir/workboard-status.sh" "$plan" 2>/dev/null || true)
  if ! printf '%s\n' "$plan_state" | grep -Eq ' (active|waiting|dispatchable) '; then
    rm -f "$runtime/plans/$plan.yml"
  fi
fi

echo "LANDED: $candidate -> $target (prospective tree verified before ref update)"
