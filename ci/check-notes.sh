#!/bin/sh
# check-notes.sh — the mechanical half of git-intent, for CI.
#
# Resolves branch-note assertions, checks anchor drift, and reports missing or
# stub notes. No model, no session: every check here is git plus grep.
#
#   ./check-notes.sh                 # every live note
#   ./check-notes.sh a.md b.md       # only these (use the PR's changed notes)
#
# Exit 1 ONLY on a violated assertion. Unresolvable anchors and stale anchors
# are advisory, per SPEC I15 — every legitimate refactor moves an anchor, and a
# check that fails the build on a rename gets deleted within a week.

set -u

FAILED=0
CHECKED=0

# Word-boundary matching. `git grep -w` is the portable spelling of \b.
resolve() {  # resolve <path>[:<symbol>] -> 0 if the anchor is still there
  _p=${1%%:*}
  _s=${1#*:}
  [ -e "$_p" ] || return 1
  [ "$_s" = "$1" ] && return 0
  git grep -qw -e "$_s" -- "$_p" 2>/dev/null
}

evaluate() {  # evaluate <check-expression> -> holds | violated | unresolvable
  _kind=$1
  shift
  case "$_kind" in
    exists)
      resolve "$1" && echo holds || echo unresolvable
      ;;
    contains)
      if resolve "$1"; then
        _p=${1%%:*}
        git grep -qw -e "$2" -- "$_p" 2>/dev/null && echo holds || echo violated
      else
        echo unresolvable
      fi
      ;;
    absent)
      _needle=$1
      shift
      if [ $# -gt 0 ]; then
        git grep -qw -e "$_needle" -- "$@" 2>/dev/null && echo violated || echo holds
      else
        git grep -qw -e "$_needle" 2>/dev/null && echo violated || echo holds
      fi
      ;;
    *)
      echo unresolvable
      ;;
  esac
}

if [ $# -gt 0 ]; then
  NOTES=$*
else
  NOTES=$(git ls-files '.branch-notes/*.md' | grep -v '/_archive/' || true)
fi

[ -z "$NOTES" ] && { echo "no live branch notes — nothing to check"; exit 0; }

for note in $NOTES; do
  [ -f "$note" ] || continue
  case "$note" in */_archive/*) continue ;; esac   # frozen; see SPEC 7.3

  echo "$note"

  # --- anchor drift (SPEC 3.4) ------------------------------------------
  anchor=$(sed -n 's/^captured_at: *//p' "$note" | head -1)
  if [ -z "$anchor" ]; then
    echo "  ! no captured_at — cannot be checked for drift"
  elif git rev-parse --verify -q "$anchor" >/dev/null 2>&1; then
    behind=$(git rev-list --count "$anchor"..HEAD 2>/dev/null || echo 0)
    [ "$behind" -gt 0 ] && echo "  ~ note is $behind commits behind HEAD (captured at $anchor)"
  else
    echo "  ~ captured_at $anchor does not resolve in this checkout"
  fi

  # --- stub check (SPEC 3.2) --------------------------------------------
  dated=$(grep -c '^- 20[0-9][0-9]-' "$note" || true)
  [ "$dated" -eq 0 ] && echo "  ~ stub: no dated entries under 'Why this shape'"

  # --- assertions (SPEC 7.1) --------------------------------------------
  # `id:` is optional — present only when an entry will be superseded. Entries
  # without one are labelled a1, a2… by position, so a bare `- check:` is still
  # checked. Skipping id-less entries would silently check nothing.
  parsed=$(awk '
    /^assert:/   { a = 1; n = 0; id = ""; next }
    /^---/       { a = 0 }
    /^[A-Za-z_]/ { a = 0 }
    a && /^ *- / { id = ""; n++ }
    a {
      line = $0
      sub(/^ *- */, "", line); sub(/^ */, "", line)
      if      (line ~ /^id:/)         { sub(/^id: */, "", line); id = line }
      else if (line ~ /^supersedes:/) { sub(/^supersedes: */, "", line); print "SUP\t" line }
      else if (line ~ /^check:/)      { sub(/^check: */, "", line); lab = (id != "" ? id : "a" n); print "CHK\t" lab "\t" line }
      else if (line ~ /^why:/)        { sub(/^why: */, "", line);   lab = (id != "" ? id : "a" n); print "WHY\t" lab "\t" line }
    }
  ' "$note")

  superseded=$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="SUP" {print $2}')
  whys=$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="WHY" {print $2"\t"$3}')

  printf '%s\n' "$parsed" | awk -F'\t' '$1=="CHK" {print $2"\t"$3}' | while IFS="$(printf '\t')" read -r id expr; do
    [ -z "$id" ] && continue
    # skip anything another entry supersedes — history, not a requirement
    if printf '%s\n' "$superseded" | grep -qx "$id"; then continue; fi

    # shellcheck disable=SC2086
    verdict=$(evaluate $expr)
    CHECKED=$((CHECKED + 1))
    why=$(printf '%s\n' "$whys" | awk -F'\t' -v k="$id" '$1==k {print $2; exit}')
    case "$verdict" in
      holds)        echo "  ok $id  $expr" ;;
      violated)     echo "  FAIL $id  $expr"
                    [ -n "$why" ] && echo "       why: $why"
                    echo "$id" >> "${TMPDIR:-/tmp}/gi-violations.$$" ;;
      unresolvable) echo "  ?? $id  $expr"
                    echo "       anchor no longer resolves — supersede this assertion if the move was intended" ;;
    esac
  done
done

if [ -s "${TMPDIR:-/tmp}/gi-violations.$$" ]; then
  FAILED=$(wc -l < "${TMPDIR:-/tmp}/gi-violations.$$" | tr -d ' ')
  rm -f "${TMPDIR:-/tmp}/gi-violations.$$"
  echo
  echo "$FAILED assertion(s) violated — a claim the author said had to survive did not."
  exit 1
fi

rm -f "${TMPDIR:-/tmp}/gi-violations.$$"
echo
echo "no violated assertions"
exit 0
