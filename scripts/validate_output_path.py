#!/usr/bin/env python3
"""Resolve and validate destructive-output paths used by MacVitals scripts."""

from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path


class PathSafetyError(ValueError):
    """Raised when an output path can escape or replace the repository root."""


def resolved(path: Path) -> Path:
    try:
        return path.expanduser().resolve(strict=False)
    except (OSError, RuntimeError) as error:
        raise PathSafetyError(f"Cannot resolve path {path}: {error}") from error


def validate_descendant(repository_root: Path, candidate: Path) -> Path:
    root = resolved(repository_root)
    expanded = candidate.expanduser()
    output = resolved(expanded if expanded.is_absolute() else root / expanded)
    if output == root:
        raise PathSafetyError("Output path must not equal the repository root")
    try:
        output.relative_to(root)
    except ValueError as error:
        raise PathSafetyError(
            f"Output path {output} must be a strict descendant of repository root {root}"
        ) from error
    return output


def expect_invalid(root: Path, candidate: Path, label: str) -> None:
    try:
        validate_descendant(root, candidate)
    except PathSafetyError:
        return
    raise PathSafetyError(f"Self-test did not reject {label}: {candidate}")


def run_self_test() -> None:
    with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
        root = Path(directory) / "repo"
        root.mkdir()
        safe = root / "build" / "nested"
        assert validate_descendant(root, safe) == safe.resolve(strict=False)
        assert validate_descendant(root / ".", root / "dist") == (root / "dist").resolve()
        assert validate_descendant(root, Path("relative-build")) == (root / "relative-build").resolve()
        assert validate_descendant(root, Path("--option-like")) == (root / "--option-like").resolve()

        expect_invalid(root, root, "repository root")
        expect_invalid(root, root.parent, "repository parent")
        expect_invalid(root, Path(outside), "outside directory")
        expect_invalid(root, root / ".." / "outside", "parent traversal")

        link = root / "linked-output"
        try:
            link.symlink_to(Path(outside), target_is_directory=True)
        except OSError:
            pass
        else:
            expect_invalid(root, link / "samples", "symlink escape")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--root", type=Path)
    parser.add_argument("--path", dest="candidate", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.self_test:
            run_self_test()
            print("Output path safety validator self-test passed")
            return 0
        if arguments.root is None or arguments.candidate is None:
            raise PathSafetyError("--root and --path are required")
        output = validate_descendant(arguments.root, arguments.candidate)
        print(os.fspath(output))
        return 0
    except PathSafetyError as error:
        print(f"Output path validation failed: {error}", file=__import__("sys").stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
