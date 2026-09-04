#!/bin/sh
# Deprecated source-tree adapter. Coordination mechanics live in the invariant package.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
python=${INVARIANT_PYTHON:-$root/.venv/bin/python}
[ -x "$python" ] || python=${PYTHON:-python3}
PYTHONPATH="$root/src${PYTHONPATH:+:$PYTHONPATH}" exec "$python" -m invariant.compat workboard-status "$@"
