from __future__ import annotations

import argparse
import os
import sys
import textwrap
from collections.abc import Sequence

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


def _color(code: str, text: str) -> str:
    if not sys.stdout.isatty() or os.environ.get("NO_COLOR") is not None:
        return text
    return f"\033[{code}m{text}\033[0m"


def _select(
    title: str,
    question: str,
    options: Sequence[tuple[str, str, str]],
    default: str,
) -> str:
    print(f"\n{_color('1;36', f'◆ {title}')}\n  {question}\n")
    by_value = {value: (index, label) for index, (value, label, _) in enumerate(options, 1)}
    for index, (value, label, detail) in enumerate(options, 1):
        marker = "●" if value == default else "○"
        suffix = " (recommended)" if value == default else ""
        marker = _color("32" if value == default else "2", marker)
        number = _color("36" if value == default else "2", f"{index}.")
        option = _color("1", label) if value == default else label
        recommendation = _color("32", suffix)
        print(f"  {marker} {number} {option}{recommendation}")
        print(_color("2", f"       {detail}"))
    default_index = by_value[default][0]
    while True:
        try:
            answer = input(f"\n  {_color('36', '›')} Select [{default_index}]: ").strip()
        except EOFError:
            raise UsageError(
                "Invariant: interactive initialization needs terminal input; use invariant init --defaults"
            ) from None
        if not answer:
            return default
        if answer.isdigit() and 1 <= int(answer) <= len(options):
            return options[int(answer) - 1][0]
        if answer in by_value:
            return answer
        print(_color("33", f"  Choose 1-{len(options)} or enter one of: {', '.join(by_value)}"))


def _logo() -> None:
    print()
    print(f"{_color('1;35', '   /\\')}     {_color('1', 'INVARIANT')}")
    print(f"{_color('1;35', '  /  \\')}    {_color('2', 'Durable intent for agentic work')}")
    print(_color("1;35", "  \\  /"))
    print(_color("1;35", "   \\/"))


def _interactive(repo) -> bootstrap.BootstrapSettings:
    current = git.current_branch(repo) or "detached HEAD"
    _logo()
    agent_choice = _select(
        "Coding agents",
        "Which agents should receive the repository workflow?",
        (
            ("both", "Codex and Claude Code", "Share one workflow through AGENTS.md."),
            ("codex", "Codex only", "Install the workflow in AGENTS.md."),
            ("claude", "Claude Code only", "Install the workflow in CLAUDE.md."),
        ),
        "both",
    )
    coding_agents = {
        "both": ("codex", "claude"),
        "codex": ("codex",),
        "claude": ("claude",),
    }[agent_choice]
    resolution = _select(
        "Semantic decisions",
        "Who approves new or changed architectural intent?",
        (
            ("assisted", "Human review", "Ask before recording or resolving semantic findings."),
            ("auto", "Agent autonomy", "Proceed when accepted repository authority is sufficient."),
        ),
        "assisted",
    )
    execution = _select(
        "Git lifecycle",
        "How should local branch creation, verification, and landing run?",
        (
            ("auto", "Automatic", "Advance every valid and authorized local transition."),
            ("assisted", "Confirm first", "Pause before branch creation and verified landing."),
        ),
        "auto",
    )
    integration_branch = _select(
        "Integration branch",
        "Where should verified changes converge?",
        (
            ("auto", f"Current branch — {current}", "Resolve the target when each task begins."),
            ("named", "Another local branch", "Keep one fixed convergence target."),
        ),
        "auto",
    )
    if integration_branch == "named":
        try:
            integration_branch = input("\n  Branch name: ").strip()
        except EOFError:
            raise UsageError("Invariant: integration branch name is required") from None
        if not integration_branch:
            raise UsageError("Invariant: integration branch name is required")
    push_remote = _select(
        "Remote publication",
        "What should happen after a verified local landing?",
        (
            ("off", "Keep it local", "Never push unless this repository setting is changed."),
            ("on", "Publish upstream", "Push the exact commit to the branch's existing upstream."),
        ),
        "off",
    )
    intent_shaping = _select(
        "Intent shaping",
        "How should Invariant shape and review task intent?",
        (
            (
                "model",
                "Model's own understanding",
                "Use the coding agent's normal workflow without extra intent steps.",
            ),
            (
                "pre",
                "Intent expansion",
                "Before implementation, make outcomes, acceptance criteria, and constraints explicit.",
            ),
            (
                "post",
                "Outcome review",
                "Before landing, assess the exact candidate against the goal.",
            ),
            (
                "both",
                "Both expansion and review",
                "Expand intent before implementation, then assess the exact candidate before landing.",
            ),
        ),
        "model",
    )
    return bootstrap.BootstrapSettings(
        coding_agents=coding_agents,
        resolution=resolution,
        execution=execution,
        integration_branch=integration_branch,
        push_remote=push_remote,
        intent_expansion=intent_shaping in {"pre", "both"},
        outcome_review=intent_shaping in {"post", "both"},
    )


def _values(lines: list[str], name: str) -> list[str]:
    prefix = f"{name}: "
    return [line.removeprefix(prefix) for line in lines if line.startswith(prefix)]


def _summary(lines: list[str], *, show_logo: bool) -> None:
    if show_logo:
        _logo()
    value = lambda name: (_values(lines, name) or [""])[0]
    agents = value("CODING-AGENTS")
    agent_label = {
        "codex, claude": "Codex and Claude Code",
        "codex": "Codex",
        "claude": "Claude Code",
    }.get(agents, agents)
    resolution = "Human review" if value("RESOLUTION") == "assisted" else "Agent autonomy"
    execution = "Automatic" if value("EXECUTION") == "auto" else "Confirm first"
    branch = value("INTEGRATION-BRANCH")
    if value("INTEGRATION-BRANCH-SETTING") == "auto":
        branch = f"{branch} (current branch)"
    publication = "Local only" if value("PUSH-REMOTE") == "off" else "Existing upstream"
    shaping = {
        (False, False): "Model's own understanding",
        (True, False): "Intent expansion",
        (False, True): "Outcome review",
        (True, True): "Both expansion and review",
    }[
        (
            value("INTENT-EXPANSION") == "on",
            value("OUTCOME-REVIEW") == "on",
        )
    ]

    print(f"\n{_color('1;32', '✓ Repository initialized')}\n")
    rows = (
        ("Coding agents", agent_label),
        ("Semantic decisions", resolution),
        ("Git lifecycle", execution),
        ("Integration", branch),
        ("Publication", publication),
        ("Intent shaping", shaping),
        ("Configuration", value("CONFIG")),
    )
    for label, setting in rows:
        print(f"  {_color('36', f'{label:<20}')}{_color('1', setting)}")

    instructions = _values(lines, "INSTRUCTIONS")
    if instructions:
        print(f"\n{_color('1;36', '  Agent instructions')}")
        for item in instructions:
            print(f"  {_color('32', '•')} {item.removeprefix('configured ')}")

    print(f"\n{_color('1;33', 'Recommended next step')}\n")
    print("Ask your coding agent:\n")
    prompt = value("PROMPT")
    recommendation = textwrap.fill(
        f'“{prompt}”', width=76, initial_indent="  ", subsequent_indent="  "
    )
    print(_color("36", recommendation))


def _initialize(args: argparse.Namespace) -> list[str]:
    repo = git.root()
    if not args.defaults and args.format == "json":
        raise UsageError("Invariant: JSON initialization requires --defaults")
    settings = bootstrap.BootstrapSettings() if args.defaults else _interactive(repo)
    lines = bootstrap.initialize(repo, settings)
    if args.format == "text":
        _summary(lines, show_logo=args.defaults)
        return []
    return lines
