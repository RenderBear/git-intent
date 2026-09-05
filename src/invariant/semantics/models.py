from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import re
from typing import Any

import yaml

from invariant.errors import UsageError


def _load_yaml(path: str | Path) -> Any:
    source = Path(path)
    try:
        return yaml.safe_load(source.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise UsageError(f"Invariant: no such file '{source}'") from None
    except yaml.YAMLError as exc:
        raise UsageError(f"Invariant: invalid YAML in {source}: {exc}") from exc


def string_list(value: Any, field_name: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise UsageError(f"{field_name} must be a list of non-empty strings")
    return sorted(set(value))


def _valid_id(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value))


@dataclass(frozen=True)
class Boundary:
    disposition: str

    @classmethod
    def from_value(cls, value: Any) -> "Boundary":
        if not isinstance(value, dict):
            raise UsageError("assessment boundary must be a mapping")
        unknown = sorted(set(value) - {"disposition"})
        if unknown:
            raise UsageError(f"assessment boundary has unknown field '{unknown[0]}'")
        disposition = value.get("disposition")
        if not isinstance(disposition, str):
            raise UsageError("assessment boundary requires a disposition")
        if disposition not in {"no-record", "recorded"} and not (
            disposition.startswith("audit:") and _valid_id(disposition.removeprefix("audit:"))
        ):
            raise UsageError("assessment has an invalid boundary disposition")
        return cls(disposition)


@dataclass(frozen=True)
class OutcomeAssessment:
    reference: str
    disposition: str
    prose: str
    evidence: list[str] = field(default_factory=list)

    @classmethod
    def from_value(cls, value: Any, index: int) -> "OutcomeAssessment":
        if not isinstance(value, dict):
            raise UsageError(f"outcome_assessment[{index}] must be a mapping")
        unknown = sorted(set(value) - {"satisfies", "disposition", "prose", "evidence"})
        if unknown:
            raise UsageError(
                f"outcome_assessment[{index}] has unknown field '{unknown[0]}'"
            )
        reference = value.get("satisfies")
        disposition = value.get("disposition")
        prose = value.get("prose")
        if not all(isinstance(item, str) and item.strip() for item in (reference, disposition, prose)):
            raise UsageError(
                f"outcome_assessment[{index}] requires satisfies, disposition, and prose"
            )
        if disposition not in {"satisfied", "not-satisfied", "unresolved"}:
            raise UsageError(
                f"outcome_assessment[{index}] disposition must be satisfied, not-satisfied, or unresolved"
            )
        return cls(reference, disposition, prose, string_list(value.get("evidence"), "outcome evidence"))


@dataclass(frozen=True)
class Assessment:
    version: int
    goal_digest: str
    paths: list[str]
    interfaces: list[str]
    domains: list[str]
    boundary: Boundary
    governance: list[str]
    architecture_reviews: list[str]
    checks: list[str]
    allow_open: bool = False
    outcomes: list[OutcomeAssessment] = field(default_factory=list)
    prose: str = ""
    candidate_tree: str | None = None

    @classmethod
    def load(cls, path: str | Path) -> "Assessment":
        raw = _load_yaml(path)
        if not isinstance(raw, dict):
            raise UsageError("assessment must be a YAML mapping")
        allowed = {
            "version",
            "goal_digest",
            "paths",
            "interfaces",
            "domains",
            "boundary",
            "governance",
            "architecture_reviews",
            "checks",
            "allow_open",
            "outcome_assessment",
            "prose",
            "candidate_tree",
        }
        unknown = sorted(set(raw) - allowed)
        if unknown:
            raise UsageError(f"assessment has unknown field '{unknown[0]}'")
        if raw.get("version") != 1:
            raise UsageError("assessment must declare version: 1")
        required = {
            "goal_digest",
            "paths",
            "interfaces",
            "domains",
            "boundary",
            "governance",
            "architecture_reviews",
            "checks",
        }
        missing = sorted(required - set(raw))
        if missing:
            raise UsageError(f"assessment is missing required field '{missing[0]}'")
        goal_digest = raw.get("goal_digest")
        if not isinstance(goal_digest, str) or not goal_digest:
            raise UsageError("assessment requires goal_digest")
        outcomes_raw = raw.get("outcome_assessment", [])
        if not isinstance(outcomes_raw, list):
            raise UsageError("outcome_assessment must be a list")
        outcomes = [OutcomeAssessment.from_value(item, index) for index, item in enumerate(outcomes_raw)]
        references = [item.reference for item in outcomes]
        if len(references) != len(set(references)):
            raise UsageError("outcome_assessment cannot contain duplicate satisfies references")
        prose = raw.get("prose", "")
        if not isinstance(prose, str):
            raise UsageError("assessment prose must be text")
        candidate_tree = raw.get("candidate_tree")
        if candidate_tree is not None and (not isinstance(candidate_tree, str) or not candidate_tree):
            raise UsageError("assessment candidate_tree must be a non-empty Git tree id")
        allow_open = raw.get("allow_open", False)
        if not isinstance(allow_open, bool):
            raise UsageError("assessment allow_open must be true or false")
        return cls(
            version=1,
            goal_digest=goal_digest,
            paths=string_list(raw.get("paths"), "assessment paths"),
            interfaces=string_list(raw.get("interfaces"), "assessment interfaces"),
            domains=string_list(raw.get("domains"), "assessment domains"),
            boundary=Boundary.from_value(raw.get("boundary")),
            governance=string_list(raw.get("governance"), "assessment governance"),
            architecture_reviews=string_list(
                raw.get("architecture_reviews"), "assessment architecture_reviews"
            ),
            checks=string_list(raw.get("checks"), "assessment checks"),
            allow_open=allow_open,
            outcomes=outcomes,
            prose=prose,
            candidate_tree=candidate_tree,
        )


@dataclass(frozen=True)
class TaskIntent:
    goal: str
    outcomes: list[str] = field(default_factory=list)
    acceptance: list[str] = field(default_factory=list)
    constraints: list[str] = field(default_factory=list)

    @classmethod
    def load(cls, path: str | Path) -> "TaskIntent":
        raw = _load_yaml(path)
        if not isinstance(raw, dict) or raw.get("version") != 1:
            raise UsageError("intent expansion must be a version-1 YAML mapping")
        intent = raw.get("intent", raw)
        if not isinstance(intent, dict):
            raise UsageError("intent expansion requires an intent mapping")
        goal = intent.get("goal")
        if not isinstance(goal, str) or not goal.strip():
            raise UsageError("intent expansion requires goal prose")

        def refs(section: str) -> list[str]:
            values = intent.get(section, [])
            if not isinstance(values, list):
                raise UsageError(f"intent {section} must be a list")
            result: list[str] = []
            for index, item in enumerate(values):
                if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                    raise UsageError(f"intent {section}[{index}] requires an id")
                if not _valid_id(item["id"]):
                    raise UsageError(f"intent {section}[{index}] has an invalid id")
                prose = item.get("prose", item.get("statement"))
                if not isinstance(prose, str) or not prose.strip():
                    raise UsageError(f"intent {section}[{index}] requires prose")
                result.append(item["id"])
            return result

        outcomes, acceptance, constraints = refs("outcomes"), refs("acceptance"), refs("constraints")
        identifiers = [*outcomes, *acceptance, *constraints]
        if len(identifiers) != len(set(identifiers)):
            raise UsageError("intent outcome, acceptance, and constraint ids must be unique")
        return cls(goal, outcomes, acceptance, constraints)
