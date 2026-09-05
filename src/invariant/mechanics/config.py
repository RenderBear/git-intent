from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from invariant.errors import InvariantError
from invariant.mechanics import git
from invariant.mechanics.documents import dump_yaml, load_yaml


CONFIG_PATH = Path(".invariant/config.yml")
SETTABLE_KEYS = {
    "coding_agents",
    "authority",
    "execution",
    "integration_branch",
    "push_remote",
    "lifecycle.intent_expansion",
    "lifecycle.outcome_review",
}
CODING_AGENT_CHOICES = {"claude", "codex"}


@dataclass(frozen=True)
class LifecycleOptions:
    intent_expansion: bool = False
    outcome_review: bool = False


@dataclass(frozen=True)
class Config:
    coding_agents: tuple[str, ...]
    authority: str
    execution: str
    integration_branch: str
    integration_branch_setting: str
    push_remote: str
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


def _from_raw(
    repo: Path,
    raw: Any,
    *,
    source: str,
    fallback_branch: str,
    fallback_source: str,
) -> Config:
    if not isinstance(raw, dict) or raw.get("version") != 1:
        raise InvariantError("Invariant: .invariant/config.yml must declare version: 1")
    allowed = {
        "version",
        "coding_agents",
        "authority",
        "execution",
        "integration_branch",
        "push_remote",
        "lifecycle",
    }
    if "resolution" in raw:
        raise InvariantError(
            "Invariant: .invariant/config.yml uses removed field 'resolution'; "
            "replace resolution: auto with authority: agent, or resolution: assisted with authority: human"
        )
    unknown = sorted(set(raw) - allowed)
    if unknown:
        raise InvariantError(f"Invariant: .invariant/config.yml has unknown field '{unknown[0]}'")
    agents_raw = raw.get("coding_agents", ["codex", "claude"])
    if (
        not isinstance(agents_raw, list)
        or not agents_raw
        or any(not isinstance(item, str) or item not in CODING_AGENT_CHOICES for item in agents_raw)
    ):
        raise InvariantError(
            "Invariant: .invariant/config.yml coding_agents must be a non-empty list containing codex or claude"
        )
    selected_agents = set(agents_raw)
    coding_agents = tuple(item for item in ("codex", "claude") if item in selected_agents)
    authority = raw.get("authority", "agent")
    if authority not in {"agent", "human"}:
        raise InvariantError(
            f"Invariant: .invariant/config.yml has invalid authority '{authority}' (use agent or human)"
        )
    execution = raw.get("execution", "auto")
    if execution not in {"auto", "assisted"}:
        raise InvariantError(
            f"Invariant: .invariant/config.yml has invalid execution '{execution}' (use auto or assisted)"
        )
    push_value = raw.get("push_remote", "off")
    push_remote = ("on" if push_value else "off") if isinstance(push_value, bool) else push_value
    if push_remote not in {"on", "off"}:
        raise InvariantError(
            f"Invariant: .invariant/config.yml has invalid push_remote '{push_remote}' (use on or off)"
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
    configured = raw.get("integration_branch", "auto")
    if not isinstance(configured, str) or not configured:
        raise InvariantError("Invariant: integration_branch must be auto or a non-empty branch name")
    if configured == "auto":
        branch = fallback_branch
        branch_source = fallback_source
    else:
        if git.run(["check-ref-format", "--branch", configured], cwd=repo, check=False).returncode:
            raise InvariantError(f"Invariant: invalid integration branch '{configured}'")
        branch = configured
        branch_source = "config"
    return _finish(
        repo,
        coding_agents,
        authority,
        execution,
        branch,
        configured,
        push_remote,
        source,
        branch_source,
        lifecycle,
    )


def resolve(repo: Path) -> Config:
    config_path = repo / CONFIG_PATH
    if not config_path.exists():
        branch, branch_source = _current(repo)
        return _finish(
            repo,
            ("codex", "claude"),
            "agent",
            "auto",
            branch,
            "auto",
            "off",
            "default",
            branch_source,
            LifecycleOptions(),
        )
    if not config_path.is_file():
        raise InvariantError("Invariant: .invariant/config.yml is not a regular file")
    raw = load_yaml(config_path)
    branch, branch_source = _current(repo)
    return _from_raw(
        repo,
        raw,
        source=CONFIG_PATH.as_posix(),
        fallback_branch=branch,
        fallback_source=branch_source,
    )


def resolve_at(repo: Path, ref: str, integration_branch: str) -> Config:
    if not git.resolve(repo, ref):
        raise InvariantError(f"Invariant: configuration ground '{ref}' does not resolve")
    result = git.run(["show", f"{ref}:{CONFIG_PATH.as_posix()}"], cwd=repo, check=False)
    if result.returncode:
        return _finish(
            repo,
            ("codex", "claude"),
            "agent",
            "auto",
            integration_branch,
            "auto",
            "off",
            "default",
            "accepted",
            LifecycleOptions(),
        )
    try:
        raw = yaml.safe_load(result.stdout)
    except yaml.YAMLError as exc:
        raise InvariantError(
            f"Invariant: invalid YAML in {CONFIG_PATH.as_posix()} at {ref}: {exc}",
            code="invalid_yaml",
        ) from exc
    return _from_raw(
        repo,
        raw,
        source=f"{CONFIG_PATH.as_posix()} at {ref}",
        fallback_branch=integration_branch,
        fallback_source="accepted",
    )


def _document(config: Config) -> dict[str, Any]:
    return {
        "version": 1,
        "coding_agents": list(config.coding_agents),
        "authority": config.authority,
        "execution": config.execution,
        "integration_branch": config.integration_branch_setting,
        "push_remote": config.push_remote,
        "lifecycle": {
            "intent_expansion": config.lifecycle.intent_expansion,
            "outcome_review": config.lifecycle.outcome_review,
        },
    }


def initialize(
    repo: Path,
    *,
    coding_agents: tuple[str, ...] | None = None,
    authority: str | None = None,
    execution: str | None = None,
    integration_branch: str | None = None,
    push_remote: str | None = None,
    intent_expansion: bool | None = None,
    outcome_review: bool | None = None,
) -> list[str]:
    path = repo / CONFIG_PATH
    if path.exists():
        raise InvariantError(f"Invariant: {CONFIG_PATH.as_posix()} already exists", code="config_exists")
    branch_setting = integration_branch or "auto"
    if branch_setting == "auto":
        fallback_branch, fallback_source = _current(repo)
    else:
        fallback_branch, fallback_source = branch_setting, "config"
    document: dict[str, Any] = {
        "version": 1,
        "coding_agents": list(coding_agents if coding_agents is not None else ("codex", "claude")),
        "authority": authority if authority is not None else "agent",
        "execution": execution if execution is not None else "auto",
        "integration_branch": branch_setting,
        "push_remote": push_remote if push_remote is not None else "off",
        "lifecycle": {
            "intent_expansion": intent_expansion is True,
            "outcome_review": outcome_review is True,
        },
    }
    _from_raw(
        repo,
        document,
        source=CONFIG_PATH.as_posix(),
        fallback_branch=fallback_branch,
        fallback_source=fallback_source,
    )
    dump_yaml(path, document)
    return [f"CONFIG: created {CONFIG_PATH.as_posix()}", *lines(resolve(repo))]


def set_value(repo: Path, key: str, value: str) -> list[str]:
    if key not in SETTABLE_KEYS:
        raise InvariantError(f"Invariant: configuration key '{key}' is not settable", code="invalid_config_key")
    path = repo / CONFIG_PATH
    if path.exists():
        current = resolve(repo)
        raw = load_yaml(path)
        if not isinstance(raw, dict):
            raise InvariantError("Invariant: .invariant/config.yml must contain a mapping")
        document = dict(raw)
    else:
        current = resolve(repo)
        document = _document(current)

    if key == "coding_agents":
        values = [item.strip() for item in value.split(",") if item.strip()]
        if not values or any(item not in CODING_AGENT_CHOICES for item in values):
            raise InvariantError(
                "Invariant: coding_agents must be a comma-separated list containing codex or claude",
                code="invalid_config_value",
            )
        selected = set(values)
        document[key] = [item for item in ("codex", "claude") if item in selected]
    elif key in {"authority", "execution"}:
        choices = {"authority": {"agent", "human"}, "execution": {"auto", "assisted"}}
        if value not in choices[key]:
            expected = " or ".join(sorted(choices[key]))
            raise InvariantError(f"Invariant: {key} must be {expected}", code="invalid_config_value")
        document[key] = value
    elif key == "integration_branch":
        if value != "auto" and git.run(["check-ref-format", "--branch", value], cwd=repo, check=False).returncode:
            raise InvariantError(f"Invariant: invalid integration branch '{value}'", code="invalid_config_value")
        document[key] = value
    elif key == "push_remote":
        if value not in {"on", "off"}:
            raise InvariantError("Invariant: push_remote must be on or off", code="invalid_config_value")
        document[key] = value
    else:
        if value not in {"on", "off"}:
            raise InvariantError(f"Invariant: {key} must be on or off", code="invalid_config_value")
        lifecycle = document.get("lifecycle", {})
        if not isinstance(lifecycle, dict):
            raise InvariantError("Invariant: .invariant/config.yml lifecycle must be a mapping")
        lifecycle = dict(lifecycle)
        lifecycle[key.removeprefix("lifecycle.")] = value == "on"
        document["lifecycle"] = lifecycle

    _from_raw(
        repo,
        document,
        source=CONFIG_PATH.as_posix(),
        fallback_branch=current.integration_branch,
        fallback_source=current.branch_source,
    )
    dump_yaml(path, document)
    return [f"CONFIG: set {key}={value}", *lines(resolve(repo))]


def _finish(
    repo: Path,
    coding_agents: tuple[str, ...],
    authority: str,
    execution: str,
    branch: str,
    branch_setting: str,
    push_remote: str,
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
    return Config(
        coding_agents,
        authority,
        execution,
        branch,
        branch_setting,
        push_remote,
        source,
        branch_source,
        unborn,
        lifecycle,
    )


def lines(config: Config) -> list[str]:
    output = [
        "version: 1",
        f"coding_agents: {', '.join(config.coding_agents)}",
        f"authority: {config.authority}",
        f"execution: {config.execution}",
        f"integration_branch: {config.integration_branch_setting}",
        f"push_remote: {config.push_remote}",
        f"source: {config.source}",
        f"integration_branch_resolved: {config.integration_branch}",
        f"branch_source: {config.branch_source}",
        f"intent_expansion: {'true' if config.lifecycle.intent_expansion else 'false'}",
        f"outcome_review: {'true' if config.lifecycle.outcome_review else 'false'}",
    ]
    if config.unborn:
        output.append("integration_branch_unborn: true")
    return output
