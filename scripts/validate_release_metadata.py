#!/usr/bin/env python3
"""Strictly validate MacVitals build manifest and human-readable status metadata."""

from __future__ import annotations

import argparse
import json
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path


WARNING = (
    "Only a Developer ID signed app with a validated stapled notarization ticket "
    "and a successful Gatekeeper assessment may be described as ready for "
    "frictionless distribution."
)
MANIFEST_KEYS = {
    "schemaVersion",
    "product",
    "version",
    "buildNumber",
    "bundleIdentifier",
    "minimumMacOS",
    "gitCommit",
    "xcodeVersion",
    "architectures",
    "signingStatus",
    "notarizationStatus",
    "artifacts",
}
FORBIDDEN_HOST_DATA = (
    "/Users/",
    "\\Users\\",
    "Apple ID",
    "serialNumber",
    "username",
)


class ValidationError(ValueError):
    """Raised when release provenance is malformed or internally inconsistent."""


@dataclass(frozen=True)
class ExpectedMetadata:
    version: str
    build_number: str
    bundle_identifier: str
    minimum_macos: str
    architectures: tuple[str, ...]
    signing_status: str
    notarization_status: str
    zip_name: str
    dmg_name: str
    expected_git_commit: str | None = None


def read_manifest(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValidationError(f"Invalid BUILD_MANIFEST.json: {error}") from error
    if not isinstance(value, dict):
        raise ValidationError("BUILD_MANIFEST.json must contain one JSON object")
    return value


def validate_manifest(manifest: dict[str, object], expected: ExpectedMetadata) -> str:
    keys = set(manifest)
    if keys != MANIFEST_KEYS:
        missing = sorted(MANIFEST_KEYS - keys)
        unexpected = sorted(keys - MANIFEST_KEYS)
        raise ValidationError(
            f"Manifest key scope mismatch; missing={missing}, unexpected={unexpected}"
        )

    fixed_values: dict[str, object] = {
        "schemaVersion": 1,
        "product": "MacVitals",
        "version": expected.version,
        "buildNumber": expected.build_number,
        "bundleIdentifier": expected.bundle_identifier,
        "minimumMacOS": expected.minimum_macos,
        "architectures": list(expected.architectures),
        "signingStatus": expected.signing_status,
        "notarizationStatus": expected.notarization_status,
        "artifacts": {
            "zip": expected.zip_name,
            "dmg": expected.dmg_name,
        },
    }
    for key, value in fixed_values.items():
        if manifest.get(key) != value:
            raise ValidationError(
                f"Manifest mismatch for {key}: expected {value!r}, "
                f"found {manifest.get(key)!r}"
            )

    commit = manifest.get("gitCommit")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}|unknown", commit):
        raise ValidationError(f"Invalid manifest gitCommit: {commit!r}")
    if expected.expected_git_commit and commit != expected.expected_git_commit:
        raise ValidationError(
            f"Manifest gitCommit {commit} does not match workflow commit "
            f"{expected.expected_git_commit}"
        )

    xcode = manifest.get("xcodeVersion")
    if (
        not isinstance(xcode, str)
        or not xcode.startswith("Xcode ")
        or "; Build version " not in xcode
    ):
        raise ValidationError(f"Invalid manifest xcodeVersion: {xcode!r}")

    serialized = json.dumps(manifest, sort_keys=True)
    for forbidden in FORBIDDEN_HOST_DATA:
        if forbidden in serialized:
            raise ValidationError(
                f"Manifest contains forbidden host-specific data: {forbidden}"
            )
    return commit


def validate_status(path: Path, expected: ExpectedMetadata, commit: str) -> None:
    expected_text = "\n".join(
        [
            f"MacVitals {expected.version} ({expected.build_number})",
            f"Git commit: {commit}",
            f"Architectures: {' '.join(expected.architectures)}",
            f"Signing status: {expected.signing_status}",
            f"Notarization status: {expected.notarization_status}",
            "",
            WARNING,
            "",
        ]
    )
    try:
        actual = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ValidationError(f"Invalid BUILD_STATUS.txt: {error}") from error
    if actual != expected_text:
        raise ValidationError(
            "BUILD_STATUS.txt does not exactly match manifest and packaged metadata"
        )


def validate_paths(manifest_path: Path, status_path: Path, expected: ExpectedMetadata) -> None:
    manifest = read_manifest(manifest_path)
    commit = validate_manifest(manifest, expected)
    validate_status(status_path, expected, commit)


def valid_fixture() -> tuple[dict[str, object], ExpectedMetadata]:
    expected = ExpectedMetadata(
        version="1.2.3",
        build_number="45",
        bundle_identifier="com.mishkacher.MacVitals",
        minimum_macos="13.0",
        architectures=("x86_64", "arm64"),
        signing_status="unsigned",
        notarization_status="not-notarized",
        zip_name="MacVitals-1.2.3.zip",
        dmg_name="MacVitals-1.2.3.dmg",
        expected_git_commit="a" * 40,
    )
    manifest: dict[str, object] = {
        "schemaVersion": 1,
        "product": "MacVitals",
        "version": expected.version,
        "buildNumber": expected.build_number,
        "bundleIdentifier": expected.bundle_identifier,
        "minimumMacOS": expected.minimum_macos,
        "gitCommit": expected.expected_git_commit,
        "xcodeVersion": "Xcode 16.4; Build version 16F6",
        "architectures": list(expected.architectures),
        "signingStatus": expected.signing_status,
        "notarizationStatus": expected.notarization_status,
        "artifacts": {"zip": expected.zip_name, "dmg": expected.dmg_name},
    }
    return manifest, expected


def expect_invalid(
    manifest: dict[str, object],
    expected: ExpectedMetadata,
    *,
    status_commit: str | None = None,
) -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        manifest_path = root / "BUILD_MANIFEST.json"
        status_path = root / "BUILD_STATUS.txt"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        commit = status_commit or str(manifest.get("gitCommit", "unknown"))
        status_path.write_text(
            "\n".join(
                [
                    f"MacVitals {expected.version} ({expected.build_number})",
                    f"Git commit: {commit}",
                    f"Architectures: {' '.join(expected.architectures)}",
                    f"Signing status: {expected.signing_status}",
                    f"Notarization status: {expected.notarization_status}",
                    "",
                    WARNING,
                    "",
                ]
            ),
            encoding="utf-8",
        )
        try:
            validate_paths(manifest_path, status_path, expected)
        except ValidationError:
            return
        raise ValidationError("Self-test expected invalid metadata to be rejected")


def run_self_test() -> None:
    manifest, expected = valid_fixture()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        manifest_path = root / "BUILD_MANIFEST.json"
        status_path = root / "BUILD_STATUS.txt"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        commit = str(manifest["gitCommit"])
        status_path.write_text(
            "\n".join(
                [
                    f"MacVitals {expected.version} ({expected.build_number})",
                    f"Git commit: {commit}",
                    f"Architectures: {' '.join(expected.architectures)}",
                    f"Signing status: {expected.signing_status}",
                    f"Notarization status: {expected.notarization_status}",
                    "",
                    WARNING,
                    "",
                ]
            ),
            encoding="utf-8",
        )
        validate_paths(manifest_path, status_path, expected)

    extra = dict(manifest)
    extra["unexpected"] = "value"
    expect_invalid(extra, expected)

    bad_commit = dict(manifest)
    bad_commit["gitCommit"] = "not-a-commit"
    expect_invalid(bad_commit, expected)

    host_path = dict(manifest)
    host_path["xcodeVersion"] = "Xcode 16.4; Build version /Users/test/16F6"
    expect_invalid(host_path, expected)

    expect_invalid(manifest, expected, status_commit="b" * 40)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--status", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--build-number")
    parser.add_argument("--bundle-identifier")
    parser.add_argument("--minimum-macos")
    parser.add_argument("--architectures")
    parser.add_argument("--signing-status")
    parser.add_argument("--notarization-status")
    parser.add_argument("--zip-name")
    parser.add_argument("--dmg-name")
    parser.add_argument("--expected-git-commit")
    return parser.parse_args()


def required(value: object, name: str) -> object:
    if value is None or value == "":
        raise ValidationError(f"Missing required argument: {name}")
    return value


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.self_test:
            run_self_test()
            print("Release metadata validator self-test passed")
            return 0

        manifest_path = required(arguments.manifest, "--manifest")
        status_path = required(arguments.status, "--status")
        architectures = str(required(arguments.architectures, "--architectures")).split()
        if not architectures:
            raise ValidationError("At least one architecture is required")
        expected = ExpectedMetadata(
            version=str(required(arguments.version, "--version")),
            build_number=str(required(arguments.build_number, "--build-number")),
            bundle_identifier=str(
                required(arguments.bundle_identifier, "--bundle-identifier")
            ),
            minimum_macos=str(required(arguments.minimum_macos, "--minimum-macos")),
            architectures=tuple(architectures),
            signing_status=str(required(arguments.signing_status, "--signing-status")),
            notarization_status=str(
                required(arguments.notarization_status, "--notarization-status")
            ),
            zip_name=str(required(arguments.zip_name, "--zip-name")),
            dmg_name=str(required(arguments.dmg_name, "--dmg-name")),
            expected_git_commit=arguments.expected_git_commit or None,
        )
        validate_paths(Path(manifest_path), Path(status_path), expected)
        print("Release manifest and status metadata are valid and consistent")
        return 0
    except ValidationError as error:
        print(f"Release metadata validation failed: {error}", file=__import__("sys").stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
