#!/usr/bin/env python3
"""Defense-in-depth identity checks for MacVitals runtime evidence."""

from __future__ import annotations

import json

import validate_runtime_metrics as base

_original_validate = base.validate
_original_self_test = base.self_test


def validate(summary: dict[str, object], limits: base.Limits) -> list[str]:
    failures = list(_original_validate(summary, limits))
    try:
        architecture = base.nonempty_string(
            base.nested(summary, "environment", "architecture"),
            "environment.architecture",
        )
        expected_executable = base.nonempty_string(
            base.nested(summary, "process", "expectedExecutableName"),
            "process.expectedExecutableName",
        )
        executable_name = base.nonempty_string(
            base.nested(summary, "process", "executableName"),
            "process.executableName",
        )
        process_name = base.nonempty_string(
            base.nested(summary, "process", "name"),
            "process.name",
        )
    except ValueError as error:
        failures.append(str(error))
        return failures

    if architecture != "arm64":
        failures.append(
            f"Expected native arm64 runtime environment, found {architecture!r}"
        )
    if expected_executable != "MacVitals":
        failures.append(
            "Expected executable identity MacVitals, "
            f"found {expected_executable!r}"
        )
    if executable_name != expected_executable or process_name != expected_executable:
        failures.append(
            "Runtime process name, observed executable and expected executable "
            "must all match MacVitals"
        )
    return failures


def self_test() -> None:
    base.validate = _original_validate
    try:
        _original_self_test()
    finally:
        base.validate = validate

    passing = {
        "schemaVersion": 3,
        "process": {
            "name": "MacVitals",
            "pidAtStart": 4242,
            "uidAtStart": 501,
            "startedAt": "Fri Jul 24 10:11:12 2026",
            "executableName": "MacVitals",
            "expectedExecutableName": "MacVitals",
            "identityTokenSha256": "a" * 64,
            "identityStable": True,
            "aliveAtEnd": True,
            "selectionMode": "explicit-pid",
        },
        "requested": {"durationSeconds": 45, "intervalSeconds": 2},
        "observed": {
            "clock": "monotonic",
            "sampleSource": "locale-fixed-single-ps-snapshot",
            "durationSeconds": 45,
            "firstSampleElapsedSeconds": 0.1,
            "lastSampleElapsedSeconds": 44.1,
            "sampleCount": 22,
            "sampleIntervalSeconds": {"p95": 3},
        },
        "environment": {"architecture": "arm64"},
        "metrics": {
            "cpuPercent": {"mean": 2, "p95": 10},
            "residentMemoryKiB": {"max": 100_000, "growth": 2_000},
            "threads": {"max": 12},
        },
    }
    assert validate(passing, base.Limits()) == []

    wrong_architecture = json.loads(json.dumps(passing))
    wrong_architecture["environment"]["architecture"] = "x86_64"
    assert any("arm64" in failure for failure in validate(wrong_architecture, base.Limits()))

    missing_expected = json.loads(json.dumps(passing))
    del missing_expected["process"]["expectedExecutableName"]
    assert any(
        "expectedExecutableName" in failure
        for failure in validate(missing_expected, base.Limits())
    )

    mismatched_expected = json.loads(json.dumps(passing))
    mismatched_expected["process"]["expectedExecutableName"] = "OtherApp"
    assert any(
        "executable identity" in failure
        for failure in validate(mismatched_expected, base.Limits())
    )
    print("Hardened runtime metrics validator self-test passed")


base.validate = validate
base.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(base.main())
