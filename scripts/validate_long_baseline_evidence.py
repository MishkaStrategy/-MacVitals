#!/usr/bin/env python3
"""Validate provenance and completeness of exact long-idle baseline evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Any, Callable


class EvidenceValidationError(RuntimeError):
    """Raised when an evidence bundle violates the replay contract."""


def _read_json(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise EvidenceValidationError(f"missing or unsafe JSON file: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceValidationError(f"invalid JSON file {path}: {error}") from error
    if not isinstance(payload, dict):
        raise EvidenceValidationError(f"JSON root must be an object: {path}")
    return payload


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_manifest_path(root: Path, raw_path: object) -> Path:
    if not isinstance(raw_path, str) or not raw_path:
        raise EvidenceValidationError("manifest path must be a non-empty string")
    relative = Path(raw_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise EvidenceValidationError(f"unsafe manifest path: {raw_path}")
    candidate = root / relative
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise EvidenceValidationError(f"manifest path escapes bundle: {raw_path}") from error
    if not candidate.is_file() or candidate.is_symlink():
        raise EvidenceValidationError(f"missing or unsafe staged file: {raw_path}")
    return candidate


def validate_bundle(
    root: Path,
    expected_source_sha: str,
    expected_run_id: str,
    expected_runner: str,
) -> int:
    if root.is_symlink():
        raise EvidenceValidationError(f"bundle root must not be a symlink: {root}")
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise EvidenceValidationError(f"bundle root is not a directory: {root}")
    if len(expected_source_sha) != 40 or any(
        character not in "0123456789abcdefABCDEF" for character in expected_source_sha
    ):
        raise EvidenceValidationError("expected source SHA must contain exactly 40 hex characters")

    manifest = _read_json(root / "recovery-manifest.json")
    if manifest.get("schemaVersion") != 1:
        raise EvidenceValidationError("unsupported recovery manifest schema")
    if manifest.get("sourceSha") != expected_source_sha:
        raise EvidenceValidationError("recovery source SHA mismatch")
    if str(manifest.get("sourceWorkflowRunId")) != expected_run_id:
        raise EvidenceValidationError("recovery workflow run mismatch")
    if manifest.get("sourceRunnerName") != expected_runner:
        raise EvidenceValidationError("recovery runner mismatch")

    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        raise EvidenceValidationError("recovery manifest contains no evidence files")

    seen_paths: set[str] = set()
    for entry in files:
        if not isinstance(entry, dict):
            raise EvidenceValidationError("manifest file entry must be an object")
        raw_path = entry.get("path")
        if not isinstance(raw_path, str) or raw_path in seen_paths:
            raise EvidenceValidationError(f"duplicate or invalid manifest path: {raw_path}")
        seen_paths.add(raw_path)
        path = _safe_manifest_path(root, raw_path)
        try:
            expected_bytes = int(entry["bytes"])
            expected_digest = str(entry["sha256"])
        except (KeyError, TypeError, ValueError) as error:
            raise EvidenceValidationError(f"invalid manifest metadata: {raw_path}") from error
        if expected_bytes < 0 or path.stat().st_size != expected_bytes:
            raise EvidenceValidationError(f"size mismatch: {raw_path}")
        if len(expected_digest) != 64 or _sha256(path) != expected_digest:
            raise EvidenceValidationError(f"digest mismatch: {raw_path}")

    actual_paths = {
        str(path.relative_to(root))
        for path in root.rglob("*")
        if path.is_file() and path.name != "recovery-manifest.json"
    }
    if actual_paths != seen_paths:
        missing = sorted(actual_paths - seen_paths)
        unexpected = sorted(seen_paths - actual_paths)
        raise EvidenceValidationError(
            "manifest file list mismatch: "
            f"unlisted={missing or 'none'} missing={unexpected or 'none'}"
        )

    results = root / "long-idle-baseline-results"
    scenario = _read_json(results / "scenario.json")
    aggregate = _read_json(results / "aggregate-summary.json")
    if scenario.get("sourceSha") != expected_source_sha:
        raise EvidenceValidationError("scenario source SHA mismatch")
    if aggregate.get("sourceSha") != expected_source_sha:
        raise EvidenceValidationError("aggregate source SHA mismatch")
    if int(aggregate.get("runCount", 0)) != 3:
        raise EvidenceValidationError("aggregate run count is not 3")

    for run_number in range(1, 4):
        run_root = results / f"run-{run_number}"
        resource = _read_json(run_root / "resource-summary.json")
        provider = _read_json(run_root / "provider-summary.json")
        timings = run_root / "provider-timings.jsonl"
        if not timings.is_file() or timings.is_symlink() or timings.stat().st_size == 0:
            raise EvidenceValidationError(f"run {run_number}: provider records are missing")
        if resource.get("sourceSha") != expected_source_sha:
            raise EvidenceValidationError(f"run {run_number}: resource source SHA mismatch")

        measurement = resource.get("measurement")
        if not isinstance(measurement, dict) or int(measurement.get("sampleCount", 0)) < 900:
            raise EvidenceValidationError(f"run {run_number}: insufficient process samples")
        process = resource.get("process")
        if not isinstance(process, dict) or process.get("aliveAtEnd") is not True:
            raise EvidenceValidationError(f"run {run_number}: app was not alive at end")
        if process.get("identityStable") is not True:
            raise EvidenceValidationError(f"run {run_number}: PID identity was not stable")

        records = int(provider.get("records", provider.get("cycleCount", 0)))
        if records <= 0:
            raise EvidenceValidationError(f"run {run_number}: no provider records")
        coverage = float(provider.get("observed_duration_s", 0))
        if coverage < 1800:
            raise EvidenceValidationError(
                f"run {run_number}: provider coverage {coverage:.3f}s < 1800s"
            )

    return len(files)


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _stage_fixture(
    root: Path,
    source_sha: str,
    run_id: str,
    runner: str,
    mutate: Callable[[Path], None] | None = None,
) -> None:
    results = root / "long-idle-baseline-results"
    _write_json(results / "scenario.json", {"sourceSha": source_sha})
    _write_json(results / "aggregate-summary.json", {"sourceSha": source_sha, "runCount": 3})
    for run_number in range(1, 4):
        run_root = results / f"run-{run_number}"
        _write_json(
            run_root / "resource-summary.json",
            {
                "sourceSha": source_sha,
                "measurement": {"sampleCount": 900},
                "process": {"aliveAtEnd": True, "identityStable": True},
            },
        )
        _write_json(
            run_root / "provider-summary.json",
            {"records": 900, "observed_duration_s": 1800.0},
        )
        (run_root / "provider-timings.jsonl").write_text('{"total_ms":1.0}\n', encoding="utf-8")
    (root / "long-idle-baseline.log").write_text("fixture\n", encoding="utf-8")

    if mutate is not None:
        mutate(root)

    files = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.name != "recovery-manifest.json":
            files.append(
                {
                    "path": str(path.relative_to(root)),
                    "bytes": path.stat().st_size,
                    "sha256": _sha256(path),
                }
            )
    _write_json(
        root / "recovery-manifest.json",
        {
            "schemaVersion": 1,
            "sourceSha": source_sha,
            "sourceWorkflowRunId": run_id,
            "sourceRunnerName": runner,
            "files": files,
        },
    )


def self_test() -> None:
    source_sha = "1" * 40
    run_id = "123456"
    runner = "self-test-runner"

    def expect_rejected(name: str, prepare: Callable[[Path], None]) -> None:
        with tempfile.TemporaryDirectory(prefix="macvitals-long-baseline-test-") as temporary:
            root = Path(temporary) / "bundle"
            root.mkdir()
            prepare(root)
            try:
                validate_bundle(root, source_sha, run_id, runner)
            except EvidenceValidationError:
                return
            raise AssertionError(f"{name} fixture unexpectedly passed validation")

    with tempfile.TemporaryDirectory(prefix="macvitals-long-baseline-test-") as temporary:
        root = Path(temporary) / "bundle"
        root.mkdir()
        _stage_fixture(root, source_sha, run_id, runner)
        validate_bundle(root, source_sha, run_id, runner)

    def digest_tamper(root: Path) -> None:
        _stage_fixture(root, source_sha, run_id, runner)
        with (root / "long-idle-baseline.log").open("a", encoding="utf-8") as handle:
            handle.write("tampered\n")

    expect_rejected("digest tamper", digest_tamper)

    def semantic_fixture(mutator: Callable[[Path], None]) -> Callable[[Path], None]:
        return lambda root: _stage_fixture(root, source_sha, run_id, runner, mutator)

    expect_rejected(
        "899 samples",
        semantic_fixture(
            lambda root: _write_json(
                root / "long-idle-baseline-results/run-1/resource-summary.json",
                {
                    "sourceSha": source_sha,
                    "measurement": {"sampleCount": 899},
                    "process": {"aliveAtEnd": True, "identityStable": True},
                },
            )
        ),
    )
    expect_rejected(
        "1799.9 second coverage",
        semantic_fixture(
            lambda root: _write_json(
                root / "long-idle-baseline-results/run-1/provider-summary.json",
                {"records": 900, "observed_duration_s": 1799.9},
            )
        ),
    )
    expect_rejected(
        "unstable PID",
        semantic_fixture(
            lambda root: _write_json(
                root / "long-idle-baseline-results/run-1/resource-summary.json",
                {
                    "sourceSha": source_sha,
                    "measurement": {"sampleCount": 900},
                    "process": {"aliveAtEnd": True, "identityStable": False},
                },
            )
        ),
    )
    expect_rejected(
        "wrong source SHA",
        lambda root: _stage_fixture(root, "2" * 40, run_id, runner),
    )

    def remove_provider_records(root: Path) -> None:
        (root / "long-idle-baseline-results/run-1/provider-timings.jsonl").unlink()

    expect_rejected(
        "missing provider records",
        semantic_fixture(remove_provider_records),
    )

    print("Long-baseline evidence validator self-test passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path)
    parser.add_argument("--expected-source-sha")
    parser.add_argument("--expected-run-id")
    parser.add_argument("--expected-runner")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.root is None:
        raise SystemExit("bundle root is required")
    for name, value in (
        ("--expected-source-sha", args.expected_source_sha),
        ("--expected-run-id", args.expected_run_id),
        ("--expected-runner", args.expected_runner),
    ):
        if not value:
            raise SystemExit(f"{name} is required")
    try:
        file_count = validate_bundle(
            args.root,
            args.expected_source_sha,
            args.expected_run_id,
            args.expected_runner,
        )
    except (EvidenceValidationError, OSError, TypeError, ValueError) as error:
        raise SystemExit(str(error)) from error
    print(
        "MACVITALS_RECOVERY_VERIFIED "
        f"source_sha={args.expected_source_sha} "
        f"source_run_id={args.expected_run_id} "
        f"runner={args.expected_runner} files={file_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
