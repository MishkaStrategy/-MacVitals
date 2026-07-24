#!/usr/bin/env python3
"""Safely stage a downloaded MacVitals workflow artifact and start guided validation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import NoReturn


VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){0,2}$")
EXPECTED_STATIC_NAMES = {
    "BUILD_MANIFEST.json",
    "BUILD_STATUS.txt",
    "SHA256SUMS.txt",
}


class ArtifactError(RuntimeError):
    """Raised when an outer workflow artifact cannot be staged safely."""


def fail(message: str, code: int = 1) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_repository(path: Path) -> Path:
    repository = path.resolve()
    if not (repository / ".git").exists():
        raise ArtifactError("Repository does not contain .git")
    guide = repository / "scripts" / "run_physical_validation_guided.py"
    if not guide.is_file() or guide.is_symlink():
        raise ArtifactError("Guided physical validation script is missing or unsafe")
    return repository


def strict_repository_child(path: Path, repository: Path, label: str) -> Path:
    repository = repository.resolve()
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(repository)
    except ValueError as error:
        raise ArtifactError(f"{label} must remain inside the repository") from error
    if relative == Path("."):
        raise ArtifactError(f"{label} must be a strict repository child")
    return resolved


def zip_member_is_symlink(info: zipfile.ZipInfo) -> bool:
    unix_mode = (info.external_attr >> 16) & 0xFFFF
    return (unix_mode & 0o170000) == 0o120000


def validated_members(archive: zipfile.ZipFile) -> tuple[str, list[zipfile.ZipInfo]]:
    infos = archive.infolist()
    if len(infos) != 5:
        raise ArtifactError(f"Workflow artifact must contain exactly five files; found {len(infos)}")

    names: set[str] = set()
    for info in infos:
        raw_name = info.filename
        path = PurePosixPath(raw_name)
        if (
            not raw_name
            or raw_name.endswith("/")
            or path.is_absolute()
            or len(path.parts) != 1
            or path.parts[0] in {".", ".."}
            or ".." in path.parts
            or "\\" in raw_name
        ):
            raise ArtifactError(f"Unsafe or nested artifact member: {raw_name!r}")
        if zip_member_is_symlink(info):
            raise ArtifactError(f"Artifact member must not be a symlink: {raw_name}")
        if info.file_size <= 0:
            raise ArtifactError(f"Artifact member must not be empty: {raw_name}")
        if raw_name in names:
            raise ArtifactError(f"Duplicate artifact member: {raw_name}")
        names.add(raw_name)

    manifests = [name for name in names if name == "BUILD_MANIFEST.json"]
    if len(manifests) != 1:
        raise ArtifactError("Workflow artifact must contain BUILD_MANIFEST.json")
    try:
        manifest = json.loads(archive.read("BUILD_MANIFEST.json").decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError, KeyError) as error:
        raise ArtifactError("Workflow artifact manifest is not valid UTF-8 JSON") from error
    if not isinstance(manifest, dict):
        raise ArtifactError("Workflow artifact manifest must contain an object")

    version = manifest.get("version")
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
        raise ArtifactError("Workflow artifact manifest version is invalid")
    if manifest.get("architectures") != ["arm64"]:
        raise ArtifactError("Workflow artifact architecture must be exactly ['arm64']")

    expected = EXPECTED_STATIC_NAMES | {
        f"MacVitals-{version}.zip",
        f"MacVitals-{version}.dmg",
    }
    if names != expected:
        missing = sorted(expected - names)
        extra = sorted(names - expected)
        raise ArtifactError(
            "Workflow artifact file set is invalid; "
            f"missing={missing or 'none'}, extra={extra or 'none'}"
        )
    return version, infos


def extract_validated(artifact: Path, destination: Path) -> str:
    try:
        archive = zipfile.ZipFile(artifact)
    except (OSError, zipfile.BadZipFile) as error:
        raise ArtifactError("Downloaded workflow artifact is not a valid ZIP") from error

    with archive:
        version, infos = validated_members(archive)
        destination.mkdir(parents=True, exist_ok=False)
        try:
            for info in infos:
                target = destination / info.filename
                with archive.open(info) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
                if target.stat().st_size != info.file_size:
                    raise ArtifactError(f"Extracted size mismatch: {info.filename}")
        except Exception:
            shutil.rmtree(destination, ignore_errors=True)
            raise
    return version


def stage(args: argparse.Namespace) -> int:
    if sys.platform != "darwin":
        raise ArtifactError("Physical validation staging requires macOS")
    if os.uname().machine != "arm64":
        raise ArtifactError(f"Physical validation requires native arm64; found {os.uname().machine!r}")

    repository = ensure_repository(args.repository)
    artifact = args.artifact.expanduser().resolve()
    if not artifact.is_file() or artifact.is_symlink():
        raise ArtifactError("Workflow artifact must be a regular non-symlink file")

    candidates_root = strict_repository_child(
        args.candidates_root, repository, "physical candidate root"
    )
    candidates_root.mkdir(parents=True, exist_ok=True)
    digest = sha256(artifact)
    destination = candidates_root / f"artifact-{digest[:16]}"
    if destination.exists() or destination.is_symlink():
        raise ArtifactError(
            "Refusing to reuse a staged workflow artifact directory: "
            + str(destination.relative_to(repository))
        )

    version = extract_validated(artifact, destination)
    guide = repository / "scripts" / "run_physical_validation_guided.py"
    command = [
        sys.executable,
        str(guide),
        "start",
        "--repository",
        str(repository),
        "--dist",
        str(destination),
    ]
    print(f"Staged verified outer artifact for version {version}.")
    print(f"Outer artifact SHA-256: {digest}")
    print(f"Candidate directory: {destination.relative_to(repository)}")
    result = subprocess.run(command, check=False)
    return int(result.returncode)


def expect_invalid(function) -> None:  # type: ignore[no-untyped-def]
    try:
        function()
    except ArtifactError:
        return
    raise AssertionError("Expected unsafe workflow artifact to be rejected")


def write_fixture(path: Path, *, nested: bool = False, symlink: bool = False) -> None:
    manifest = json.dumps({"version": "1.0.0", "architectures": ["arm64"]}).encode()
    entries = {
        "BUILD_MANIFEST.json": manifest,
        "BUILD_STATUS.txt": b"status\n",
        "SHA256SUMS.txt": b"checksums\n",
        "MacVitals-1.0.0.zip": b"inner-zip",
        "MacVitals-1.0.0.dmg": b"inner-dmg",
    }
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        for name, data in entries.items():
            member = f"nested/{name}" if nested else name
            info = zipfile.ZipInfo(member)
            if symlink and name == "BUILD_STATUS.txt":
                info.external_attr = (0o120777 << 16)
            archive.writestr(info, data)


def self_test(_args: argparse.Namespace | None = None) -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        valid = root / "valid.zip"
        write_fixture(valid)
        output = root / "output"
        assert extract_validated(valid, output) == "1.0.0"
        assert {path.name for path in output.iterdir()} == EXPECTED_STATIC_NAMES | {
            "MacVitals-1.0.0.zip",
            "MacVitals-1.0.0.dmg",
        }

        nested = root / "nested.zip"
        write_fixture(nested, nested=True)
        expect_invalid(lambda: extract_validated(nested, root / "nested-output"))

        linked = root / "linked.zip"
        write_fixture(linked, symlink=True)
        expect_invalid(lambda: extract_validated(linked, root / "linked-output"))

        extra = root / "extra.zip"
        write_fixture(extra)
        with zipfile.ZipFile(extra, "a") as archive:
            archive.writestr("unexpected.txt", b"unexpected")
        expect_invalid(lambda: extract_validated(extra, root / "extra-output"))

        empty = root / "empty.zip"
        write_fixture(empty)
        with zipfile.ZipFile(empty, "a") as archive:
            archive.writestr("empty.txt", b"")
        expect_invalid(lambda: extract_validated(empty, root / "empty-output"))

    print("Physical workflow artifact staging self-test passed")
    return 0


def build_parser() -> argparse.ArgumentParser:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    stage_parser = commands.add_parser("stage")
    stage_parser.add_argument("artifact", type=Path)
    stage_parser.add_argument("--repository", type=Path, default=root)
    stage_parser.add_argument(
        "--candidates-root",
        type=Path,
        default=root / "physical-validation-candidates",
    )
    stage_parser.set_defaults(function=stage)

    test_parser = commands.add_parser("self-test")
    test_parser.set_defaults(function=self_test)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return int(args.function(args))
    except ArtifactError as error:
        fail(str(error))


if __name__ == "__main__":
    raise SystemExit(main())
