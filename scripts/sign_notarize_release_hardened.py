#!/usr/bin/env python3
"""Provenance and nested-code hardening for the private signed-release pipeline."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Sequence

import sign_notarize_release as base
import validate_fan_helper_bundle as fan_bundle

SUPPORTED_XCODEGEN_VERSIONS = ("2.45.4", "2.46.0")
_original_manifest_keys = set(base.MANIFEST_KEYS)
_hardened_manifest_keys = _original_manifest_keys | {"xcodeGenVersion"}
_original_signed_manifest = base.signed_manifest
_original_self_test = base.self_test
_original_run = base.run
_original_verify_developer_id = base.verify_developer_id


def signed_manifest(
    unsigned: dict[str, object], version: str, build: str, commit: str
) -> dict[str, object]:
    xcodegen_version = unsigned.get("xcodeGenVersion")
    if xcodegen_version not in SUPPORTED_XCODEGEN_VERSIONS:
        raise base.ReleaseError(
            "Unsigned manifest contains an unsupported XcodeGen version: "
            f"{xcodegen_version!r}"
        )
    result = _original_signed_manifest(unsigned, version, build, commit)
    if result.get("xcodeGenVersion") != xcodegen_version:
        raise base.ReleaseError("Signed manifest did not preserve XcodeGen provenance")
    return result


def helper_sign_command(app_sign_command: Sequence[str], helper: Path) -> list[str]:
    command = list(app_sign_command)
    if not command or Path(command[0]).name != "codesign" or "--sign" not in command:
        raise base.ReleaseError("Could not derive a nested helper signing command")
    identity_index = command.index("--sign") + 1
    if identity_index >= len(command):
        raise base.ReleaseError("Application signing command does not contain an identity")
    identity = command[identity_index]
    result = [
        command[0],
        "--force",
        "--sign",
        identity,
        "--options",
        "runtime",
        "--timestamp",
        "--generate-entitlement-der",
        str(helper),
    ]
    return result


def run(
    args: Sequence[str],
    *,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> Any:
    command = list(args)
    if (
        command
        and Path(command[0]).name == "codesign"
        and "--sign" in command
        and command[-1].endswith("MacVitals.app")
        and "--entitlements" in command
    ):
        app = Path(command[-1])
        try:
            fan_bundle.validate_bundle(app)
        except fan_bundle.ValidationError as error:
            raise base.ReleaseError(f"Fan helper bundle failed signed-release preflight: {error}") from error
        helper = app / fan_bundle.HELPER_RELATIVE_PATH
        _original_run(helper_sign_command(command, helper), env=env, check=True)
    return _original_run(command, env=env, check=check)


def verify_developer_id(
    app: Path,
    identity: str,
    team_id: str,
    evidence: Path,
) -> str:
    detail = _original_verify_developer_id(app, identity, team_id, evidence)
    try:
        fan_bundle.validate_bundle(app)
    except fan_bundle.ValidationError as error:
        raise base.ReleaseError(f"Signed fan helper bundle is invalid: {error}") from error

    helper = app / fan_bundle.HELPER_RELATIVE_PATH
    _original_run(["codesign", "--verify", "--strict", "--verbose=4", str(helper)])
    result = _original_run(
        ["codesign", "-dv", "--verbose=4", str(helper)],
        check=False,
    )
    helper_detail = result.stdout + result.stderr
    base.write_redacted(evidence / "codesign-fan-helper-details.txt", helper_detail)
    if result.returncode != 0:
        raise base.ReleaseError("Could not inspect Developer ID fan helper signature")
    if f"Authority={identity}" not in helper_detail:
        raise base.ReleaseError("Fan helper authority does not match the application identity")
    if f"TeamIdentifier={team_id}" not in helper_detail:
        raise base.ReleaseError("Fan helper TeamIdentifier does not match the application")
    if "runtime" not in helper_detail.lower():
        raise base.ReleaseError("Fan helper does not advertise Hardened Runtime")
    if "Timestamp=" not in helper_detail:
        raise base.ReleaseError("Fan helper does not contain a trusted timestamp")
    architecture = base.output("lipo", "-archs", str(helper))
    if architecture != "arm64":
        raise base.ReleaseError(
            f"Signed fan helper must be exactly arm64; found {architecture!r}"
        )
    return detail


def self_test(_args: argparse.Namespace | None = None) -> int:
    base.MANIFEST_KEYS = set(_original_manifest_keys)
    base.signed_manifest = _original_signed_manifest
    base.run = _original_run
    base.verify_developer_id = _original_verify_developer_id
    try:
        _original_self_test(None)
    finally:
        base.MANIFEST_KEYS = set(_hardened_manifest_keys)
        base.signed_manifest = signed_manifest
        base.run = run
        base.verify_developer_id = verify_developer_id

    valid: dict[str, object] = {
        "schemaVersion": 1,
        "product": "MacVitals",
        "version": "1.2.3",
        "buildNumber": "45",
        "bundleIdentifier": "com.mishkacher.MacVitals",
        "minimumMacOS": "13.0",
        "gitCommit": "a" * 40,
        "xcodeVersion": "Xcode 16.4; Build version 16F6",
        "xcodeGenVersion": "2.46.0",
        "architectures": ["arm64"],
        "signingStatus": "unsigned",
        "notarizationStatus": "not-notarized",
        "artifacts": {"zip": "MacVitals-1.2.3.zip", "dmg": "MacVitals-1.2.3.dmg"},
    }
    transformed = signed_manifest(valid, "1.2.3", "45", "a" * 40)
    assert transformed["xcodeGenVersion"] == "2.46.0"
    assert transformed["signingStatus"] == "developer-id-signed"
    assert transformed["notarizationStatus"] == "ticket-present"

    alternate = dict(valid)
    alternate["xcodeGenVersion"] = "2.45.4"
    assert signed_manifest(alternate, "1.2.3", "45", "a" * 40)[
        "xcodeGenVersion"
    ] == "2.45.4"

    for invalid in (None, "", "2.47.0"):
        mutated = dict(valid)
        if invalid is None:
            mutated.pop("xcodeGenVersion")
        else:
            mutated["xcodeGenVersion"] = invalid
        try:
            signed_manifest(mutated, "1.2.3", "45", "a" * 40)
        except base.ReleaseError:
            pass
        else:
            raise AssertionError(
                f"Unsupported signed-release XcodeGen provenance was accepted: {invalid!r}"
            )

    app_command = [
        "codesign",
        "--force",
        "--sign",
        "Developer ID Application: Example (ABCDEFGHIJ)",
        "--options",
        "runtime",
        "--timestamp",
        "--generate-entitlement-der",
        "--entitlements",
        "MacVitals/Resources/MacVitals.entitlements",
        "/tmp/MacVitals.app",
    ]
    helper_command = helper_sign_command(
        app_command,
        Path("/tmp/MacVitals.app/Contents/Resources/MacVitalsFanHelper"),
    )
    assert helper_command[-1].endswith("Contents/Resources/MacVitalsFanHelper")
    assert "--entitlements" not in helper_command
    assert "runtime" in helper_command
    assert helper_command.index("--sign") + 1 < len(helper_command)

    print("Hardened signed release pipeline self-test passed")
    return 0


base.MANIFEST_KEYS = set(_hardened_manifest_keys)
base.signed_manifest = signed_manifest
base.run = run
base.verify_developer_id = verify_developer_id
base.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(base.main())
