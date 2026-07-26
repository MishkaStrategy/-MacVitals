#!/usr/bin/env python3
"""Resource-limit hardening for downloaded physical workflow artifacts."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import prepare_physical_artifact as base

MAX_OUTER_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_MEMBER_UNCOMPRESSED_BYTES = 768 * 1024 * 1024
MAX_TOTAL_UNCOMPRESSED_BYTES = 1024 * 1024 * 1024
MAX_TOTAL_COMPRESSED_BYTES = 512 * 1024 * 1024
MAX_COMPRESSION_RATIO = 100.0
RATIO_CHECK_MINIMUM_BYTES = 1024 * 1024

_original_validated_members = base.validated_members
_original_extract_validated = base.extract_validated
_original_self_test = base.self_test


def _validate_resource_limits(infos: list[zipfile.ZipInfo]) -> None:
    total_uncompressed = 0
    total_compressed = 0
    for info in infos:
        if info.file_size < 0 or info.compress_size < 0:
            raise base.ArtifactError(f"Artifact member has an invalid size: {info.filename}")
        if info.file_size > MAX_MEMBER_UNCOMPRESSED_BYTES:
            raise base.ArtifactError(
                f"Artifact member exceeds the uncompressed size limit: {info.filename}"
            )
        total_uncompressed += info.file_size
        total_compressed += info.compress_size
        if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES:
            raise base.ArtifactError("Workflow artifact exceeds the total uncompressed size limit")
        if total_compressed > MAX_TOTAL_COMPRESSED_BYTES:
            raise base.ArtifactError("Workflow artifact exceeds the total compressed size limit")
        if info.file_size >= RATIO_CHECK_MINIMUM_BYTES:
            if info.compress_size == 0:
                raise base.ArtifactError(
                    f"Artifact member has an unsafe compression ratio: {info.filename}"
                )
            ratio = info.file_size / info.compress_size
            if ratio > MAX_COMPRESSION_RATIO:
                raise base.ArtifactError(
                    f"Artifact member compression ratio is unsafe: {info.filename}"
                )


def validated_members(
    archive: zipfile.ZipFile,
) -> tuple[str, list[zipfile.ZipInfo]]:
    version, infos = _original_validated_members(archive)
    _validate_resource_limits(infos)
    return version, infos


def extract_validated(artifact: Path, destination: Path) -> str:
    if artifact.stat().st_size > MAX_OUTER_ARCHIVE_BYTES:
        raise base.ArtifactError("Downloaded workflow artifact exceeds the outer ZIP size limit")
    return _original_extract_validated(artifact, destination)


def hardened_guide(repository: Path) -> Path:
    guide = repository / "scripts" / "run_physical_validation_guided_hardened.py"
    if not guide.is_file() or guide.is_symlink():
        raise base.ArtifactError("Hardened guided physical validation script is missing or unsafe")
    return guide


def stage(args: argparse.Namespace) -> int:
    if sys.platform != "darwin":
        raise base.ArtifactError("Physical validation staging requires macOS")
    if os.uname().machine != "arm64":
        raise base.ArtifactError(
            f"Physical validation requires native arm64; found {os.uname().machine!r}"
        )

    repository = base.ensure_repository(args.repository)
    guide = hardened_guide(repository)
    artifact = args.artifact.expanduser().resolve()
    if not artifact.is_file() or artifact.is_symlink():
        raise base.ArtifactError("Workflow artifact must be a regular non-symlink file")

    candidates_root = base.strict_repository_child(
        args.candidates_root, repository, "physical candidate root"
    )
    candidates_root.mkdir(parents=True, exist_ok=True)
    digest = base.sha256(artifact)
    destination = candidates_root / f"artifact-{digest[:16]}"
    if destination.exists() or destination.is_symlink():
        raise base.ArtifactError(
            "Refusing to reuse a staged workflow artifact directory: "
            + str(destination.relative_to(repository))
        )

    app_root = base.strict_repository_child(
        repository / "physical-validation-apps" / f"artifact-{digest[:16]}",
        repository,
        "physical validation app root",
    )
    if app_root.exists() or app_root.is_symlink():
        raise base.ArtifactError(
            "Refusing to reuse a staged physical application root: "
            + str(app_root.relative_to(repository))
        )

    version = extract_validated(artifact, destination)
    command = [
        sys.executable,
        str(guide),
        "start",
        "--repository",
        str(repository),
        "--dist",
        str(destination),
        "--app-root",
        str(app_root),
    ]
    print(f"Staged verified outer artifact for version {version}.")
    print(f"Outer artifact SHA-256: {digest}")
    print(f"Candidate directory: {destination.relative_to(repository)}")
    result = subprocess.run(command, check=False)
    return int(result.returncode)


def _write_custom_fixture(
    path: Path,
    *,
    zip_payload: bytes = b"inner-zip",
    compression: int = zipfile.ZIP_STORED,
) -> None:
    manifest = b'{"version":"1.0.0","architectures":["arm64"]}'
    entries = {
        "BUILD_MANIFEST.json": manifest,
        "BUILD_STATUS.txt": b"status\n",
        "SHA256SUMS.txt": b"checksums\n",
        "MacVitals-1.0.0.zip": zip_payload,
        "MacVitals-1.0.0.dmg": b"inner-dmg",
    }
    with zipfile.ZipFile(path, "w", compression=compression) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)


def self_test(_args_value: argparse.Namespace | None = None) -> int:
    _original_self_test(None)
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)

        valid = root / "valid.zip"
        _write_custom_fixture(valid)
        assert extract_validated(valid, root / "valid-output") == "1.0.0"

        high_ratio = root / "high-ratio.zip"
        _write_custom_fixture(
            high_ratio,
            zip_payload=b"0" * (2 * 1024 * 1024),
            compression=zipfile.ZIP_DEFLATED,
        )
        base.expect_invalid(
            lambda: extract_validated(high_ratio, root / "high-ratio-output")
        )

        oversized_info = zipfile.ZipInfo("MacVitals-1.0.0.zip")
        oversized_info.file_size = MAX_MEMBER_UNCOMPRESSED_BYTES + 1
        oversized_info.compress_size = MAX_MEMBER_UNCOMPRESSED_BYTES + 1
        try:
            _validate_resource_limits([oversized_info])
        except base.ArtifactError:
            pass
        else:
            raise AssertionError("Oversized workflow artifact member was accepted")

        first = zipfile.ZipInfo("first")
        first.file_size = MAX_TOTAL_UNCOMPRESSED_BYTES // 2 + 1
        first.compress_size = first.file_size
        second = zipfile.ZipInfo("second")
        second.file_size = MAX_TOTAL_UNCOMPRESSED_BYTES // 2 + 1
        second.compress_size = second.file_size
        try:
            _validate_resource_limits([first, second])
        except base.ArtifactError:
            pass
        else:
            raise AssertionError("Oversized total workflow artifact was accepted")

        repository = root / "repository"
        scripts = repository / "scripts"
        scripts.mkdir(parents=True)
        guide = scripts / "run_physical_validation_guided_hardened.py"
        guide.write_text("# fixture\n", encoding="utf-8")
        assert hardened_guide(repository) == guide
        guide.unlink()
        try:
            hardened_guide(repository)
        except base.ArtifactError:
            pass
        else:
            raise AssertionError("Missing hardened guide was accepted")

    print("Hardened physical workflow artifact staging self-test passed")
    return 0


base.validated_members = validated_members
base.extract_validated = extract_validated
base.stage = stage
base.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(base.main())
