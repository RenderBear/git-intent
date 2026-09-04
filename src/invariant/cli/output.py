from __future__ import annotations

import json
import re
import sys

from invariant.errors import InvariantError


def _records(lines: list[str]) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    for line in lines:
        match = re.match(r"^([A-Z][A-Z0-9-]*): (.*)$", line)
        if match:
            result.append({"name": match.group(1), "value": match.group(2)})
    return result


def emit_success(command: str, lines: list[str], format_name: str) -> int:
    if format_name == "json":
        print(
            json.dumps(
                {
                    "protocol": 1,
                    "command": command,
                    "status": "ok",
                    "result": {"records": _records(lines), "output": "\n".join(lines) + ("\n" if lines else "")},
                    "diagnostics": [],
                },
                separators=(",", ":"),
            )
        )
    elif lines:
        print("\n".join(lines))
    return 0


def emit_error(command: str, error: InvariantError, format_name: str) -> int:
    lines = list(error.lines)
    if format_name == "json":
        status = "blocked" if error.exit_code == 1 else "error"
        print(
            json.dumps(
                {
                    "protocol": 1,
                    "command": command,
                    "status": status,
                    "result": {"records": _records(lines), "output": "\n".join(lines) + ("\n" if lines else "")},
                    "diagnostics": [{"code": error.code, "message": error.message}],
                },
                separators=(",", ":"),
            )
        )
    else:
        if lines:
            print("\n".join(lines))
        print(error.message, file=sys.stderr)
    return error.exit_code

