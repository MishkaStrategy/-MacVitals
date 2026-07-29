#!/usr/bin/env python3
"""Route the guided physical validation UI through the hardened harness."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

import run_physical_validation_guided as guide

_original_run = guide.run
_original_self_test = guide.self_test


def _redirected_command(command: Sequence[str]) -> list[str]:
    values = list(command)
    if len(values) < 2:
        return values
    candidate = Path(values[1])
    if candidate.name != "run_physical_validation.py":
        return values
    hardened = candidate.with_name("run_physical_validation_hardened.py")
    if not hardened.is_file() or hardened.is_symlink():
        raise guide.GuideError("Hardened physical validation harness is missing or unsafe")
    values[1] = str(hardened)
    return values


def run(
    command: Sequence[str],
    *,
    capture: bool = False,
    env: dict[str, str] | None = None,
):  # type: ignore[no-untyped-def]
    return _original_run(_redirected_command(command), capture=capture, env=env)


def self_test(_args_value: argparse.Namespace | None = None) -> int:
    _original_self_test(None)
    root = Path(__file__).resolve().parent
    original = root / "run_physical_validation.py"
    redirected = _redirected_command(["python3", str(original), "self-test"])
    assert Path(redirected[1]).name == "run_physical_validation_hardened.py"
    assert redirected[0] == "python3"
    assert redirected[2] == "self-test"
    assert _redirected_command(["uname", "-m"]) == ["uname", "-m"]
    print("Hardened guided physical validation self-test passed")
    return 0


guide.run = run
guide.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(guide.main())
