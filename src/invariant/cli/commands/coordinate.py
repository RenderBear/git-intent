from __future__ import annotations

import argparse

from invariant.mechanics import coordinate, git


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("coordinate", help="Inspect plans and manage causal leases")
    commands = parser.add_subparsers(dest="coordinate_command", required=True)
    status = commands.add_parser("status")
    status.add_argument("plan", nargs="?")
    status.add_argument("--pinned", action="store_true")
    status.set_defaults(_handler=_status, _command="coordinate.status")
    plan = commands.add_parser("plan")
    plans = plan.add_subparsers(dest="plan_command", required=True)
    validate = plans.add_parser("validate")
    validate.add_argument("plan")
    validate.set_defaults(_handler=_plan, _command="coordinate.plan.validate")
    runtime = commands.add_parser("runtime")
    runtimes = runtime.add_subparsers(dest="runtime_command", required=True)
    root = runtimes.add_parser("root")
    root.set_defaults(_handler=lambda _: [str(coordinate.runtime_root(git.root()))], _command="coordinate.runtime.root")
    ensure = runtimes.add_parser("ensure")
    ensure.set_defaults(_handler=lambda _: [str(coordinate.ensure_runtime(git.root()))], _command="coordinate.runtime.ensure")
    clean = runtimes.add_parser("clean")
    clean.add_argument("--apply", action="store_true")
    clean.set_defaults(_handler=_clean, _command="coordinate.runtime.clean")
    lease = commands.add_parser("lease")
    leases = lease.add_subparsers(dest="lease_command", required=True)
    acquire = leases.add_parser("acquire", aliases=["create"])
    acquire.add_argument("unit")
    acquire.add_argument("--scope")
    acquire.add_argument("--path", action="append", default=[])
    acquire.add_argument("--interface", action="append", default=[])
    acquire.add_argument("--governance", action="append", default=[])
    acquire.add_argument("--domain", action="append", default=[])
    acquire.add_argument("--digest")
    acquire.add_argument("--branch")
    acquire.add_argument("--worktree")
    acquire.add_argument("--task")
    acquire.add_argument("--owner")
    acquire.add_argument("--integration-target")
    acquire.add_argument("--duration", default="2h")
    acquire.set_defaults(_handler=_acquire, _command="coordinate.lease.acquire")
    renew = leases.add_parser("renew")
    renew.add_argument("unit")
    renew.add_argument("--duration", default="2h")
    renew.set_defaults(_handler=_renew, _command="coordinate.lease.renew")
    release = leases.add_parser("release")
    release.add_argument("unit")
    release.set_defaults(_handler=_release, _command="coordinate.lease.release")
    listing = leases.add_parser("list")
    listing.add_argument("--scope")
    listing.add_argument("--domain")
    listing.set_defaults(_handler=_list, _command="coordinate.lease.list")
    fresh = leases.add_parser("fresh")
    fresh.add_argument("unit")
    fresh.set_defaults(_handler=_fresh, _command="coordinate.lease.fresh")
    reap = leases.add_parser("reap")
    reap.add_argument("--apply", action="store_true")
    reap.set_defaults(_handler=_reap, _command="coordinate.lease.reap")


def _status(args: argparse.Namespace) -> list[str]:
    if args.plan:
        return coordinate.plan_status(git.root(), args.plan, pinned=args.pinned)
    return coordinate.runtime_status(git.root())


def _plan(args: argparse.Namespace) -> list[str]:
    return coordinate.validate_plan(git.root(), args.plan)


def _clean(args: argparse.Namespace) -> list[str]:
    return coordinate.clean_runtime(git.root(), apply=args.apply)


def _acquire(args: argparse.Namespace) -> list[str]:
    return coordinate.create_lease(
        git.root(),
        args.unit,
        scope=args.scope,
        paths=args.path,
        interfaces=args.interface,
        governance_claims=args.governance,
        domains=args.domain,
        digest=args.digest,
        branch=args.branch,
        worktree=args.worktree,
        task=args.task,
        owner=args.owner,
        integration_target=args.integration_target,
        duration=args.duration,
    )


def _renew(args: argparse.Namespace) -> list[str]:
    return coordinate.renew_lease(git.root(), args.unit, args.duration)


def _release(args: argparse.Namespace) -> list[str]:
    return coordinate.release_lease(git.root(), args.unit)


def _list(args: argparse.Namespace) -> list[str]:
    return coordinate.list_leases(git.root(), scope=args.scope, domain=args.domain)


def _fresh(args: argparse.Namespace) -> list[str]:
    return coordinate.lease_fresh(git.root(), args.unit)


def _reap(args: argparse.Namespace) -> list[str]:
    return coordinate.reap_leases(git.root(), apply=args.apply).lines

