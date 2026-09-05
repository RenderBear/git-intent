from __future__ import annotations

import argparse

from invariant.lifecycle import tasks
from invariant.mechanics import git


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("task", help="Manage the fixed repository task lifecycle")
    commands = parser.add_subparsers(dest="task_command", required=True)

    begin = commands.add_parser("begin")
    begin.add_argument("task_id")
    begin.add_argument("--goal", required=True)
    begin.add_argument(
        "--boundary",
        default="unresolved",
        help="initial durable-meaning disposition (defaults to unresolved)",
    )
    begin.add_argument("--path", action="append", default=[])
    begin.add_argument("--interface", action="append", default=[])
    begin.add_argument("--domain", action="append", default=[])
    begin.add_argument("--intent")
    begin.add_argument("--intent-expansion", action=argparse.BooleanOptionalAction, default=None)
    begin.add_argument("--outcome-review", action=argparse.BooleanOptionalAction, default=None)
    begin.set_defaults(_handler=_begin, _command="task.begin")

    status = commands.add_parser("status")
    status.add_argument("task_id")
    status.set_defaults(_handler=_status, _command="task.status")

    check = commands.add_parser("check")
    check.add_argument("task_id")
    goal = check.add_mutually_exclusive_group(required=True)
    goal.add_argument("--goal")
    goal.add_argument("--goal-digest")
    check.add_argument("--compatible-goal", action="store_true")
    check.add_argument("--path", action="append")
    check.add_argument("--interface", action="append")
    check.add_argument("--domain", action="append")
    check.set_defaults(_handler=_check, _command="task.check")

    finish = commands.add_parser("finish")
    finish.add_argument("task_id")
    finish.add_argument("--assessment", required=True)
    finish.add_argument("--subject")
    finish.add_argument("--check", action="append", default=[])
    finish.set_defaults(_handler=_finish, _command="task.finish")

    continuation = commands.add_parser("continue")
    continuation.add_argument("task_id")
    continuation.add_argument("--apply", action="store_true")
    continuation.set_defaults(_handler=_continue, _command="task.continue")

    invalidate = commands.add_parser("invalidate")
    invalidate.add_argument("task_id")
    invalidate.set_defaults(_handler=_invalidate, _command="task.invalidate")

    guide = commands.add_parser("guidance")
    guide.add_argument("task_id")
    guide.set_defaults(_handler=_guidance, _command="task.guidance")


def _repo():
    return git.root()


def _begin(args: argparse.Namespace) -> list[str]:
    return tasks.begin(
        _repo(),
        args.task_id,
        goal=args.goal,
        boundary=args.boundary,
        paths=args.path,
        interfaces=args.interface,
        domains=args.domain,
        intent_file=args.intent,
        intent_expansion=args.intent_expansion,
        outcome_review=args.outcome_review,
    )


def _status(args: argparse.Namespace) -> list[str]:
    return tasks.status(_repo(), args.task_id)


def _check(args: argparse.Namespace) -> list[str]:
    return tasks.check(
        _repo(),
        args.task_id,
        goal=args.goal,
        goal_digest=args.goal_digest,
        compatible_goal=args.compatible_goal,
        paths=args.path,
        interfaces=args.interface,
        domains=args.domain,
    )


def _finish(args: argparse.Namespace) -> list[str]:
    return tasks.finish(
        _repo(),
        args.task_id,
        assessment_path=args.assessment,
        subject=args.subject,
        checks=args.check,
    )


def _continue(args: argparse.Namespace) -> list[str]:
    return tasks.continue_task(_repo(), args.task_id, apply=args.apply)


def _invalidate(args: argparse.Namespace) -> list[str]:
    return tasks.invalidate(_repo(), args.task_id)


def _guidance(args: argparse.Namespace) -> list[str]:
    return tasks.task_guidance(_repo(), args.task_id)
