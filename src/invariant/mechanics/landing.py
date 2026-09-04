from __future__ import annotations

import os
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from invariant.errors import Blocked, InvariantError
from invariant.mechanics import audit, config, coordinate, git, governance, state


@dataclass(frozen=True)
class LandRequest:
    mode: str
    subject: str
    units: tuple[str, ...]
    scopes: tuple[str, ...]
    boundary: str
    merge_branch: str | None = None
    paths: tuple[str, ...] = ()
    domains: tuple[str, ...] = ()
    interfaces: tuple[str, ...] = ()
    governance_refs: tuple[str, ...] = ()
    reviewed: tuple[str, ...] = ()
    checks: tuple[str, ...] = ()
    target: str | None = None
    plan: str | None = None
    allow_open: bool = False


@dataclass(frozen=True)
class Candidate:
    commit: str
    tree: str
    target: str
    old: str | None
    unborn: bool
    covers: str | None
    reach_base: str | None


def _validate_request(request: LandRequest) -> None:
    if request.mode not in {"direct", "staged", "merge"}:
        raise InvariantError(f"Invariant: invalid landing mode '{request.mode}'")
    if not request.units:
        raise InvariantError("Invariant: landing requires at least one unit id")
    if not request.scopes:
        raise InvariantError("Invariant: landing requires at least one scope")
    if request.mode == "direct" and not request.paths:
        raise InvariantError("Invariant: direct landing requires --paths")
    if request.boundary not in {"no-record", "recorded"} and not request.boundary.startswith("audit:"):
        raise InvariantError(f"Invariant: invalid --boundary-review '{request.boundary}'")
    if request.boundary.startswith("audit:") and not git.valid_id(request.boundary.removeprefix("audit:")):
        raise InvariantError(f"Invariant: invalid boundary audit id '{request.boundary.removeprefix('audit:')}'")
    if request.boundary == "recorded" and not request.governance_refs:
        raise InvariantError(
            "Invariant: --boundary-review recorded requires at least one --governance reference"
        )
    if request.mode == "merge" and not request.merge_branch:
        raise InvariantError("Invariant: merge landing requires a branch")
    if request.mode == "staged" and (
        request.boundary != "no-record"
        or request.domains
        or request.interfaces
        or request.governance_refs
        or request.reviewed
        or request.plan
        or request.allow_open
    ):
        raise InvariantError(
            "Invariant: staged landing is only for an explicit local no-record edit; use normal work-branch landing"
        )


def _last_attested(repo: Path, old: str) -> str | None:
    commits = git.run(["rev-list", "--first-parent", old], cwd=repo, check=False).stdout.splitlines()
    for commit in commits:
        if git.trailers(repo, commit, "Intent-Boundary"):
            return commit
    return None


def _message(repo: Path, request: LandRequest, covers: str | None) -> str:
    message = governance.commit_message(
        repo,
        request.subject,
        request.units,
        request.scopes,
        request.domains,
        request.plan,
    )
    message += f"Intent-Boundary: {request.boundary}\n"
    if covers:
        message += f"Intent-Covers: {covers}\n"
    for reference in request.governance_refs:
        message += f"Intent-Governance: {reference}\n"
    for reference in request.reviewed:
        if reference.startswith("architecture:"):
            message += f"Intent-Architecture: {reference}\n"
    return message


def _temporary_index(repo: Path) -> tuple[dict[str, str], Path]:
    descriptor, name = tempfile.mkstemp(prefix="invariant-index.")
    os.close(descriptor)
    path = Path(name)
    path.unlink()
    return {"GIT_INDEX_FILE": str(path)}, path


def _construct(repo: Path, request: LandRequest, target: str) -> Candidate:
    old = git.resolve(repo, f"refs/heads/{target}")
    unborn = old is None
    if unborn and git.resolve(repo, "HEAD"):
        raise InvariantError(f"Invariant: integration branch '{target}' has no commit")
    if request.mode == "merge" and unborn:
        raise InvariantError("Invariant: an unborn integration branch requires a direct first landing")
    if request.mode == "staged" and unborn:
        raise InvariantError("Invariant: staged landing requires an existing integration commit")
    if request.mode == "direct" and not unborn:
        raise InvariantError(
            "Invariant: direct landing is reserved for the first commit on an unborn integration branch; use a work branch and merge"
        )

    current = git.current_branch(repo)
    target_worktree = git.worktree_for_branch(repo, target)
    if request.mode == "direct":
        if current != target:
            raise InvariantError(
                f"Invariant: unborn direct landing must run in the integration worktree ('{target}')"
            )
        if git.run(["diff", "--cached", "--quiet", "--"], cwd=repo, check=False).returncode:
            raise InvariantError("Invariant: staged changes exist; preserve or unstage them before direct landing")
    elif request.mode == "staged":
        if current != target:
            raise InvariantError(
                f"Invariant: staged landing must run in the checked-out integration branch ('{target}')"
            )
        if git.run(["ls-files", "-u"], cwd=repo).stdout:
            raise InvariantError("Invariant: staged landing cannot include unresolved index entries")
        if git.run(["diff", "--cached", "--quiet", "--"], cwd=repo, check=False).returncode == 0:
            raise InvariantError("Invariant: staged landing requires staged changes")
    elif target_worktree and not git.tracked_worktree_clean(target_worktree):
        raise InvariantError(
            f"Invariant: integration worktree '{target_worktree}' has tracked changes; landing cannot synchronize it safely"
        )

    branch_ref: str | None = None
    if request.mode == "merge":
        branch_ref = git.resolve(repo, f"refs/heads/{request.merge_branch}")
        if not branch_ref:
            raise InvariantError(f"Invariant: merge branch '{request.merge_branch}' does not exist locally")
        candidate_worktree = git.worktree_for_branch(repo, str(request.merge_branch))
        if candidate_worktree and not git.tracked_worktree_clean(candidate_worktree):
            raise InvariantError(
                f"Invariant: candidate worktree '{candidate_worktree}' has uncommitted tracked changes"
            )

    covers: str | None = None
    reach_base = old
    if old:
        last = _last_attested(repo, old)
        if last and last != old:
            covers = f"{last}..{old}"
            reach_base = last
    message = _message(repo, request, covers)

    if request.mode == "direct":
        environment, index = _temporary_index(repo)
        try:
            git.run(["read-tree", "--empty"], cwd=repo, env=environment)
            for path in request.paths:
                if Path(path).is_absolute() or ".." in Path(path).parts:
                    raise InvariantError(f"Invariant: invalid landing path '{path}'")
                git.run(["add", "-A", "--", path], cwd=repo, env=environment)
            tree = git.run(["write-tree"], cwd=repo, env=environment).stdout
        finally:
            index.unlink(missing_ok=True)
        candidate = git.run(["commit-tree", tree, "-F", "-"], cwd=repo, input_text=message).stdout
    elif request.mode == "staged":
        assert old is not None
        tree = git.run(["write-tree"], cwd=repo).stdout
        if tree == git.resolve(repo, f"{old}^{{tree}}", ""):
            raise InvariantError("Invariant: staged index produces no change")
        candidate = git.run(["commit-tree", tree, "-p", old, "-F", "-"], cwd=repo, input_text=message).stdout
    else:
        assert old is not None and branch_ref is not None
        tree = git.merge_tree(repo, old, branch_ref)
        candidate = git.run(
            ["commit-tree", tree, "-p", old, "-p", branch_ref, "-F", "-"],
            cwd=repo,
            input_text=message,
        ).stdout
    return Candidate(candidate, tree, target, old, unborn, covers, reach_base)


def prospective_tree(repo: Path, target: str, branch: str | None = None) -> str:
    """Return the exact prospective tree without creating a commit or moving a ref."""
    old = git.resolve(repo, f"refs/heads/{target}")
    if old is None:
        _, tree = audit.snapshot(repo)
        return tree
    if not branch:
        raise InvariantError("Invariant: a born integration target requires a candidate branch")
    branch_ref = git.resolve(repo, f"refs/heads/{branch}")
    if not branch_ref:
        raise InvariantError(f"Invariant: task branch '{branch}' is missing")
    return git.merge_tree(repo, old, branch_ref)


def _candidate_paths(repo: Path, candidate: Candidate) -> list[str]:
    if candidate.old:
        return git.changed_paths(repo, candidate.old, candidate.commit)
    return git.run(
        ["diff-tree", "--no-commit-id", "--name-only", "-r", "--root", candidate.commit],
        cwd=repo,
    ).stdout.splitlines()


def _untracked_collisions(target_worktree: Path, candidate_paths: Iterable[str]) -> list[str]:
    untracked = git.run(["ls-files", "--others", "--"], cwd=target_worktree, check=False).stdout.splitlines()
    tracked = list(candidate_paths)
    collisions: list[str] = []
    for local in untracked:
        if any(governance.paths_related(local, candidate) for candidate in tracked):
            collisions.append(local)
    return collisions


def _checkout_safe(repo: Path, request: LandRequest, candidate: Candidate) -> None:
    current = git.resolve(repo, f"refs/heads/{candidate.target}")
    if current != candidate.old:
        raise Blocked(
            f"Invariant: integration branch changed during landing (expected {candidate.old}, current {current})",
            code="concurrent_ref_movement",
        )
    target_worktree = git.worktree_for_branch(repo, candidate.target)
    if request.mode == "staged":
        current_index = git.run(["write-tree"], cwd=repo).stdout
        if current_index != candidate.tree:
            raise InvariantError("Invariant: staged index changed during landing")
        return
    if request.mode == "direct" or not target_worktree:
        return
    if not git.tracked_worktree_clean(target_worktree):
        raise InvariantError(f"Invariant: integration worktree '{target_worktree}' changed during landing")
    collisions = _untracked_collisions(target_worktree, git.run(
        ["ls-tree", "-r", "--name-only", candidate.commit, "--"], cwd=repo
    ).stdout.splitlines())
    if collisions:
        raise InvariantError(
            "Invariant: untracked integration files collide with the candidate:",
            lines=[f"  {item}" for item in collisions],
            code="untracked_collision",
        )


def _governance_exists(repo: Path, reference: str) -> bool:
    if ":" not in reference:
        return False
    kind, identifier = reference.split(":", 1)
    if kind == "domain":
        return identifier in {str(row.get("id")) for row in governance.domains(repo)}
    if kind == "contract":
        return identifier in {str(row.get("id")) for row in governance.contracts(repo)}
    if kind == "constraint":
        return identifier in {str(row.get("id")) for row in governance.constraints(repo)}
    if kind == "architecture":
        path = identifier.split("#", 1)[0]
        if not (repo / path).is_file():
            return False
        return reference in {
            item
            for row in [*governance.domains(repo), *governance.contracts(repo)]
            for item in governance.architecture_refs(row.get("architecture"))
        }
    return False


def _run_locator(repo: Path, locator: str) -> list[str]:
    output = [f"CHECK: running — {locator}"]
    if locator.startswith("command:"):
        path = locator.removeprefix("command:")
        candidate = repo / path
        if not candidate.is_file() or not candidate.stat().st_mode & 0o111:
            raise Blocked(
                f"Invariant: command verifier '{path}' is missing or not executable",
                code="verification_failed",
                lines=output,
            )
        command = [str(candidate)]
    elif locator.startswith("test:"):
        spec = locator.removeprefix("test:")
        path = spec.split("::", 1)[0]
        candidate = repo / path
        if path.endswith(".sh"):
            command = ["sh", path]
        elif path.endswith(".py"):
            command = ["python3", "-m", "pytest", spec]
        elif candidate.is_file() and candidate.stat().st_mode & 0o111:
            command = [str(candidate)]
        else:
            raise Blocked(
                f"Invariant: test verifier '{locator}' is not directly executable; use a command: wrapper",
                code="verification_failed",
                lines=output,
            )
    elif locator.startswith("schema:"):
        path = locator.removeprefix("schema:").split("#", 1)[0]
        candidate = repo / path
        if not candidate.is_file() or not candidate.stat().st_mode & 0o111:
            raise Blocked(
                f"Invariant: schema verifier '{locator}' needs an executable command: wrapper",
                code="verification_failed",
                lines=output,
            )
        command = [str(candidate)]
    elif locator.startswith("contract:"):
        raise Blocked(
            f"Invariant: nested contract verifier '{locator}' must resolve to an executable verifier before landing",
            code="verification_failed",
            lines=output,
        )
    else:
        raise Blocked(
            f"Invariant: unsupported check locator '{locator}'",
            code="verification_failed",
            lines=output,
        )
    completed = subprocess.run(command, cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if completed.stdout:
        output.extend(completed.stdout.rstrip("\n").splitlines())
    if completed.stderr:
        output.extend(completed.stderr.rstrip("\n").splitlines())
    if completed.returncode:
        raise Blocked(
            f"Invariant: verifier failed — {locator}", code="verification_failed", lines=output
        )
    return output


def _boundary_review(repo: Path, request: LandRequest, reach_lines: list[str]) -> list[str]:
    governance_changed = any(line.startswith("GOVERNANCE:") for line in reach_lines)
    if request.boundary == "no-record":
        if governance_changed:
            raise Blocked(
                "Invariant: governance changed; use --boundary-review recorded with --governance references",
                code="invalid_boundary",
            )
        return ["BOUNDARY-REVIEW: no-record"]
    if request.boundary.startswith("audit:"):
        if governance_changed:
            raise Blocked(
                "Invariant: governance changed; use --boundary-review recorded with --governance references",
                code="invalid_boundary",
            )
        identifier = request.boundary.removeprefix("audit:")
        path = repo / ".invariant" / "audits" / f"{identifier}.yml"
        if not path.is_file():
            raise Blocked(f"Invariant: boundary audit '{identifier}' is absent from the candidate")
        from invariant.mechanics.documents import load_yaml

        raw = load_yaml(path)
        if not isinstance(raw, dict) or raw.get("mode") != "scope":
            raise Blocked("Invariant: boundary review requires a scoped audit")
        unresolved = {"adoptable", "needs-authority", "needs-verifier"}
        if any(
            isinstance(item, dict) and item.get("disposition") in unresolved
            for item in raw.get("findings", [])
        ):
            raise Blocked(
                f"Invariant: boundary audit '{identifier}' has adoptable or unresolved findings"
            )
        audit.fresh(repo, identifier, "HEAD")
        return [f"BOUNDARY-REVIEW: audit:{identifier} — no governance adoption required"]
    for reference in request.governance_refs:
        if not _governance_exists(repo, reference):
            raise Blocked(
                f"Invariant: boundary governance '{reference}' is not an accepted candidate record"
            )
    return [f"BOUNDARY-REVIEW: recorded — {' '.join(request.governance_refs)}"]


def _coordinate_verify(repo: Path, request: LandRequest, candidate: Candidate) -> None:
    if not request.plan:
        return
    coordinate.validate_plan(repo, request.plan)
    lease_values: list[dict[str, object]] = []
    for unit in request.units:
        path = coordinate.runtime_root(repo) / "leases" / f"{unit}.yml"
        if not path.is_file():
            raise Blocked(f"Invariant: coordinated unit '{unit}' has no live lease")
        coordinate.lease_fresh(repo, unit)
        from invariant.mechanics.documents import load_yaml

        value = load_yaml(path)
        if not isinstance(value, dict):
            raise Blocked(f"Invariant: coordinated unit '{unit}' has an invalid lease")
        if value.get("integration_target") != candidate.target:
            raise Blocked(
                f"Invariant: lease '{unit}' targets '{value.get('integration_target')}', not '{candidate.target}'"
            )
        if request.mode == "merge" and value.get("branch") != request.merge_branch:
            raise Blocked(
                f"Invariant: lease '{unit}' belongs to '{value.get('branch')}', not '{request.merge_branch}'"
            )
        lease_values.append(value)
    for changed in _candidate_paths(repo, candidate):
        if not any(
            any(governance.paths_related(changed, claim) for claim in governance.refs(value.get("paths")))
            for value in lease_values
        ):
            raise Blocked(f"Invariant: coordinated path '{changed}' is outside the combined lease claims")
    for requested in request.interfaces:
        if not any(requested in governance.refs(value.get("interfaces")) for value in lease_values):
            raise Blocked(f"Invariant: interface '{requested}' is absent from the combined lease claims")
    for requested in request.domains:
        if not any(requested in governance.refs(value.get("domains")) for value in lease_values):
            raise Blocked(f"Invariant: domain '{requested}' is absent from the combined lease context")
    for requested in request.governance_refs:
        if not any(requested in governance.refs(value.get("governance")) for value in lease_values):
            raise Blocked(f"Invariant: governance '{requested}' is absent from the combined lease claims")


def verify_and_land(repo: Path, request: LandRequest, *, update_ref: bool = True) -> list[str]:
    _validate_request(request)
    target = request.target or config.resolve(repo).integration_branch
    if git.run(["check-ref-format", "--branch", target], cwd=repo, check=False).returncode:
        raise InvariantError(f"Invariant: invalid integration branch '{target}'")
    candidate = _construct(repo, request, target)
    _checkout_safe(repo, request, candidate)
    temporary = Path(tempfile.mkdtemp(prefix="invariant-land."))
    verify_dir = temporary / "verify"
    added = False
    output: list[str] = []
    try:
        git.run(["worktree", "add", "--quiet", "--detach", str(verify_dir), candidate.commit], cwd=repo)
        added = True
        if candidate.unborn:
            reach_lines = governance.reach(
                verify_dir,
                root_mode=True,
                domains_selected=list(request.domains),
                interfaces=list(request.interfaces),
            )
            verifier_lines = governance.verifiers(
                verify_dir,
                root_mode=True,
                domains_selected=list(request.domains),
                interfaces=list(request.interfaces),
            )
        else:
            reach_lines = governance.reach(
                verify_dir,
                base=candidate.reach_base,
                history=True,
                domains_selected=list(request.domains),
                interfaces=list(request.interfaces),
            )
            verifier_lines = governance.verifiers(
                verify_dir,
                base=candidate.reach_base,
                history=True,
                domains_selected=list(request.domains),
                interfaces=list(request.interfaces),
            )
        output.extend(reach_lines)
        if candidate.covers:
            output.append(f"COVERAGE: {candidate.covers}")
        verdict = next((line.removeprefix("REACH: ") for line in reach_lines if line.startswith("REACH: ")), "")
        if verdict in {"open", "gated"} and not request.allow_open:
            label = "open governance boundary" if verdict == "open" else "gated governance transition"
            raise Blocked(
                f"Invariant: {label} requires resolved authority (--allow-open)",
                code="authority_required",
                lines=output,
            )
        if request.mode == "staged" and verdict != "local":
            raise Blocked(
                f"Invariant: staged edit has {verdict} reach; use normal work-branch landing",
                lines=output,
            )
        prior_target = os.environ.get("GIT_INTENT_INTEGRATION_TARGET")
        prior_unborn = os.environ.get("GIT_INTENT_ALLOW_UNBORN")
        os.environ["GIT_INTENT_INTEGRATION_TARGET"] = target
        os.environ["GIT_INTENT_ALLOW_UNBORN"] = "1" if candidate.unborn else "0"
        try:
            state_lines = state.validate(verify_dir, landing=True)
        finally:
            if prior_target is None:
                os.environ.pop("GIT_INTENT_INTEGRATION_TARGET", None)
            else:
                os.environ["GIT_INTENT_INTEGRATION_TARGET"] = prior_target
            if prior_unborn is None:
                os.environ.pop("GIT_INTENT_ALLOW_UNBORN", None)
            else:
                os.environ["GIT_INTENT_ALLOW_UNBORN"] = prior_unborn
        if state_lines[-1] != "intent state valid" and state_lines[-1] != "no intent state — nothing to validate":
            raise Blocked("Invariant: candidate state validation failed", code="invalid_state", lines=state_lines)
        governance.validate_trailer(verify_dir, candidate.commit)
        output.extend(_boundary_review(verify_dir, request, reach_lines))

        executed: set[str] = set()
        for line in verifier_lines:
            if line.startswith("REVIEW: "):
                decision = line.split(" ", 2)[1]
                if decision not in request.reviewed:
                    raise Blocked(
                        f"Invariant: affected semantic {decision} requires --reviewed {decision} after prospective-tree review",
                        code="missing_review",
                        lines=output,
                    )
                output.append(f"REVIEW: accepted — {decision}")
            elif line.startswith("VERIFY: "):
                locator = line.split(" ", 2)[2]
                if locator not in executed:
                    output.extend(_run_locator(verify_dir, locator))
                    executed.add(locator)
        for locator in request.checks:
            if locator not in executed:
                output.extend(_run_locator(verify_dir, locator))
                executed.add(locator)
        output.append(f"CHECKS: {len(executed)} unique")
        _coordinate_verify(verify_dir, request, candidate)

        if not update_ref:
            output.append(f"VERIFIED: {candidate.commit} ({candidate.tree})")
            return output
        _checkout_safe(repo, request, candidate)
        expected = candidate.old or "0" * 40
        git.run(["update-ref", f"refs/heads/{target}", candidate.commit, expected], cwd=repo)
        target_worktree = git.worktree_for_branch(repo, target)
        if target_worktree:
            if request.mode in {"direct", "staged"}:
                git.run(["read-tree", candidate.commit], cwd=target_worktree)
            else:
                git.run(["read-tree", "--reset", "-u", candidate.commit], cwd=target_worktree)
        for unit in request.units:
            lease = coordinate.runtime_root(repo) / "leases" / f"{unit}.yml"
            if lease.is_file():
                coordinate.release_lease(repo, unit)
        if request.plan:
            plan_path = coordinate.runtime_root(repo) / "plans" / f"{request.plan}.yml"
            if plan_path.is_file():
                plan_lines = coordinate.plan_status(repo, request.plan)
                active = any(
                    status in line
                    for line in plan_lines
                    for status in (" active ", " waiting ", " dispatchable ")
                )
                if not active:
                    plan_path.unlink()
        output.append(
            f"LANDED: {candidate.commit} -> {target} (prospective tree verified before ref update)"
        )
        return output
    except Blocked as exc:
        if not exc.lines and output:
            exc.lines = output  # type: ignore[misc]
        raise
    finally:
        if added:
            git.run(["worktree", "remove", "--force", str(verify_dir)], cwd=repo, check=False)
        import shutil

        shutil.rmtree(temporary, ignore_errors=True)


def direct_edit(repo: Path, subject: str, unit: str, checks: Iterable[str], target: str | None = None) -> list[str]:
    if not git.valid_id(unit):
        raise InvariantError(f"Invariant: invalid unit id '{unit}'")
    target = target or config.resolve(repo).integration_branch
    if git.current_branch(repo) != target:
        raise InvariantError(
            f"Invariant: direct edit must run on the checked-out integration branch ('{target}')"
        )
    old = git.resolve(repo, "HEAD")
    if not old:
        raise InvariantError("Invariant: direct edit requires an existing integration commit")
    if git.run(["ls-files", "-u"], cwd=repo).stdout:
        raise InvariantError("Invariant: direct edit cannot include unresolved index entries")
    if git.run(["diff", "--cached", "--quiet", "--"], cwd=repo, check=False).returncode == 0:
        raise InvariantError("Invariant: direct edit requires staged changes")
    tree = git.run(["write-tree"], cwd=repo).stdout
    probe = git.run(
        ["commit-tree", tree, "-p", old, "-m", "Invariant direct-edit reach probe"], cwd=repo
    ).stdout
    temporary = Path(tempfile.mkdtemp(prefix="invariant-direct-edit."))
    verify_dir = temporary / "verify"
    try:
        git.run(["worktree", "add", "--quiet", "--detach", str(verify_dir), probe], cwd=repo)
        last = _last_attested(repo, old)
        base = last if last and last != old else old
        history = bool(last and last != old)
        reach_lines = governance.reach(verify_dir, base=base, history=history)
        verdict = next((line.removeprefix("REACH: ") for line in reach_lines if line.startswith("REACH: ")), "")
        if verdict != "local":
            raise Blocked(
                f"Invariant: direct edit has {verdict or 'unknown'} reach; use normal work-branch landing",
                lines=reach_lines,
            )
        scopes = tuple(line.removeprefix("TOPOLOGY: ") for line in reach_lines if line.startswith("TOPOLOGY: "))
        if not scopes:
            raise Blocked("Invariant: direct edit has no derived path scope; use normal work-branch landing")
    finally:
        git.run(["worktree", "remove", "--force", str(verify_dir)], cwd=repo, check=False)
        import shutil

        shutil.rmtree(temporary, ignore_errors=True)
    request = LandRequest(
        mode="staged",
        subject=subject,
        units=(unit,),
        scopes=scopes,
        boundary="no-record",
        checks=tuple(checks),
        target=target,
    )
    return [*reach_lines, *verify_and_land(repo, request)]
