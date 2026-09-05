from __future__ import annotations

import argparse

from invariant.errors import UsageError
from invariant.lifecycle import bootstrap
from invariant.mechanics import git


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("init", help="Initialize Invariant for this repository")
    parser.add_argument(
        "--defaults",
        action="store_true",
        help="use all safe defaults and configure both Codex and Claude Code",
    )
    parser.set_defaults(_handler=_initialize, _command="init")


def _ask(
    title: str, explanation: str, choices: str, default: str, *, allow_other: bool = False
) -> str:
    print(f"\n{title}")
    print(explanation)
    while True:
        try:
            value = input(f"Value ({choices}) [{default}]: ").strip() or default
        except EOFError:
            raise UsageError(
                "Invariant: interactive initialization needs terminal input; use invariant init --defaults"
            ) from None
        if allow_other or value in {item.strip() for item in choices.split("|")}:
            return value
        print(f"Choose one of: {choices}")


def _interactive(repo) -> bootstrap.BootstrapSettings:
    current = git.current_branch(repo) or "detached HEAD"
    harness_choice = _ask(
        "Coding agents",
        "Choose which repository instruction files receive the Invariant workflow. Both keeps the "
        "workflow in AGENTS.md and lets Claude import it.",
        "both|codex|claude",
        "both",
    )
    harnesses = {
        "both": ("codex", "claude"),
        "codex": ("codex",),
        "claude": ("claude",),
    }[harness_choice]
    resolution = _ask(
        "Semantic resolution",
        "Assisted asks the human before discoveries or their resolutions become tracked evidence. "
        "Auto lets the agent proceed when accepted authority is sufficient.",
        "assisted|auto",
        "assisted",
    )
    execution = _ask(
        "Lifecycle execution",
        "Auto advances valid local lifecycle transitions immediately. Assisted pauses before branch "
        "creation and landing.",
        "auto|assisted",
        "auto",
    )
    integration_branch = _ask(
        "Integration branch",
        f"Auto uses the current branch for each new task (currently {current}). Choose a named local "
        "branch to keep one fixed convergence target.",
        "auto|<branch>",
        "auto",
        allow_other=True,
    )
    push_remote = _ask(
        "Remote publication",
        "Off keeps every verified landing local. On publishes the exact landed commit to the named "
        "integration branch's existing upstream.",
        "off|on",
        "off",
    )
    intent_expansion = _ask(
        "Intent expansion",
        "Off begins from the goal directly. On requires explicit outcomes, acceptance criteria, and "
        "constraints before implementation.",
        "off|on",
        "off",
    )
    outcome_review = _ask(
        "Outcome review",
        "Off relies on normal candidate review. On requires each expanded outcome to be assessed "
        "against the exact candidate tree before landing.",
        "off|on",
        "off",
    )
    return bootstrap.BootstrapSettings(
        harnesses=harnesses,
        resolution=resolution,
        execution=execution,
        integration_branch=integration_branch,
        push_remote=push_remote,
        intent_expansion=intent_expansion == "on",
        outcome_review=outcome_review == "on",
    )


def _initialize(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    if not args.defaults and args.format == "json":
        raise UsageError("Invariant: JSON initialization requires --defaults")
    settings = bootstrap.BootstrapSettings() if args.defaults else _interactive(repo)
    return bootstrap.initialize(repo, settings)
