from __future__ import annotations

import argparse
from pathlib import Path

from invariant.errors import Blocked
from invariant.mechanics import audit, config, git


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("evidence", help="Audit and record progressive discoveries")
    commands = parser.add_subparsers(dest="evidence_command", required=True)
    audit_parser = commands.add_parser("audit")
    audits = audit_parser.add_subparsers(dest="audit_command", required=True)
    scope = audits.add_parser("scope")
    scope.add_argument("--path", action="append", required=True)
    scope.set_defaults(_handler=_scope, _command="evidence.audit.scope")
    full = audits.add_parser("full")
    full.add_argument("--resolution", choices=["assisted", "auto"])
    full.set_defaults(_handler=_full, _command="evidence.audit.full")
    fresh = commands.add_parser("fresh")
    fresh.add_argument("locator")
    fresh.add_argument("--at", default="HEAD")
    fresh.set_defaults(_handler=_fresh, _command="evidence.fresh")
    discovery = commands.add_parser("discovery")
    discoveries = discovery.add_subparsers(dest="discovery_command", required=True)
    capture = discoveries.add_parser("capture")
    capture.add_argument("discovery_id")
    capture.add_argument("--observation", required=True)
    capture.add_argument("--evidence", action="append", default=[])
    capture.add_argument("--searched", action="append", default=[])
    capture.add_argument("--basis-prose", default="")
    capture.add_argument("--domain", action="append", default=[])
    capture.add_argument("--path", action="append", default=[])
    capture.add_argument("--related", action="append", default=[])
    capture_action = capture.add_mutually_exclusive_group()
    capture_action.add_argument("--dry-run", action="store_true")
    capture_action.add_argument("--apply", action="store_true")
    capture.set_defaults(_handler=_capture, _command="evidence.discovery.capture")
    resolve = discoveries.add_parser("resolve")
    resolve.add_argument("discovery_id")
    resolve.add_argument("--prose", default="")
    resolve.add_argument("--output", action="append", default=[])
    resolve_action = resolve.add_mutually_exclusive_group()
    resolve_action.add_argument("--dry-run", action="store_true")
    resolve_action.add_argument("--apply", action="store_true")
    resolve.set_defaults(_handler=_resolve, _command="evidence.discovery.resolve")


def _scope(args: argparse.Namespace) -> list[str]:
    return audit.frame(git.root(), "scope", args.path)


def _full(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    resolution = args.resolution or config.resolve(repo).resolution
    return audit.full(repo, resolution)


def _resolution_mode(repo: Path) -> str:
    proposed = config.resolve(repo)
    if proposed.resolution != "auto":
        return "assisted"
    ground = git.resolve(repo, f"refs/heads/{proposed.integration_branch}")
    if not ground:
        return "assisted"
    accepted = config.resolve_at(repo, ground, proposed.integration_branch)
    return "auto" if accepted.resolution == "auto" else "assisted"


def _fresh(args: argparse.Namespace) -> list[str]:
    return audit.fresh(git.root(), args.locator, args.at)


def _capture(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    preview = args.dry_run or (_resolution_mode(repo) == "assisted" and not args.apply)
    lines = audit.capture_discovery(
        repo,
        args.discovery_id,
        observation=args.observation,
        evidence=args.evidence,
        searched=args.searched,
        basis_prose=args.basis_prose,
        domains=args.domain,
        paths=args.path,
        related=args.related,
        dry_run=preview,
    )
    if preview and not args.dry_run:
        observation = " ".join(args.observation.split())
        raise Blocked(
            "Invariant: assisted resolution requires approval before recording a discovery",
            code="resolution_required",
            lines=[
                f"PROPOSAL: record discovery {args.discovery_id} — {observation}",
                *lines,
                "NEXT: after human approval, the harness must rerun this command with --apply",
            ],
        )
    return lines


def _resolve(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    preview = args.dry_run or (_resolution_mode(repo) == "assisted" and not args.apply)
    lines = audit.resolve_discovery(
        repo, args.discovery_id, prose=args.prose, outputs=args.output, dry_run=preview
    )
    if preview and not args.dry_run:
        raise Blocked(
            "Invariant: assisted resolution requires approval before resolving a discovery",
            code="resolution_required",
            lines=[
                f"PROPOSAL: resolve discovery {args.discovery_id}",
                *lines,
                "NEXT: after human approval, the harness must rerun this command with --apply",
            ],
        )
    return lines
