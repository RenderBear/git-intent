#!/bin/sh
# Verify read-only authority and integration-target resolution.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
resolver="$root/skills/intent-brief/scripts/resolve-config.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/invariant-config-test.XXXXXX")
cleanup() { rm -rf "$fixture"; }
trap cleanup EXIT HUP INT TERM

git -C "$fixture" init -qb trunk
git -C "$fixture" config user.name test
git -C "$fixture" config user.email test@example.com
echo x >"$fixture/f"
git -C "$fixture" add f
git -C "$fixture" commit -qm seed

default=$(cd "$fixture" && sh "$resolver")
[ "$default" = "resolution: assisted
execution: auto
integration_branch: trunk
source: default
integration_branch_resolved: trunk
branch_source: current" ]
[ ! -e "$fixture/.invariant" ]

unborn="$fixture/unborn"
git init -qb fresh "$unborn"
unborn_out=$(cd "$unborn" && sh "$resolver")
printf '%s\n' "$unborn_out" | grep -q '^integration_branch: fresh$'
printf '%s\n' "$unborn_out" | grep -q '^integration_branch_unborn: true$'

mkdir -p "$fixture/.invariant"
cat >"$fixture/.invariant/config.yml" <<EOF
version: 1
resolution: auto
execution: assisted
integration_branch: trunk
push_remote: off
EOF

explicit=$(cd "$fixture" && sh "$resolver")
[ "$explicit" = "resolution: auto
execution: assisted
integration_branch: trunk
source: .invariant/config.yml
integration_branch_resolved: trunk
branch_source: config" ]

cat >"$fixture/.invariant/config.yml" <<EOF
version: 1
EOF
omitted=$(cd "$fixture" && sh "$resolver")
[ "$omitted" = "resolution: assisted
execution: auto
integration_branch: trunk
source: .invariant/config.yml
integration_branch_resolved: trunk
branch_source: current" ]

cat >"$fixture/.invariant/config.yml" <<EOF
version: 1
resolution: deferred
EOF
if (cd "$fixture" && sh "$resolver" >/dev/null 2>&1); then
  echo "not ok - invalid resolution value was accepted"
  exit 1
fi

cat >"$fixture/.invariant/config.yml" <<EOF
version: 1
execution: deferred
EOF
if (cd "$fixture" && sh "$resolver" >/dev/null 2>&1); then
  echo "not ok - invalid execution value was accepted"
  exit 1
fi

cat >"$fixture/.invariant/config.yml" <<EOF
version: 1
push_remote: maybe
EOF
if (cd "$fixture" && sh "$resolver" >/dev/null 2>&1); then
  echo "not ok - invalid push_remote value was accepted"
  exit 1
fi

cat >"$fixture/.invariant/config.yml" <<EOF
version: 1
workers: subagent
EOF
if (cd "$fixture" && sh "$resolver" >/dev/null 2>&1); then
  echo "not ok - removed workers field was accepted"
  exit 1
fi

cat >"$fixture/.invariant/config.yml" <<EOF
version: 1
integration_branch: missing
EOF
if (cd "$fixture" && sh "$resolver" >/dev/null 2>&1); then
  echo "not ok - missing configured branch silently fell back"
  exit 1
fi

rm -f "$fixture/.invariant/config.yml"
git -C "$fixture" checkout -q --detach
if (cd "$fixture" && sh "$resolver" >/dev/null 2>&1); then
  echo "not ok - detached HEAD without an explicit target was accepted"
  exit 1
fi

captured=$(cd "$fixture" && GIT_INTENT_INTEGRATION_TARGET=trunk sh "$resolver")
printf '%s\n' "$captured" | grep -q '^integration_branch: trunk$'
printf '%s\n' "$captured" | grep -q '^branch_source: captured$'

echo "11 config resolution checks passed"
