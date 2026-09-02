#!/bin/sh
# Validate the semantic-free mechanics of a runtime plan: references,
# dependency order, verification declarations, reliance order, and unordered
# claim overlap. The model chooses the units; this script validates the graph.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
brief_script="$script_dir/../../intent-brief/scripts/brief-support.sh"

[ "$#" -eq 2 ] && [ "$1" = validate ] || {
  echo "usage: workboard-support.sh validate <plan-id-or-file>" >&2
  exit 2
}

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "git-intent: not inside a Git repository" >&2
  exit 2
}
runtime=$(sh "$script_dir/runtime-support.sh" root)

case "$2" in
  */*) plan=$2 ;;
  *) plan="$runtime/plans/$2.yml" ;;
esac
[ -f "$plan" ] || { echo "git-intent: no plan '$2'" >&2; exit 2; }

version=$(sed -n 's/^version:[[:space:]]*//p' "$plan" | head -1)
plan_id=$(sed -n 's/^id:[[:space:]]*//p' "$plan" | head -1)
goal=$(sed -n 's/^goal:[[:space:]]*//p' "$plan" | head -1)
target=$(sed -n 's/^integration_target:[[:space:]]*//p' "$plan" | head -1)
ground=$(sed -n 's/^integration_ground:[[:space:]]*//p' "$plan" | head -1)
digest=$(sed -n 's/^governing_digest:[[:space:]]*//p' "$plan" | head -1)
domains_raw=$(sed -n 's/^domains:[[:space:]]*//p' "$plan" | head -1)
[ "$version" = 1 ] || { echo "PLAN: invalid — version must be 1"; exit 1; }
case "$plan_id" in ''|.*|*..*|*.|*[!a-zA-Z0-9._-]*) echo "PLAN: invalid — malformed id '$plan_id'"; exit 1 ;; esac
file_id=$(basename "$plan" .yml)
[ "$file_id" = "$plan_id" ] || { echo "PLAN: invalid — filename must be $plan_id.yml"; exit 1; }
[ -n "$goal" ] || { echo "PLAN: invalid — missing goal"; exit 1; }
[ -n "$target" ] || { echo "PLAN: invalid — missing integration_target"; exit 1; }
[ -n "$ground" ] || { echo "PLAN: invalid — missing integration_ground"; exit 1; }
[ -n "$digest" ] || { echo "PLAN: invalid — missing governing_digest"; exit 1; }
case "$domains_raw" in \[*\]) ;; *) echo "PLAN: invalid — domains must be an inline list"; exit 1 ;; esac
git show-ref --verify -q "refs/heads/$target" || {
  echo "PLAN: invalid — integration target '$target' does not exist locally"
  exit 1
}
git rev-parse -q --verify "$ground^{commit}" >/dev/null 2>&1 || {
  echo "PLAN: invalid — integration ground '$ground' is not a commit"
  exit 1
}
git merge-base --is-ancestor "$ground" "refs/heads/$target" || {
  echo "PLAN: invalid — integration ground is not an ancestor of '$target'"
  exit 1
}
domain_list=$(printf '%s' "$domains_raw" | tr '[],' '   ')
for domain in $domain_list; do
  case "$domain" in *[!a-zA-Z0-9._-]*|'' ) echo "PLAN: invalid — malformed semantic domain '$domain'"; exit 1 ;; esac
done
# Domain selection is semantic, but once selected its governing digest is an
# exact mechanical freshness check for the lifetime of this plan.
# shellcheck disable=SC2086
if ! digest_row=$(sh "$brief_script" digest $domain_list 2>&1); then
  printf 'PLAN: invalid — %s\n' "$digest_row"
  exit 1
fi
actual_digest=$(printf '%s\n' "$digest_row" | sed -n 's/^DIGEST:[[:space:]]*//p')
[ "$digest" = "$actual_digest" ] || {
  echo "PLAN: invalid — governing digest is stale (expected $digest, current $actual_digest)"
  exit 1
}

result=$(awk '
  function value(line) {
    sub(/^[^:]*: */, "", line); sub(/[[:space:]]+#.*$/, "", line)
    return line
  }
  function list(line,    n,a,i,out) {
    line=value(line); gsub(/[][,]/, " ", line)
    n=split(line,a,/[[:space:]]+/); out=""
    for(i=1;i<=n;i++) if(a[i]!="") out=out (out==""?"":" ") a[i]
    return out
  }
  function words_has(words,w,    n,a,i) {
    n=split(words,a," "); for(i=1;i<=n;i++) if(a[i]==w) return 1
    return 0
  }
  function words_share(a,b,    n,x,i) {
    n=split(a,x," "); for(i=1;i<=n;i++) if(x[i]!="" && words_has(b,x[i])) return x[i]
    return ""
  }
  function path_related(a,b) { return a==b || index(a,b "/")==1 || index(b,a "/")==1 }
  function paths_share(a,b,    na,nb,aa,bb,i,j) {
    na=split(a,aa," "); nb=split(b,bb," ")
    for(i=1;i<=na;i++) for(j=1;j<=nb;j++)
      if(aa[i]!="" && bb[j]!="" && path_related(aa[i],bb[j])) return aa[i]
    return ""
  }
  function fail(msg) { print "PLAN: invalid — " msg; bad=1 }
  function flush() {
    if(id=="") return
    if(id !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) fail("malformed unit id " id)
    if(id in seen) fail("duplicate unit " id)
    seen[id]=1; uid[++nu]=id
    objective[id]=obj; deps[id]=dep; paths[id]=pth; interfaces[id]=ifc
    governance[id]=gov; provides[id]=pro; relies[id]=rel; verifies[id]=ver
    id=obj=dep=pth=ifc=gov=pro=rel=ver=""
  }
  /^  - id:/ { flush(); id=value($0); next }
  id!="" && /^    objective:/ { obj=value($0); next }
  id!="" && /^    dependencies:/ { dep=list($0); next }
  id!="" && /^    paths:/ { pth=list($0); next }
  id!="" && /^    interfaces:/ { ifc=list($0); next }
  id!="" && /^    governance:/ { gov=list($0); next }
  id!="" && /^    provides:/ { pro=list($0); next }
  id!="" && /^    relies_on:/ { rel=list($0); next }
  id!="" && /^    verifies:/ { ver=list($0); next }
  END {
    flush()
    if(nu<2) fail("coordination requires at least two units")
    for(i=1;i<=nu;i++) {
      u=uid[i]
      if(objective[u]=="") fail("unit " u " has no objective")
      if(paths[u]=="" && interfaces[u]=="" && governance[u]=="")
        fail("unit " u " has no path, interface, or governance claim")
      if(verifies[u]=="") fail("unit " u " has no verification")
      n=split(paths[u],a," ")
      for(j=1;j<=n;j++) if(a[j] ~ /^\// || a[j] ~ /^\.\.\// || a[j] ~ /\/\.\.\// || a[j] ~ /\/\.\.$/)
        fail("unit " u " has unsafe path claim " a[j])
      n=split(verifies[u],a," ")
      for(j=1;j<=n;j++) if(a[j]!="" && a[j] !~ /^(command|test|schema):/)
        fail("unit " u " has unsupported verifier " a[j])
      n=split(deps[u],a," ")
      for(j=1;j<=n;j++) if(a[j]!="") {
        if(a[j]==u) fail("unit " u " depends on itself")
        else if(!(a[j] in seen)) fail("unit " u " depends on missing unit " a[j])
        else reach[u SUBSEP a[j]]=1
      }
      n=split(provides[u],a," ")
      for(j=1;j<=n;j++) if(a[j]!="" && !words_has(governance[u],a[j]))
        fail("unit " u " provides " a[j] " without claiming it as governance")
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

    for(i=1;i<=nu;i++) {
      consumer=uid[i]; nr=split(relies[consumer],rr," ")
      for(r=1;r<=nr;r++) if(rr[r]!="") {
        provider=""
        for(j=1;j<=nu;j++) if(words_has(provides[uid[j]],rr[r])) {
          if(provider!="" && provider!=uid[j]) fail("multiple units provide " rr[r])
          provider=uid[j]
        }
        if(provider!="" && provider!=consumer && !reach[consumer SUBSEP provider])
          fail("unit " consumer " relies on " rr[r] " but does not depend on provider " provider)
      }
    }

    for(i=1;i<=nu;i++) for(j=i+1;j<=nu;j++) {
      ua=uid[i]; ub=uid[j]
      if(reach[ua SUBSEP ub] || reach[ub SUBSEP ua]) continue
      overlap=paths_share(paths[ua],paths[ub])
      if(overlap!="") { fail("unordered units " ua " and " ub " overlap at path " overlap); continue }
      overlap=words_share(interfaces[ua],interfaces[ub])
      if(overlap!="") { fail("unordered units " ua " and " ub " overlap at interface " overlap); continue }
      overlap=words_share(governance[ua],governance[ub])
      if(overlap!="") fail("unordered units " ua " and " ub " overlap at governance " overlap)
    }
    if(!bad) print "PLAN: valid — " nu " units, target and ground checked, dependencies acyclic, reliance ordered, unordered claims disjoint"
    exit bad
  }
' "$plan") || {
  printf '%s\n' "$result"
  exit 1
}
printf '%s\n' "$result"
