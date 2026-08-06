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
    re.compile(r"Contents/MacOS/MacVitals"),
    re.compile(r"(?:^|\s)(?:/usr/bin/)?open\s+-[A-Za-z]*n[A-Za-z]*a\b", re.MULTILINE),
    re.compile(r"subprocess\.Popen\(\[str\(executable\)"),
    re.compile(
        r"pgrep(?:\s+-[A-Za-z]+)*\s+[\"']?MacVitals[\"']?(?=\s|$)",
        re.MULTILINE,
    ),
    re.compile(r"matching_pid\(executable"),
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
PHYSICAL_EVIDENCE_MARKERS = (
    "run_ci_physical_validation_hardened.sh",
    "physical-validation-results",
)


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def is_runtime_launcher(text: str) -> bool:
    return any(pattern.search(text) for pattern in RUNTIME_PATTERNS)


def uses_canonical_physical_evidence(text: str) -> bool:
    return all(marker in text for marker in PHYSICAL_EVIDENCE_MARKERS)


def validate_text(path: Path, text: str) -> list[str]:
    if not is_runtime_launcher(text):
        return []
    physical_evidence = uses_canonical_physical_evidence(text)
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

    collected_only = direct_launch + "\nbash scripts/collect_runtime_metrics.sh 60 2\n"
    errors = validate_text(Path("missing-report.sh"), collected_only)
    assert len(errors) == 1 and "runtime resource evidence" in errors[0], errors

    compliant = collected_only + "\npython3 scripts/report_runtime_resources.py summary.json\n"
    assert validate_text(Path("good.sh"), compliant) == []

    wrapper = "bash scripts/run_ci_runtime_smoke.sh MacVitals.app"
    assert validate_text(Path("workflow.yml"), wrapper) == []

    incomplete_physical = direct_launch + "\nbash scripts/run_ci_physical_validation_hardened.sh\n"
    assert len(validate_text(Path("incomplete-physical.sh"), incomplete_physical)) == 2

    physical = incomplete_physical + "\npath: physical-validation-results/\n"
    assert uses_canonical_physical_evidence(physical)
    assert validate_text(Path("physical.yml"), physical) == []

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
