from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from invariant.errors import InvariantError
from invariant.mechanics import git
from invariant.mechanics.documents import load_yaml


@dataclass(frozen=True)
class LifecycleOptions:
    intent_expansion: bool = False
    outcome_review: bool = False


@dataclass(frozen=True)
class Config:
    resolution: str
    execution: str
    integration_branch: str
    source: str
    branch_source: str
    unborn: bool
    lifecycle: LifecycleOptions


def _current(repo: Path) -> tuple[str, str]:
    captured = os.environ.get("GIT_INTENT_INTEGRATION_TARGET")
    if captured:
        return captured, "captured"
    branch = git.current_branch(repo)
    if not branch:
        raise InvariantError(
            "Invariant: integration_branch is not configured and HEAD is detached",
            code="missing_integration_target",
        )
    return branch, "current"


def resolve(repo: Path) -> Config:
    config_path = repo / ".invariant" / "config.yml"
    if not config_path.exists():
        branch, branch_source = _current(repo)
        return _finish(repo, "assisted", "auto", branch, "default", branch_source, LifecycleOptions())
    if not config_path.is_file():
        raise InvariantError("Invariant: .invariant/config.yml is not a regular file")
    raw = load_yaml(config_path)
    if not isinstance(raw, dict) or raw.get("version") != 1:
        raise InvariantError("Invariant: .invariant/config.yml must declare version: 1")
    allowed = {"version", "resolution", "execution", "integration_branch", "lifecycle"}
    unknown = sorted(set(raw) - allowed)
    if unknown:
        raise InvariantError(f"Invariant: .invariant/config.yml has unknown field '{unknown[0]}'")
    resolution = raw.get("resolution", "assisted")
    if resolution not in {"assisted", "auto"}:
        raise InvariantError(
            f"Invariant: .invariant/config.yml has invalid resolution '{resolution}' (use assisted or auto)"
        )
    execution = raw.get("execution", "auto")
    if execution not in {"auto", "assisted"}:
        raise InvariantError(
            f"Invariant: .invariant/config.yml has invalid execution '{execution}' (use auto or assisted)"
        )
    lifecycle_raw = raw.get("lifecycle", {})
    if not isinstance(lifecycle_raw, dict):
        raise InvariantError("Invariant: .invariant/config.yml lifecycle must be a mapping")
    lifecycle_unknown = sorted(set(lifecycle_raw) - {"intent_expansion", "outcome_review"})
    if lifecycle_unknown:
        raise InvariantError(
            f"Invariant: .invariant/config.yml has unknown lifecycle field '{lifecycle_unknown[0]}'"
        )
    for key in ("intent_expansion", "outcome_review"):
        if key in lifecycle_raw and not isinstance(lifecycle_raw[key], bool):
            raise InvariantError(f"Invariant: lifecycle.{key} must be true or false")
    lifecycle = LifecycleOptions(
        lifecycle_raw.get("intent_expansion", False), lifecycle_raw.get("outcome_review", False)
    )
    configured = raw.get("integration_branch")
    if configured is not None and (not isinstance(configured, str) or not configured):
        raise InvariantError("Invariant: integration_branch must be a non-empty branch name")
    if configured:
        branch, branch_source = configured, "config"
    else:
        branch, branch_source = _current(repo)
    return _finish(repo, resolution, execution, branch, ".invariant/config.yml", branch_source, lifecycle)


def _finish(
    repo: Path,
    resolution: str,
    execution: str,
    branch: str,
    source: str,
    branch_source: str,
    lifecycle: LifecycleOptions,
) -> Config:
    unborn = not git.branch_exists(repo, branch)
    if unborn:
        symbolic = git.current_branch(repo)
        allowed_unborn = (
            symbolic == branch and git.resolve(repo, "HEAD") is None
        ) or (
            os.environ.get("GIT_INTENT_ALLOW_UNBORN") == "1"
            and os.environ.get("GIT_INTENT_INTEGRATION_TARGET") == branch
        )
        if not allowed_unborn:
            raise InvariantError(f"Invariant: configured integration branch '{branch}' does not exist locally")
    return Config(resolution, execution, branch, source, branch_source, unborn, lifecycle)


def lines(config: Config) -> list[str]:
    output = [
        f"resolution: {config.resolution}",
        f"execution: {config.execution}",
        f"integration_branch: {config.integration_branch}",
        f"source: {config.source}",
        f"integration_branch_resolved: {config.integration_branch}",
        f"branch_source: {config.branch_source}",
        f"intent_expansion: {'true' if config.lifecycle.intent_expansion else 'false'}",
        f"outcome_review: {'true' if config.lifecycle.outcome_review else 'false'}",
    ]
    if config.unborn:
        output.append("integration_branch_unborn: true")
    return output

