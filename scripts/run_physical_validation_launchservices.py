#!/usr/bin/env python3
"""Launch MacVitals through same-user LaunchServices for physical CI validation."""

from __future__ import annotations

import argparse
import time
from pathlib import Path

import run_physical_validation_hardened as hardened

base = hardened.base
_original_hardened_self_test = hardened.self_test


def _require_delegated_hardened_runner_contract() -> None:
    """Refuse to launch unless the delegated hardened physical wrapper retains its safety contract."""
    wrapper = Path(__file__).resolve().with_name("run_ci_physical_validation_hardened.sh")
    if not wrapper.is_file() or wrapper.is_symlink():
        raise base.ValidationError("Canonical hardened physical wrapper is missing or unsafe")
    text = wrapper.read_text(encoding="utf-8")
    for marker in (
        "run_ci_physical_validation.sh",
        "run_physical_validation_hardened.py",
        "candidate_pid_is_owned",
        'GITHUB_SHA="${EXPECTED_SHA}"',
    ):
        if marker not in text:
            raise base.ValidationError(
                f"Canonical hardened physical wrapper contract is missing: {marker}"
            )


def _application_for_executable(executable: Path) -> Path:
    resolved = executable.resolve()
    try:
        application = resolved.parents[2]
    except IndexError as error:
        raise base.ValidationError("MacVitals executable path is incomplete") from error
    if application.suffix != ".app" or application.name != "MacVitals.app":
        raise base.ValidationError("MacVitals executable is not inside MacVitals.app")
    expected = application / "Contents" / "MacOS" / "MacVitals"
    if resolved != expected.resolve():
        raise base.ValidationError("MacVitals executable resolves outside the expected app path")
    return application


def _exact_matching_pids(executable: Path) -> list[int]:
    matches: list[int] = []
    for raw in base.output("pgrep", "-x", "MacVitals").splitlines():
        value = raw.strip()
        if not value.isdigit():
            continue
        pid = int(value)
        if hardened._pid_matches_executable(pid, executable):
            matches.append(pid)
    return sorted(set(matches))


def matching_pid(executable: Path, warmup: float) -> tuple[int, bool]:
    """Launch through LaunchServices, then bind ownership to the exact executable PID."""
    existing = _exact_matching_pids(executable)
    if len(existing) > 1:
        raise base.ValidationError("Multiple matching MacVitals processes are running")
    if existing:
        return existing[0], False

    _require_delegated_hardened_runner_contract()
    application = _application_for_executable(executable)
    started = time.monotonic()
    launched = base.command(
        "open",
        "-na",
        str(application),
        "--args",
        "-notificationsEnabled",
        "NO",
        "-showInDock",
        "NO",
    )
    if launched.returncode != 0:
        details = base.redact(launched.stdout + launched.stderr).strip()
        suffix = f": {details}" if details else ""
        raise base.ValidationError(f"LaunchServices could not start MacVitals{suffix}")

    startup_deadline = started + max(10.0, warmup)
    pid: int | None = None
    while time.monotonic() < startup_deadline:
        matches = _exact_matching_pids(executable)
        if len(matches) > 1:
            raise base.ValidationError("Multiple exact MacVitals processes appeared after launch")
        if matches:
            pid = matches[0]
            break
        time.sleep(0.25)
    if pid is None:
        raise base.ValidationError("LaunchServices did not produce the exact MacVitals executable")

    warmup_deadline = started + max(0.0, warmup)
    while time.monotonic() < warmup_deadline:
        if not hardened._pid_matches_executable(pid, executable):
            raise base.ValidationError("MacVitals exited during LaunchServices validation startup")
        time.sleep(min(0.25, max(0.0, warmup_deadline - time.monotonic())))
    if not hardened._pid_matches_executable(pid, executable):
        raise base.ValidationError("MacVitals is not alive after LaunchServices validation startup")

    hardened._owned_process_executables[pid] = executable.resolve()
    return pid, True


def self_test(args: argparse.Namespace | None = None) -> int:
    result = _original_hardened_self_test(args)
    base.matching_pid = matching_pid

    _require_delegated_hardened_runner_contract()
    fixture = Path("/tmp/MacVitals.app/Contents/MacOS/MacVitals")
    assert _application_for_executable(fixture) == Path("/tmp/MacVitals.app").resolve()
    try:
        _application_for_executable(Path("/tmp/not-an-app/MacVitals"))
    except base.ValidationError:
        pass
    else:
        raise AssertionError("non-app executable path unexpectedly passed")
    assert base.matching_pid is matching_pid
    assert base.terminate is hardened.terminate
    print("LaunchServices physical adapter self-test passed")
    return result


base.matching_pid = matching_pid
base.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(base.main())
