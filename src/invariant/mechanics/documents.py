from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Any

import yaml

from invariant.errors import InvariantError


class LiteralDumper(yaml.SafeDumper):
    pass


def _represent_string(dumper: yaml.SafeDumper, value: str) -> yaml.Node:
    style = "|" if "\n" in value else None
    return dumper.represent_scalar("tag:yaml.org,2002:str", value, style=style)


LiteralDumper.add_representer(str, _represent_string)


def load_yaml(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return yaml.safe_load(handle)
    except FileNotFoundError:
        raise InvariantError(f"Invariant: no such file '{path}'", code="missing_file") from None
    except yaml.YAMLError as exc:
        raise InvariantError(f"Invariant: invalid YAML in {path}: {exc}", code="invalid_yaml") from exc


def dump_yaml(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, pending_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    pending = Path(pending_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            yaml.dump(
                value,
                handle,
                Dumper=LiteralDumper,
                sort_keys=False,
                allow_unicode=True,
                width=100,
            )
        pending.replace(path)
    finally:
        if pending.exists():
            pending.unlink()

