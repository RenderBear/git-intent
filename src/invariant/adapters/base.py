from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol


@dataclass(frozen=True)
class AdapterGate:
    stage: str
    message: str
    code: str
    lines: tuple[str, ...] = ()


class TaskAdapter(Protocol):
    """Optional task behavior surrounding the fixed core lifecycle."""

    id: str

    def begin(
        self,
        task_root: Path,
        goal_digest: str,
        source: str | None,
        state: dict[str, object] | None,
    ) -> tuple[dict[str, object] | None, AdapterGate | None]: ...

    def prepare_candidate(
        self,
        task_root: Path,
        goal_digest: str,
        candidate_tree: str,
        state: dict[str, object],
    ) -> dict[str, object]: ...

    def review_candidate(
        self,
        task_root: Path,
        goal_digest: str,
        candidate_tree: str,
        source: str | None,
        state: dict[str, object],
    ) -> AdapterGate | None: ...

    def context(self, task_root: Path, state: dict[str, object]) -> list[str]: ...

    def guidance(self, stage: str) -> str: ...
