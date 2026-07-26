#!/usr/bin/env python3
"""Provenance hardening overlay for the private signed-release pipeline."""

from __future__ import annotations

import argparse

import sign_notarize_release as base

SUPPORTED_XCODEGEN_VERSIONS = ("2.45.4", "2.46.0")
_original_manifest_keys = set(base.MANIFEST_KEYS)
_hardened_manifest_keys = _original_manifest_keys | {"xcodeGenVersion"}
_original_signed_manifest = base.signed_manifest
_original_self_test = base.self_test


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


def self_test(_args: argparse.Namespace | None = None) -> int:
    base.MANIFEST_KEYS = set(_original_manifest_keys)
    base.signed_manifest = _original_signed_manifest
    try:
        _original_self_test(None)
    finally:
        base.MANIFEST_KEYS = set(_hardened_manifest_keys)
        base.signed_manifest = signed_manifest

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

    print("Hardened signed release pipeline self-test passed")
    return 0


base.MANIFEST_KEYS = set(_hardened_manifest_keys)
base.signed_manifest = signed_manifest
base.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(base.main())
