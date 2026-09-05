from __future__ import annotations

import argparse
from pathlib import Path

from invariant.errors import Blocked, InvariantError
from invariant.lifecycle import tasks
from invariant.mechanics import audit, config, git, receipts
from invariant.mechanics.documents import dump_yaml, load_yaml


DEFAULT_GOAL = "Establish the repository's initial durable governance from a causal audit."
TASK_ID_HELP = "caller-chosen ID for this initial-governance session"


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser(
        "initial-governance",
        help="Run the audit, adoption, and verification phases as one resumable session",
    )
    commands = parser.add_subparsers(dest="initial_governance_command", required=True)

    begin = commands.add_parser("begin", help="Open the managed branch before creating an audit")
    begin.add_argument("task_id", help=TASK_ID_HELP)
    begin.add_argument("--goal", default=DEFAULT_GOAL)
    begin.set_defaults(_handler=_begin, _command="initial-governance.begin")

    save = commands.add_parser("audit-save", help="Save the full audit inside the managed session")
    save.add_argument("task_id", help=TASK_ID_HELP)
    save.add_argument("audit_label")
    save.add_argument("--input", type=Path, required=True)
    save.set_defaults(_handler=_audit_save, _command="initial-governance.audit-save")

    adopt = commands.add_parser("adopt", help="Select ready audit findings for governance adoption")
    adopt.add_argument("task_id", help=TASK_ID_HELP)
    selection = adopt.add_mutually_exclusive_group(required=True)
    selection.add_argument("--all-ready", action="store_true")
    selection.add_argument("--finding", action="append")
    adopt.set_defaults(_handler=_adopt, _command="initial-governance.adopt")

    defer = commands.add_parser(
        "defer", help="Land the saved audit without adopting durable governance"
    )
    defer.add_argument("task_id", help=TASK_ID_HELP)
    defer.set_defaults(_handler=_defer, _command="initial-governance.defer")

    status = commands.add_parser("status", help="Show the governance phase and managed task state")
    status.add_argument("task_id", help=TASK_ID_HELP)
    status.set_defaults(_handler=_status, _command="initial-governance.status")


def _session(repo: Path, task: str) -> tuple[dict[str, object], dict[str, object]]:
    receipt = receipts.load(repo, task)
    session = (
        receipt.get("initial_governance")
        if isinstance(receipt.get("initial_governance"), dict)
        else None
    )
    if session is None:
        raise Blocked(f"Invariant: task '{task}' is not an initial-governance session")
    return receipt, session


def _authority(repo: Path, receipt: dict[str, object]) -> str:
    proposed = config.resolve(repo)
    ground = str(receipt.get("integration_head") or "")
    target = str(receipt.get("integration_target") or "")
    if proposed.authority != "agent" or ground == "unborn":
        return proposed.authority
    accepted = config.resolve_at(repo, ground, target)
    return "agent" if accepted.authority == "agent" else "human"


def _begin(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    lines = tasks.begin(
        repo,
        args.task_id,
        goal=args.goal,
        boundary="unresolved",
        paths=[],
        interfaces=[],
        domains=[],
        adapter_overrides={"task_acceptance": False},
    )
    receipt = receipts.load(repo, args.task_id)
    receipt["initial_governance"] = {"phase": "audit"}
    receipts.save(repo, args.task_id, receipt)
    lifecycle = receipt.get("lifecycle") if isinstance(receipt.get("lifecycle"), dict) else {}
    if lifecycle.get("stage") in {"implementing", "implementing-unborn"}:
        lines.extend(["GOVERNANCE-PHASE: audit", *audit.full(repo, _authority(repo, receipt))])
    else:
        lines.append("NEXT: continue the lifecycle, then rerun initial-governance status")
    return lines


def _audit_save(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    receipt, session = _session(repo, args.task_id)
    if session.get("phase") != "audit":
        raise Blocked(
            f"Invariant: initial-governance audit is already in phase '{session.get('phase')}'"
        )
    lifecycle = receipt.get("lifecycle") if isinstance(receipt.get("lifecycle"), dict) else {}
    branch = str(lifecycle.get("branch") or "")
    if branch and git.current_branch(repo) != branch:
        raise Blocked(f"Invariant: initial-governance task branch '{branch}' is not checked out")
    authority = _authority(repo, receipt)
    lines = audit.save(
        repo,
        args.audit_label,
        mode="full",
        source=args.input,
        paths=[],
        domains=[],
        authority=authority,
    )
    audit_id = next(line.removeprefix("AUDIT: ") for line in lines if line.startswith("AUDIT: "))
    raw = load_yaml(repo / ".invariant" / "audits" / f"{audit_id}.yml")
    findings = raw.get("findings", []) if isinstance(raw, dict) else []
    ready = [
        str(finding.get("id"))
        for finding in findings
        if isinstance(finding, dict) and finding.get("disposition") == "adoptable"
    ]
    session["audit"] = audit_id
    if authority == "agent":
        session["phase"] = "adopt"
        session["selected_findings"] = ready
        lines.extend(
            [
                "GOVERNANCE-PHASE: adopt",
                f"SELECTED-FINDINGS: {', '.join(ready) or 'none ready'}",
            ]
        )
    else:
        session["phase"] = "decision"
        lines.append("GOVERNANCE-PHASE: decision")
    receipt["initial_governance"] = session
    receipts.save(repo, args.task_id, receipt)
    return lines


def _adopt(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    receipt, session = _session(repo, args.task_id)
    if session.get("phase") not in {"decision", "adopt"}:
        raise Blocked(f"Invariant: adoption is unavailable in phase '{session.get('phase')}'")
    audit_id = str(session.get("audit") or "")
    raw = load_yaml(repo / ".invariant" / "audits" / f"{audit_id}.yml")
    findings = raw.get("findings", []) if isinstance(raw, dict) else []
    available = {
        str(finding.get("id")): str(finding.get("disposition"))
        for finding in findings
        if isinstance(finding, dict) and finding.get("id")
    }
    selected = (
        sorted(identifier for identifier, disposition in available.items() if disposition == "adoptable")
        if args.all_ready
        else sorted(set(args.finding or []))
    )
    missing = [identifier for identifier in selected if identifier not in available]
    if missing:
        raise InvariantError(f"Invariant: audit has no finding '{missing[0]}'")
    session["phase"] = "adopt"
    session["selected_findings"] = selected
    receipt["initial_governance"] = session
    receipts.save(repo, args.task_id, receipt)
    return [
        f"GOVERNANCE-PHASE: adopt",
        f"AUDIT: {audit_id}",
        f"SELECTED-FINDINGS: {', '.join(selected) or 'none'}",
        "NEXT: record the selected durable meaning, commit the candidate, then run task assessment prepare",
    ]


def _status(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    receipt, session = _session(repo, args.task_id)
    lines = [
        f"GOVERNANCE-PHASE: {session.get('phase')}",
        f"AUDIT: {session.get('audit') or 'not saved'}",
    ]
    selected = session.get("selected_findings")
    if isinstance(selected, list):
        lines.append(f"SELECTED-FINDINGS: {', '.join(str(item) for item in selected) or 'none'}")
    lines.extend(tasks.status(repo, args.task_id))
    lifecycle = receipt.get("lifecycle") if isinstance(receipt.get("lifecycle"), dict) else {}
    if session.get("phase") == "audit" and lifecycle.get("stage") in {
        "implementing",
        "implementing-unborn",
    }:
        lines.extend(audit.full(repo, _authority(repo, receipt)))
    return lines


def _defer(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    receipt, session = _session(repo, args.task_id)
    if session.get("phase") == "deferred":
        return ["GOVERNANCE-PHASE: deferred", *tasks.status(repo, args.task_id)]
    if session.get("phase") not in {"decision", "adopt"}:
        raise Blocked(f"Invariant: deferral is unavailable in phase '{session.get('phase')}'")
    audit_id = str(session.get("audit") or "")
    audit_path = f".invariant/audits/{audit_id}.yml"
    if not (repo / audit_path).is_file():
        raise Blocked(f"Invariant: saved audit '{audit_id}' is absent")
    lifecycle = receipt.get("lifecycle") if isinstance(receipt.get("lifecycle"), dict) else {}
    branch = str(lifecycle.get("branch") or "")
    if branch and git.current_branch(repo) != branch:
        raise Blocked(f"Invariant: initial-governance task branch '{branch}' is not checked out")
    working = git.changed_paths(repo)
    if working:
        if set(working) != {audit_path}:
            raise Blocked(
                "Invariant: deferral can commit only the saved audit; preserve or commit other work first",
                lines=[f"CHANGED: {path}" for path in working],
            )
        git.run(["add", "--", audit_path], cwd=repo)
        git.run(["commit", "-q", "-m", f"Record deferred governance audit {audit_id}"], cwd=repo)
    base = str(receipt.get("integration_head") or "")
    branch_ref = git.resolve(repo, f"refs/heads/{branch}") if branch else None
    candidate_paths = git.changed_paths(repo, base, branch_ref) if branch_ref and base != "unborn" else [audit_path]
    if set(candidate_paths) != {audit_path}:
        raise Blocked(
            "Invariant: deferral candidate contains changes beyond the saved audit",
            lines=[f"CANDIDATE-PATH: {path}" for path in candidate_paths],
        )
    assessment = {
        "version": 1,
        "goal_digest": str(receipt.get("goal_digest") or ""),
        "paths": [audit_path],
        "interfaces": [],
        "domains": [],
        "boundary": {"disposition": "no-record"},
        "governance": [],
        "architecture_reviews": [],
        "checks": [],
        "allow_open": False,
    }
    local = receipts.task_root(repo, args.task_id)
    assessment_path = local / "deferred-audit-assessment.yml"
    dump_yaml(assessment_path, assessment)
    session["phase"] = "deferred"
    receipt["initial_governance"] = session
    receipts.save(repo, args.task_id, receipt)
    return [
        "GOVERNANCE-PHASE: deferred",
        *tasks.finish(
            repo,
            args.task_id,
            assessment_path=str(assessment_path),
            subject=f"Record deferred governance audit {audit_id}",
        ),
    ]
