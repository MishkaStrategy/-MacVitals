#!/usr/bin/env python3
"""Require the reviewed XcodeGen version before project generation."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

EXPECTED_VERSION = "2.46.0"
_VERSION_RE = re.compile(r"(?:^|\b)(\d+\.\d+\.\d+)(?:\b|$)")


class VersionError(RuntimeError):
    pass


def parse_version(output: str) -> str:
    matches = _VERSION_RE.findall(output)
    if len(matches) != 1:
        raise VersionError(f"Could not parse exactly one XcodeGen version from {output!r}")
    return matches[0]


def resolve_binary(explicit: Path | None = None) -> Path:
    if explicit is not None:
        candidate = explicit.expanduser().resolve()
    else:
        found = shutil.which("xcodegen")
        if not found:
            raise VersionError("xcodegen is unavailable")
        candidate = Path(found).resolve()
    if not candidate.is_file() or candidate.is_symlink():
        raise VersionError(f"xcodegen path is not a regular executable: {candidate}")
    return candidate


def installed_version(binary: Path) -> str:
    result = subprocess.run(
        [str(binary), "--version"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise VersionError(f"xcodegen --version failed with exit {result.returncode}")
    return parse_version((result.stdout + "\n" + result.stderr).strip())


def verify(binary: Path) -> str:
    version = installed_version(binary)
    if version != EXPECTED_VERSION:
        raise VersionError(
            f"MacVitals requires reviewed XcodeGen {EXPECTED_VERSION}; found {version}"
        )
    return version


def self_test() -> None:
    assert parse_version("Version: 2.46.0") == "2.46.0"
    assert parse_version("XcodeGen 2.46.0\n") == "2.46.0"
    for invalid in ("", "Version unknown", "2.46", "2.46.0 and 2.47.0"):
        try:
            parse_version(invalid)
        except VersionError:
            pass
        else:
            raise AssertionError(f"Invalid XcodeGen version output was accepted: {invalid!r}")
    print("XcodeGen version verifier self-test passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        self_test()
        return 0
    try:
        binary = resolve_binary(args.binary)
        version = verify(binary)
    except VersionError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f"XcodeGen version verified: {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
