from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import re
from typing import Any


def refs(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    if isinstance(value, str):
        stripped = value.strip().strip("[]")
        return [item.strip() for item in stripped.split(",") if item.strip()]
    return []


@dataclass(frozen=True)
class DiscoveryBasis:
    ground: str
    tree: str
    evidence: list[str] = field(default_factory=list)
    searched: list[str] = field(default_factory=list)
    prose: str = ""


@dataclass(frozen=True)
class DiscoveryDisposition:
    state: str
    prose: str = ""
    outputs: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class Discovery:
    identifier: str
    observation: str
    basis: DiscoveryBasis
    domains: list[str]
    paths: list[str]
    related: list[str]
    disposition: DiscoveryDisposition
    legacy_status: str | None = None

    @classmethod
    def parse(cls, raw: dict[str, Any]) -> "Discovery":
        basis_raw = raw.get("basis") if isinstance(raw.get("basis"), dict) else {}
        relevance = raw.get("relevance") if isinstance(raw.get("relevance"), dict) else {}
        disposition_raw = raw.get("disposition") if isinstance(raw.get("disposition"), dict) else {}
        legacy = raw.get("status") if isinstance(raw.get("status"), str) else None
        if legacy:
            state = "open" if legacy == "pending" else "resolved"
            outputs = refs(raw.get("resolution"))
            prose = str(raw.get("reason") or "")
        else:
            state = str(disposition_raw.get("state") or "open")
            outputs = refs(disposition_raw.get("outputs"))
            prose = str(disposition_raw.get("prose") or "")
        return cls(
            identifier=str(raw.get("id") or ""),
            observation=str(raw.get("observation") or raw.get("statement") or ""),
            basis=DiscoveryBasis(
                ground=str(basis_raw.get("ground") or raw.get("ground") or ""),
                tree=str(basis_raw.get("tree") or raw.get("tree") or ""),
                evidence=refs(basis_raw.get("evidence")) + refs(raw.get("evidence")),
                searched=refs(basis_raw.get("searched")),
                prose=str(basis_raw.get("prose") or ""),
            ),
            domains=refs(relevance.get("domains")) + refs(raw.get("domains")),
            paths=refs(relevance.get("paths")) + refs(raw.get("paths")),
            related=refs(relevance.get("related")),
            disposition=DiscoveryDisposition(state, prose, outputs),
            legacy_status=legacy,
        )


def allowed_top_fields(raw: dict[str, Any]) -> set[str]:
    if "basis" in raw or "observation" in raw or isinstance(raw.get("disposition"), dict):
        return {"version", "id", "observation", "basis", "relevance", "disposition"}
    return {
        "version",
        "id",
        "status",
        "ground",
        "tree",
        "domains",
        "statement",
        "evidence",
        "candidates",
        "resolution",
        "reason",
    }


def validate_shape(path: Path, raw: dict[str, Any]) -> list[str]:
    label = path.as_posix()
    result: list[str] = []
    discovery = Discovery.parse(raw)
    unknown = sorted(set(raw) - allowed_top_fields(raw))
    for field_name in unknown:
        result.append(f"{label}:{discovery.identifier or 'discovery'} unknown field {field_name}")
    if raw.get("version") != 1:
        result.append(f"{label} must declare version: 1")
    if not discovery.identifier:
        result.append(f"{label} missing discovery id")
    elif not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", discovery.identifier):
        result.append(f"{label} invalid discovery id '{discovery.identifier}'")
    elif path.stem != discovery.identifier:
        result.append(f"{label} filename must be {discovery.identifier}.yml")
    if not discovery.observation.strip():
        result.append(f"{label}:{discovery.identifier} missing observation")
    if not discovery.basis.ground:
        result.append(f"{label}:{discovery.identifier} missing basis ground")
    if not discovery.basis.tree:
        result.append(f"{label}:{discovery.identifier} missing basis tree")
    if not discovery.basis.evidence and not discovery.basis.searched:
        result.append(f"{label}:{discovery.identifier} requires evidence or an explicit searched scope")
    if discovery.disposition.state not in {"open", "resolved"}:
        result.append(
            f"{label}:{discovery.identifier} invalid disposition state '{discovery.disposition.state}'"
        )
    if discovery.disposition.state == "open" and discovery.disposition.outputs:
        result.append(f"{label}:{discovery.identifier} open discovery cannot have outputs")
    if discovery.disposition.state == "resolved" and not (
        discovery.disposition.prose.strip() or discovery.disposition.outputs
    ):
        result.append(f"{label}:{discovery.identifier} resolved discovery requires prose or outputs")

    if not discovery.legacy_status:
        nested = (
            ("basis", {"ground", "tree", "evidence", "searched", "prose"}, True),
            ("relevance", {"domains", "paths", "related"}, False),
            ("disposition", {"state", "prose", "outputs"}, True),
        )
        for field_name, allowed, required in nested:
            value = raw.get(field_name)
            if value is None and required:
                result.append(f"{label}:{discovery.identifier} missing {field_name} mapping")
                continue
            if value is not None and not isinstance(value, dict):
                result.append(f"{label}:{discovery.identifier} {field_name} must be a mapping")
                continue
            if isinstance(value, dict):
                for unknown_field in sorted(set(value) - allowed):
                    result.append(
                        f"{label}:{discovery.identifier} unknown {field_name} field {unknown_field}"
                    )

    if discovery.legacy_status:
        status = discovery.legacy_status
        if status not in {"pending", "promoted", "dismissed", "superseded", "stale"}:
            result.append(f"{label}:{discovery.identifier} invalid status '{status}'")
        candidates = refs(raw.get("candidates"))
        if status == "pending" and not candidates:
            result.append(f"{label}:{discovery.identifier} pending discovery requires at least one candidate")
        for candidate in candidates:
            if candidate not in {"domain", "architecture", "contract"}:
                result.append(f"{label}:{discovery.identifier} invalid candidate '{candidate}'")
        if status == "promoted" and not refs(raw.get("resolution")):
            result.append(f"{label}:{discovery.identifier} promoted discovery requires a resolution")
        if status in {"dismissed", "stale"} and not raw.get("reason"):
            result.append(f"{label}:{discovery.identifier} {status} discovery requires a reason")
        if status == "superseded" and not any(
            item.startswith("discovery:") for item in refs(raw.get("resolution"))
        ):
            result.append(
                f"{label}:{discovery.identifier} superseded discovery must resolve to discovery:<id>"
            )
    return result
