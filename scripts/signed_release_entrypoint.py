#!/usr/bin/env python3
"""Validate signed-release directory isolation before invoking the signing pipeline."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NoReturn, Sequence


class PathSafetyError(RuntimeError):
    """Raised when signed-release filesystem isolation cannot be proven."""


def fail(message: str, code: int = 1) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def strict_repository_child(path: Path, repository: Path, label: str) -> Path:
    repository = repository.resolve()
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(repository)
    except ValueError as error:
        raise PathSafetyError(f"{label} must remain inside the repository") from error
    if relative == Path("."):
        raise PathSafetyError(f"{label} must be a strict repository child")
    return resolved


def paths_overlap(first: Path, second: Path) -> bool:
    """Return true when paths are equal or one contains the other."""
    if first == second:
        return True
    try:
        first.relative_to(second)
        return True
    except ValueError:
        pass
    try:
        second.relative_to(first)
        return True
    except ValueError:
        return False


def validate_release_roots(
    repository: Path,
    output_root: Path,
    work_root: Path,
    evidence_root: Path,
) -> tuple[Path, Path, Path, Path]:
    repository = repository.resolve()
    if not (repository / ".git").exists():
        raise PathSafetyError("Repository does not contain .git")

    resolved = {
        "signed output root": strict_repository_child(
            output_root, repository, "signed output root"
        ),
        "signed work root": strict_repository_child(
            work_root, repository, "signed work root"
        ),
        "signed evidence root": strict_repository_child(
            evidence_root, repository, "signed evidence root"
        ),
    }
    items = list(resolved.items())
    for index, (first_label, first_path) in enumerate(items):
        for second_label, second_path in items[index + 1 :]:
            if paths_overlap(first_path, second_path):
                raise PathSafetyError(
                    f"{first_label} and {second_label} must be non-overlapping "
                    "repository children"
                )
    return (
        repository,
        resolved["signed output root"],
        resolved["signed work root"],
        resolved["signed evidence root"],
    )


def run_pipeline(args: argparse.Namespace) -> int:
    repository, output_root, work_root, evidence_root = validate_release_roots(
        args.repository,
        args.output_root,
        args.work_root,
        args.evidence_root,
    )
    implementation = repository / "scripts" / "sign_notarize_release.py"
    if not implementation.is_file() or implementation.is_symlink():
        raise PathSafetyError(
            "Signed-release implementation must be a regular repository file"
        )

    command: list[str] = [
        sys.executable,
        str(implementation),
        "run",
        "--repository",
        str(repository),
        "--version",
        args.version,
        "--build-number",
        args.build_number,
        "--expected-commit",
        args.expected_commit,
        "--identity",
        args.identity,
        "--team-id",
        args.team_id,
        "--api-key",
        str(args.api_key),
        "--key-id",
        args.key_id,
        "--issuer",
        args.issuer,
        "--authorization",
        args.authorization,
        "--output-root",
        str(output_root),
        "--work-root",
        str(work_root),
        "--evidence-root",
        str(evidence_root),
    ]
    if args.keep_work:
        command.append("--keep-work")
    result = subprocess.run(command, check=False, env=os.environ.copy())
    return int(result.returncode)


def expect_invalid(function) -> None:  # type: ignore[no-untyped-def]
    try:
        function()
    except PathSafetyError:
        return
    raise AssertionError("Expected unsafe signed-release paths to be rejected")


def self_test(_args: argparse.Namespace | None = None) -> int:
    with tempfile.TemporaryDirectory() as directory:
        repository = Path(directory) / "repo"
        repository.mkdir()
        (repository / ".git").mkdir()

        output_root = repository / "signed-dist"
        work_root = repository / "signed-release-work"
        evidence_root = repository / "signed-release-evidence"
        resolved = validate_release_roots(
            repository, output_root, work_root, evidence_root
        )
        assert resolved[1:] == (
            output_root.resolve(),
            work_root.resolve(),
            evidence_root.resolve(),
        )

        expect_invalid(
            lambda: validate_release_roots(
                repository, output_root, output_root, evidence_root
            )
        )
        expect_invalid(
            lambda: validate_release_roots(
                repository, output_root, output_root / "work", evidence_root
            )
        )
        expect_invalid(
            lambda: validate_release_roots(
                repository, output_root / "nested", output_root, evidence_root
            )
        )
        expect_invalid(
            lambda: validate_release_roots(
                repository, output_root, work_root, work_root / "evidence"
            )
        )
        expect_invalid(
            lambda: validate_release_roots(
                repository, repository, work_root, evidence_root
            )
        )
        expect_invalid(
            lambda: validate_release_roots(
                repository,
                Path(directory) / "outside",
                work_root,
                evidence_root,
            )
        )

        outside = Path(directory) / "outside-target"
        outside.mkdir()
        symlink = repository / "symlink-output"
        symlink.symlink_to(outside, target_is_directory=True)
        expect_invalid(
            lambda: validate_release_roots(
                repository, symlink, work_root, evidence_root
            )
        )

    print("Signed release entrypoint self-test passed")
    return 0


def add_run_arguments(parser: argparse.ArgumentParser) -> None:
    root = Path(__file__).resolve().parent.parent
    parser.add_argument("--repository", type=Path, default=root)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--api-key", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer", required=True)
    parser.add_argument("--authorization", required=True)
    parser.add_argument("--output-root", type=Path, default=root / "signed-dist")
    parser.add_argument(
        "--work-root", type=Path, default=root / "signed-release-work"
    )
    parser.add_argument(
        "--evidence-root", type=Path, default=root / "signed-release-evidence"
    )
    parser.add_argument("--keep-work", action="store_true")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    run_parser = commands.add_parser("run")
    add_run_arguments(run_parser)
    run_parser.set_defaults(function=run_pipeline)
    test_parser = commands.add_parser("self-test")
    test_parser.set_defaults(function=self_test)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return int(args.function(args))
    except PathSafetyError as error:
        fail(str(error))


if __name__ == "__main__":
    raise SystemExit(main())
