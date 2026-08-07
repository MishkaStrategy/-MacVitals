#!/usr/bin/env python3
"""Fail closed when changed runtime tests omit MacVitals CPU/RSS evidence."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

RUNTIME_SUFFIXES = {".yml", ".yaml", ".sh", ".py"}
RUNTIME_PATTERNS = (
    re.compile(
        r"(?m)^\s*(?:[A-Za-z_][A-Za-z0-9_]*=[^\n ]+\s+)*"
        r"(?:[\"'][^\"'\n]*Contents/MacOS/MacVitals[\"']|"
        r"[^\s#]*Contents/MacOS/MacVitals)(?=\s|$)"
    ),
    re.compile(r"(?:^|\s)(?:/usr/bin/)?open\s+-[A-Za-z]*n[A-Za-z]*a\b", re.MULTILINE),
    re.compile(r"subprocess\.Popen\(\[str\(executable\)"),
    re.compile(
        r"pgrep(?:\s+-[A-Za-z]+)*\s+[\"']?MacVitals[\"']?(?=\s|$)",
        re.MULTILINE,
    ),
    re.compile(r"matching_pid\(executable"),
)
SHELL_EXECUTABLE_ASSIGNMENT = re.compile(
    r"(?m)^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)="
    r"(?:[\"'][^\"'\n]*Contents/MacOS/MacVitals[\"']|[^\s#]*Contents/MacOS/MacVitals)\s*$"
)
COLLECTOR_MARKERS = (
    "collect_runtime_metrics.sh",
    "collect_runtime_metrics.py",
    "run_ci_runtime_smoke.sh",
)
REPORTER_MARKERS = (
    "report_runtime_resources.py",
    "MACVITALS_RESOURCE_SUMMARY",
)
CANONICAL_SAFE_PHYSICAL_WRAPPER = Path("scripts/run_safe_physical_validation.sh")
SAFE_PHYSICAL_EVIDENCE_MARKERS = (
    "run_ci_physical_validation_hardened.sh",
    "physical-validation-results",
)
CANONICAL_HARDENED_PHYSICAL_WRAPPER = Path("scripts/run_ci_physical_validation_hardened.sh")
HARDENED_PHYSICAL_WRAPPER_MARKERS = (
    "run_ci_physical_validation.sh",
    "run_physical_validation_hardened.py",
    "candidate_pid_is_owned",
    'GITHUB_SHA="${EXPECTED_SHA}"',
)
CANONICAL_HARDENED_PHYSICAL_HARNESS = Path("scripts/run_physical_validation_hardened.py")
HARDENED_PHYSICAL_HARNESS_MARKERS = (
    "import run_physical_validation as base",
    "_original_run_scenario = base.run_scenario",
    "base.matching_pid = matching_pid",
    "base.terminate = terminate",
    "_completion_failures",
)
TARGETED_LAUNCHSERVICES_PHYSICAL_HARNESS = Path(
    "scripts/run_physical_validation_launchservices.py"
)
TARGETED_LAUNCHSERVICES_HARNESS_MARKERS = (
    "import run_physical_validation_hardened as hardened",
    "def host_snapshot()",
    "return base.host_snapshot()",
    "def power_snapshot(",
    "return hardened.power_snapshot(started)",
    "_require_delegated_hardened_runner_contract",
    "base.matching_pid = matching_pid",
    "hardened._owned_process_executables[pid]",
    '"open",',
    '"-na",',
    "base.terminate is hardened.terminate",
)


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def shell_variable_is_executed(text: str, variable: str) -> bool:
    escaped = re.escape(variable)
    command = re.compile(
        rf"(?m)^\s*(?:[A-Za-z_][A-Za-z0-9_]*=[^\n ]+\s+)*"
        rf"(?:\"\${{{escaped}}}\"|\"\${escaped}\"|\${{{escaped}}}|\${escaped})(?=\s|$)"
    )
    return command.search(text) is not None


def is_runtime_launcher(text: str) -> bool:
    if any(pattern.search(text) for pattern in RUNTIME_PATTERNS):
        return True
    return any(
        shell_variable_is_executed(text, match.group(1))
        for match in SHELL_EXECUTABLE_ASSIGNMENT.finditer(text)
    )


def uses_canonical_physical_evidence(path: Path, text: str) -> bool:
    if path == CANONICAL_SAFE_PHYSICAL_WRAPPER:
        return all(marker in text for marker in SAFE_PHYSICAL_EVIDENCE_MARKERS)
    if path == CANONICAL_HARDENED_PHYSICAL_WRAPPER:
        return all(marker in text for marker in HARDENED_PHYSICAL_WRAPPER_MARKERS)
    if path == CANONICAL_HARDENED_PHYSICAL_HARNESS:
        return all(marker in text for marker in HARDENED_PHYSICAL_HARNESS_MARKERS)
    if path == TARGETED_LAUNCHSERVICES_PHYSICAL_HARNESS:
        return all(marker in text for marker in TARGETED_LAUNCHSERVICES_HARNESS_MARKERS)
    return False


def validate_text(path: Path, text: str) -> list[str]:
    if not is_runtime_launcher(text):
        return []
    physical_evidence = uses_canonical_physical_evidence(path, text)
    errors: list[str] = []
    if not physical_evidence and not any(marker in text for marker in COLLECTOR_MARKERS):
        errors.append(
            f"{path}: launches MacVitals but does not invoke the canonical runtime metrics collector"
        )
    if not physical_evidence and not any(marker in text for marker in REPORTER_MARKERS):
        errors.append(
            f"{path}: launches MacVitals but does not emit canonical runtime resource evidence"
        )
    return errors


def changed_paths(base_ref: str) -> list[Path]:
    result = subprocess.run(
        [
            "git",
            "diff",
            "--name-only",
            "--diff-filter=ACMR",
            f"{base_ref}...HEAD",
            "--",
            ".github/workflows",
            "scripts",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail("Could not determine changed runtime-test files: " + result.stderr.strip())
    return [Path(line.strip()) for line in result.stdout.splitlines() if line.strip()]


def validate(paths: list[Path]) -> list[str]:
    errors: list[str] = []
    for path in sorted(set(paths)):
        if path.suffix not in RUNTIME_SUFFIXES or not path.is_file() or path.is_symlink():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            errors.append(f"{path}: runtime policy file is not UTF-8")
            continue
        errors.extend(validate_text(path, text))
    return errors


def self_test() -> None:
    direct_launch = """
    executable="$app/Contents/MacOS/MacVitals"
    "$executable" > app.log 2>&1 &
    """
    errors = validate_text(Path("missing.sh"), direct_launch)
    assert len(errors) == 2, errors

    literal_launch = '"$app/Contents/MacOS/MacVitals" -showInDock NO > app.log 2>&1 &\n'
    assert is_runtime_launcher(literal_launch)
    assert len(validate_text(Path("literal-launch.sh"), literal_launch)) == 2

    verification_only = """
    EXECUTABLE="${ZIP_APP}/Contents/MacOS/MacVitals"
    architectures="$(lipo -archs "${EXECUTABLE}")"
    codesign --verify --deep --strict "${ZIP_APP}"
    """
    assert not is_runtime_launcher(verification_only)
    assert validate_text(Path("verify_release.sh"), verification_only) == []

    collected_only = direct_launch + "\nbash scripts/collect_runtime_metrics.sh 60 2\n"
    errors = validate_text(Path("missing-report.sh"), collected_only)
    assert len(errors) == 1 and "runtime resource evidence" in errors[0], errors

    compliant = collected_only + "\npython3 scripts/report_runtime_resources.py summary.json\n"
    assert validate_text(Path("good.sh"), compliant) == []

    wrapper = "bash scripts/run_ci_runtime_smoke.sh MacVitals.app"
    assert validate_text(Path("workflow.yml"), wrapper) == []

    incomplete_safe_physical = direct_launch + "\nbash scripts/run_ci_physical_validation_hardened.sh\n"
    assert len(validate_text(CANONICAL_SAFE_PHYSICAL_WRAPPER, incomplete_safe_physical)) == 2

    safe_physical = incomplete_safe_physical + "\npath: physical-validation-results/\n"
    assert uses_canonical_physical_evidence(CANONICAL_SAFE_PHYSICAL_WRAPPER, safe_physical)
    assert validate_text(CANONICAL_SAFE_PHYSICAL_WRAPPER, safe_physical) == []

    safe_lookalike = Path("scripts/not-the-canonical-wrapper.sh")
    assert not uses_canonical_physical_evidence(safe_lookalike, safe_physical)
    assert len(validate_text(safe_lookalike, safe_physical)) == 2

    hardened_wrapper = """
    ORIGINAL="${SCRIPT_DIR}/run_ci_physical_validation.sh"
    HARDENED="${SCRIPT_DIR}/run_physical_validation_hardened.py"
    candidate_pid_is_owned() { pgrep -x MacVitals >/dev/null; }
    GITHUB_SHA="${EXPECTED_SHA}" bash "${TEMP_RUNNER}" "$@"
    """
    assert is_runtime_launcher(hardened_wrapper)
    assert uses_canonical_physical_evidence(
        CANONICAL_HARDENED_PHYSICAL_WRAPPER, hardened_wrapper
    )
    assert validate_text(CANONICAL_HARDENED_PHYSICAL_WRAPPER, hardened_wrapper) == []

    hardened_wrapper_lookalike = Path("scripts/not-the-hardened-physical-wrapper.sh")
    assert not uses_canonical_physical_evidence(hardened_wrapper_lookalike, hardened_wrapper)
    assert len(validate_text(hardened_wrapper_lookalike, hardened_wrapper)) == 2

    incomplete_wrapper = hardened_wrapper.replace("candidate_pid_is_owned", "pid_is_owned")
    assert not uses_canonical_physical_evidence(
        CANONICAL_HARDENED_PHYSICAL_WRAPPER, incomplete_wrapper
    )
    assert len(validate_text(CANONICAL_HARDENED_PHYSICAL_WRAPPER, incomplete_wrapper)) == 2

    hardened_harness = """
    import run_physical_validation as base
    _original_run_scenario = base.run_scenario
    def matching_pid(executable, warmup):
        return 1, True
    def terminate(pid):
        return None
    base.matching_pid = matching_pid
    base.terminate = terminate
    def _completion_failures(record, summary):
        return []
    """
    assert is_runtime_launcher(hardened_harness)
    assert uses_canonical_physical_evidence(
        CANONICAL_HARDENED_PHYSICAL_HARNESS, hardened_harness
    )
    assert validate_text(CANONICAL_HARDENED_PHYSICAL_HARNESS, hardened_harness) == []

    hardened_harness_lookalike = Path("scripts/not-the-hardened-physical-harness.py")
    assert not uses_canonical_physical_evidence(hardened_harness_lookalike, hardened_harness)
    assert len(validate_text(hardened_harness_lookalike, hardened_harness)) == 2

    incomplete_harness = hardened_harness.replace(
        "base.terminate = terminate", "base.terminate = base.terminate"
    )
    assert not uses_canonical_physical_evidence(
        CANONICAL_HARDENED_PHYSICAL_HARNESS, incomplete_harness
    )
    assert len(validate_text(CANONICAL_HARDENED_PHYSICAL_HARNESS, incomplete_harness)) == 2

    launchservices_harness = """
    import run_physical_validation_hardened as hardened
    def host_snapshot():
        return base.host_snapshot()
    def power_snapshot(started=None):
        return hardened.power_snapshot(started)
    def _require_delegated_hardened_runner_contract():
        return None
    def matching_pid(executable, warmup):
        launched = base.command("open", "-na", str(application))
        hardened._owned_process_executables[pid] = executable.resolve()
        return pid, True
    base.matching_pid = matching_pid
    assert base.terminate is hardened.terminate
    """
    assert is_runtime_launcher(launchservices_harness)
    assert uses_canonical_physical_evidence(
        TARGETED_LAUNCHSERVICES_PHYSICAL_HARNESS, launchservices_harness
    )
    assert validate_text(
        TARGETED_LAUNCHSERVICES_PHYSICAL_HARNESS, launchservices_harness
    ) == []

    launchservices_lookalike = Path("scripts/not-the-launchservices-physical-harness.py")
    assert not uses_canonical_physical_evidence(launchservices_lookalike, launchservices_harness)
    assert len(validate_text(launchservices_lookalike, launchservices_harness)) == 2

    incomplete_launchservices = launchservices_harness.replace(
        "hardened._owned_process_executables[pid]", "owned_processes[pid]"
    )
    assert not uses_canonical_physical_evidence(
        TARGETED_LAUNCHSERVICES_PHYSICAL_HARNESS, incomplete_launchservices
    )
    assert len(
        validate_text(TARGETED_LAUNCHSERVICES_PHYSICAL_HARNESS, incomplete_launchservices)
    ) == 2

    missing_module_api = launchservices_harness.replace(
        "return hardened.power_snapshot(started)", "return {}"
    )
    assert not uses_canonical_physical_evidence(
        TARGETED_LAUNCHSERVICES_PHYSICAL_HARNESS, missing_module_api
    )
    assert len(
        validate_text(TARGETED_LAUNCHSERVICES_PHYSICAL_HARNESS, missing_module_api)
    ) == 2

    exact_process_probe = "pgrep -x MacVitals"
    assert is_runtime_launcher(exact_process_probe)

    ui_runner_probe = "pgrep -x MacVitalsUITests-Runner"
    assert not is_runtime_launcher(ui_runner_probe)
    assert validate_text(Path("ui-compile.yml"), ui_runner_probe) == []

    unit_only = "xcodebuild test -only-testing:MacVitalsTests"
    assert validate_text(Path("unit.yml"), unit_only) == []
    assert validate([]) == []
    print("Runtime resource policy self-test passed")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("paths", nargs="*", type=Path)
    result.add_argument("--base-ref")
    result.add_argument("--self-test", action="store_true")
    return result


def main() -> int:
    args = parser().parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.paths and not args.base_ref:
        fail("Provide paths or --base-ref")

    paths = list(args.paths)
    if args.base_ref:
        paths.extend(changed_paths(args.base_ref))

    errors = validate(paths)
    if errors:
        print("Runtime resource evidence policy failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"Runtime resource evidence policy passed for {len(set(paths))} changed paths")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
