# Audit orientation — entering an unfamiliar repository

Run compact, derived checks into context. Report provenance for each assertion. Do not write a cache,
open the full decision set, or treat repository structure as semantic authority.

```bash
# structure
git ls-files | awk -F/ 'NF>1{print $1"/"$2}' | sort | uniq -c | sort -rn | head -30

# recent churn
git log --format='' --name-only --since='3 months ago' |
  awk -F/ 'NF>1{print $1"/"$2}' | sort | uniq -c | sort -rn | head -15

# ownership evidence; CODEOWNERS outranks log-derived ownership
git ls-files | grep -E '(^|/)(CODEOWNERS|ARCHITECTURE\.md)$|docs/adr/' | head -40

# commands from repository configuration, never guessed
git ls-files | grep -E '(^|/)(Makefile|justfile|Taskfile\.yml|package\.json)$|^\.github/workflows/'

# intent shape; inspect counts only, then compile after the unit is known
git ls-files '.intent/' | awk -F/ '{print $1"/"$2}' | sort | uniq -c
```

Once the request is split into a narrow unit, run `intent-brief` with its goal, scope, optional
paths, and interfaces. That compiled brief is the only normal intent read. Read at most the exact
unit exception file during landing. Open an ADR, architecture section, scope-partitioned history
id, or proposal only after the brief identifies a concrete match or contradiction.
