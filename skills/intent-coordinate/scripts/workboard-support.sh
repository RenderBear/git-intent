#!/bin/sh
# Validate the semantic-free mechanics of an ephemeral coordination board:
# references, dependency order, cycles, and unordered claim overlap.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

[ "$#" -eq 2 ] && [ "$1" = validate ] || {
  echo "usage: workboard-support.sh validate <board-id-or-file>" >&2
  exit 2
}

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git-intent: not inside a Git repository" >&2
  exit 2
}
runtime=$(sh "$script_dir/runtime-support.sh" root)

case "$2" in
  */*) board=$2 ;;
  *) board="$runtime/boards/$2.yml" ;;
esac
[ -f "$board" ] || { echo "git-intent: no workboard '$2'" >&2; exit 2; }

target=$(sed -n 's/^integration_target:[[:space:]]*//p' "$board" | head -1)
[ -n "$target" ] || { echo "WORKBOARD: invalid — missing integration_target"; exit 1; }
git show-ref --verify -q "refs/heads/$target" || {
  echo "WORKBOARD: invalid — integration target '$target' does not exist locally"
  exit 1
}

result=$(awk '
  function list(line, out,    n,a,i) {
    sub(/^[^:]*: */, "", line); gsub(/[][,]/, " ", line)
    n=split(line,a,/[[:space:]]+/); out=""
    for(i=1;i<=n;i++) if(a[i]!="") out=out (out==""?"":" ") a[i]
    return out
  }
  function related(a,b) { return a==b || index(a,b "/")==1 || index(b,a "/")==1 }
  function fail(msg) { print "WORKBOARD: invalid — " msg; bad=1 }
  function flush(    i,a,n) {
    if(id=="") return
    if(id in seen) fail("duplicate unit " id)
    seen[id]=1; uid[++nu]=id; deps[id]=d; claims[id]=s
    id=d=s=""
  }
  /^  - id:/ {
    flush(); id=$0; sub(/^[^:]*: */,"",id); sub(/[[:space:]]+#.*$/, "", id); next
  }
  id!="" && /^    dependencies:/ { d=list($0); next }
  id!="" && /^    surfaces:/ { s=list($0); next }
  END {
    flush()
    if(nu<2) fail("coordination requires at least two units")
    for(i=1;i<=nu;i++) {
      u=uid[i]
      if(claims[u]=="") fail("unit " u " has no surfaces claim")
      n=split(deps[u],a," ")
      for(j=1;j<=n;j++) if(a[j]!="") {
        if(a[j]==u) fail("unit " u " depends on itself")
        else if(!(a[j] in seen)) fail("unit " u " depends on missing unit " a[j])
        else reach[u SUBSEP a[j]]=1
      }
    }
    changed=1
    while(changed) {
      changed=0
      for(i=1;i<=nu;i++) for(j=1;j<=nu;j++) for(k=1;k<=nu;k++)
        if(reach[uid[i] SUBSEP uid[j]] && reach[uid[j] SUBSEP uid[k]] && !reach[uid[i] SUBSEP uid[k]]) {
          reach[uid[i] SUBSEP uid[k]]=1; changed=1
        }
    }
    for(i=1;i<=nu;i++) if(reach[uid[i] SUBSEP uid[i]]) fail("dependency cycle includes " uid[i])
    for(i=1;i<=nu;i++) for(j=i+1;j<=nu;j++) {
      ua=uid[i]; ub=uid[j]
      if(reach[ua SUBSEP ub] || reach[ub SUBSEP ua]) continue
      na=split(claims[ua],ca," "); nb=split(claims[ub],cb," "); overlap=""
      for(x=1;x<=na;x++) for(y=1;y<=nb;y++) if(related(ca[x],cb[y])) overlap=ca[x]
      if(overlap!="") fail("unordered units " ua " and " ub " overlap at " overlap)
    }
    if(!bad) print "WORKBOARD: valid — " nu " units, integration target checked, dependencies acyclic, unordered claims disjoint"
    exit bad
  }
' "$board") || {
  printf '%s\n' "$result"
  exit 1
}
printf '%s\n' "$result"
