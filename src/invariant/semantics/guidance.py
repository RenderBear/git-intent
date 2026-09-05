from __future__ import annotations

from importlib.resources import files


def read(name: str) -> str:
    resource = files("invariant.semantics").joinpath("guidance", f"{name}.md")
    return resource.read_text(encoding="utf-8").strip()


def agent_workflow() -> str:
    return "\n\n".join((read("workflow"), read("human-ergonomics"), read("protocol-reference")))


def for_stage(stage: str, *, intent_expansion: bool, outcome_review: bool) -> str:
    if stage == "awaiting-intent-expansion":
        names = ["intent-expansion", "semantic-reasoning", "repository-archaeology", "human-ergonomics"]
    elif stage == "awaiting-outcome-review":
        names = ["semantic-reasoning", "repository-archaeology", "outcome-review", "human-ergonomics"]
    elif stage == "awaiting-landing":
        names = ["semantic-reasoning", "repository-archaeology", "land", "human-ergonomics"]
    elif stage in {"implementing", "implementing-unborn"}:
        names = [
            "brief",
            "semantic-reasoning",
            "repository-archaeology",
            "discovery",
            "coordinate",
            "land",
            "human-ergonomics",
        ]
        if outcome_review:
            names.append("outcome-review")
    else:
        names = ["brief", "semantic-reasoning", "repository-archaeology", "human-ergonomics"]
        if intent_expansion:
            names.insert(0, "intent-expansion")
    names.append("protocol-reference")
    return "\n\n".join(read(name) for name in names)
