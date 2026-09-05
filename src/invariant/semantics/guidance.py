from __future__ import annotations

from importlib.resources import files


def read(name: str) -> str:
    resource = files("invariant.semantics").joinpath("guidance", f"{name}.md")
    return resource.read_text(encoding="utf-8").strip()


def for_stage(stage: str, *, intent_expansion: bool, outcome_review: bool) -> str:
    if stage == "awaiting-intent-expansion":
        names = ["intent-expansion", "semantic-reasoning", "repository-archaeology"]
    elif stage == "awaiting-outcome-review":
        names = ["semantic-reasoning", "repository-archaeology", "outcome-review"]
    elif stage == "awaiting-landing":
        names = ["semantic-reasoning", "repository-archaeology", "land"]
    elif stage in {"implementing", "implementing-unborn"}:
        names = [
            "brief",
            "semantic-reasoning",
            "repository-archaeology",
            "discovery",
            "coordinate",
            "land",
        ]
        if outcome_review:
            names.append("outcome-review")
    else:
        names = ["brief", "semantic-reasoning", "repository-archaeology"]
        if intent_expansion:
            names.insert(0, "intent-expansion")
    return "\n\n".join(read(name) for name in names)
