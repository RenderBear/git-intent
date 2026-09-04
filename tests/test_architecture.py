from __future__ import annotations

import ast
from pathlib import Path

import yaml

from invariant.semantics import guidance
from invariant.semantics.discovery import Discovery, validate_shape
from invariant.semantics.models import Assessment, TaskIntent


PACKAGE = Path(__file__).parents[1] / "src" / "invariant"


def imported_modules(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    modules: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            modules.add(node.module)
    return modules


def test_semantics_does_not_depend_on_mechanics_or_lifecycle() -> None:
    for path in (PACKAGE / "semantics").glob("*.py"):
        imports = imported_modules(path)
        assert not any(name.startswith("invariant.mechanics") for name in imports), path
        assert not any(name.startswith("invariant.lifecycle") for name in imports), path


def test_mechanics_does_not_depend_on_lifecycle_or_skill_source() -> None:
    for path in (PACKAGE / "mechanics").glob("*.py"):
        imports = imported_modules(path)
        assert not any(name.startswith("invariant.lifecycle") for name in imports), path
        assert "skills/intent-" not in path.read_text(encoding="utf-8")


def test_task_intent_keeps_prose_input_and_stable_ids(tmp_path: Path) -> None:
    path = tmp_path / "intent.yml"
    path.write_text(
        yaml.safe_dump(
            {
                "version": 1,
                "intent": {
                    "goal": "Restore active jobs after reopening.",
                    "outcomes": [{"id": "O1", "prose": "Active jobs remain visible."}],
                    "acceptance": [{"id": "A1", "prose": "Each job appears once."}],
                    "constraints": [{"id": "C1", "prose": "Chat remains session scoped."}],
                },
            }
        ),
        encoding="utf-8",
    )
    intent = TaskIntent.load(path)
    assert intent.goal == "Restore active jobs after reopening."
    assert intent.outcomes == ["O1"]
    assert intent.acceptance == ["A1"]
    assert intent.constraints == ["C1"]
    assert "Active jobs remain visible." in path.read_text(encoding="utf-8")


def test_outcome_assessment_is_exact_tree_semantic_input(tmp_path: Path) -> None:
    path = tmp_path / "assessment.yml"
    path.write_text(
        yaml.safe_dump(
            {
                "version": 1,
                "goal_digest": "abc",
                "paths": ["src/jobs.py"],
                "interfaces": [],
                "domains": [],
                "boundary": {"disposition": "no-record"},
                "governance": [],
                "architecture_reviews": [],
                "checks": [],
                "candidate_tree": "tree-id",
                "outcome_assessment": [
                    {
                        "satisfies": "A1",
                        "disposition": "satisfied",
                        "prose": "The candidate restores each job once.",
                        "evidence": ["test:tests/test_jobs.py"],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    assessment = Assessment.load(path)
    assert assessment.candidate_tree == "tree-id"
    assert assessment.outcomes[0].reference == "A1"
    assert assessment.outcomes[0].disposition == "satisfied"


def test_discovery_can_resolve_without_a_contract() -> None:
    raw = {
        "version": 1,
        "id": "missing-adr",
        "observation": "The recovery decision is undocumented.",
        "basis": {
            "ground": "abc",
            "tree": "def",
            "searched": ["docs", "src/jobs"],
            "prose": "The search found behavior but no rationale.",
        },
        "relevance": {"paths": ["src/jobs"], "related": ["task:document-recovery"]},
        "disposition": {
            "state": "resolved",
            "prose": "Documentation work is tracked separately.",
            "outputs": ["task:document-recovery"],
        },
    }
    discovery = Discovery.parse(raw)
    assert discovery.disposition.outputs == ["task:document-recovery"]
    assert validate_shape(Path(".invariant/discoveries/missing-adr.yml"), raw) == []


def test_stage_guidance_remains_free_form_and_composable() -> None:
    text = guidance.for_stage(
        "implementing", intent_expansion=True, outcome_review=True
    )
    assert "# Brief" in text
    assert "# Progressive discovery" in text
    assert "# Coordinate" in text
    assert "# Land" in text
    assert "# Optional outcome review" in text
