#!/usr/bin/env python3
"""Build, Developer ID sign, notarize and verify a private MacVitals candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, NoReturn, Sequence

AUTHORIZATION = "SIGN_MACVITALS_RELEASE_CANDIDATE"
WARNING = (
    "Only a Developer ID signed app with a validated stapled notarization ticket "
    "and a successful Gatekeeper assessment may be described as ready for "
    "frictionless distribution."
)
VERSION_RE = re.compile(r"[0-9]+(?:\.[0-9]+){0,2}\Z")
BUILD_RE = re.compile(r"[0-9]+(?:\.[0-9]+)*\Z")
COMMIT_RE = re.compile(r"[0-9a-f]{40}\Z")
TEAM_RE = re.compile(r"[A-Z0-9]{10}\Z")
KEY_ID_RE = re.compile(r"[A-Z0-9]{10}\Z")
ISSUER_RE = re.compile(r"[0-9a-fA-F-]{36}\Z")
HOME_RE = re.compile(r"/(?:Users|home)/[^/\s]+")
MANIFEST_KEYS = {
    "schemaVersion", "product", "version", "buildNumber", "bundleIdentifier",
    "minimumMacOS", "gitCommit", "xcodeVersion", "architectures",
    "signingStatus", "notarizationStatus", "artifacts",
}


class ReleaseError(RuntimeError):
    """Raised when the signed release gate cannot be proven."""


def fail(message: str, code: int = 1) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def redact(text: str) -> str:
    home = str(Path.home())
    if home:
        text = text.replace(home, "<HOME>")
    return HOME_RE.sub("<HOME>", text)


def run(
    args: Sequence[str],
    *,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    process_env = {**os.environ, "LC_ALL": "C", "LANG": "C"}
    if env:
        process_env.update(env)
    result = subprocess.run(
        list(args),
        capture_output=True,
        text=True,
        check=False,
        env=process_env,
    )
    if check and result.returncode != 0:
        detail = redact((result.stdout + "\n" + result.stderr).strip())
        raise ReleaseError(f"Command failed: {Path(args[0]).name}\n{detail}")
    return result


def output(*args: str) -> str:
    return run(args).stdout.strip()


def require_commands(*names: str) -> None:
    missing = [name for name in names if shutil.which(name) is None]
    if missing:
        raise ReleaseError("Required command is unavailable: " + ", ".join(missing))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"Could not read valid {path.name}: {error}") from error
    if not isinstance(value, dict):
        raise ReleaseError(f"{path.name} must contain one object")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def write_redacted(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(redact(text).rstrip() + "\n", encoding="utf-8")


def strict_child(path: Path, root: Path, label: str) -> Path:
    resolved_root = root.resolve()
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(resolved_root)
    except ValueError as error:
        raise ReleaseError(f"{label} must remain inside the repository") from error
    if relative == Path("."):
        raise ReleaseError(f"{label} must be a strict repository child")
    return resolved


def validate_release_inputs(
    version: str,
    build_number: str,
    expected_commit: str,
    identity: str,
    team_id: str,
    key_id: str,
    issuer: str,
    authorization: str,
) -> None:
    if not VERSION_RE.fullmatch(version) or len(version) > 64:
        raise ReleaseError(f"Invalid release version: {version!r}")
    if not BUILD_RE.fullmatch(build_number) or len(build_number) > 64:
        raise ReleaseError(f"Invalid build number: {build_number!r}")
    if not COMMIT_RE.fullmatch(expected_commit):
        raise ReleaseError("Expected commit must be a lowercase 40-character SHA")
    if authorization != AUTHORIZATION:
        raise ReleaseError("Explicit signed-release authorization is missing")
    if not identity.startswith("Developer ID Application:"):
        raise ReleaseError("Identity must be a Developer ID Application identity")
    if not TEAM_RE.fullmatch(team_id):
        raise ReleaseError("Team ID must contain exactly 10 uppercase letters or digits")
    if team_id not in identity:
        raise ReleaseError("Developer ID identity does not contain the expected Team ID")
    if not KEY_ID_RE.fullmatch(key_id):
        raise ReleaseError("Notary API key ID must contain exactly 10 uppercase letters or digits")
    if not ISSUER_RE.fullmatch(issuer):
        raise ReleaseError("Notary issuer must be a UUID")


def validate_api_key(path: Path) -> Path:
    resolved = path.resolve()
    if not resolved.is_file() or path.is_symlink():
        raise ReleaseError("Notary API key must be a regular non-symlink file")
    mode = stat.S_IMODE(resolved.stat().st_mode)
    if mode & 0o077:
        raise ReleaseError("Notary API key permissions must not allow group/other access")
    if resolved.stat().st_size <= 0:
        raise ReleaseError("Notary API key is empty")
    return resolved


def parse_notary_response(text: str, label: str) -> tuple[str, str]:
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        raise ReleaseError(f"{label} response is not valid JSON: {error}") from error
    if not isinstance(value, dict):
        raise ReleaseError(f"{label} response root must be an object")
    request_id = value.get("id")
    status_value = value.get("status")
    if not isinstance(request_id, str) or not re.fullmatch(r"[0-9a-fA-F-]{36}", request_id):
        raise ReleaseError(f"{label} response contains an invalid submission ID")
    if status_value != "Accepted":
        message = value.get("message")
        suffix = f": {message}" if isinstance(message, str) and message else ""
        raise ReleaseError(f"{label} was not accepted; status={status_value!r}{suffix}")
    return request_id, status_value


def signed_manifest(unsigned: dict[str, Any], version: str, build: str, commit: str) -> dict[str, Any]:
    if set(unsigned) != MANIFEST_KEYS:
        raise ReleaseError("Unsigned manifest key scope is invalid")
    expected = {
        "schemaVersion": 1,
        "product": "MacVitals",
        "version": version,
        "buildNumber": build,
        "gitCommit": commit,
        "architectures": ["arm64"],
        "signingStatus": "unsigned",
        "notarizationStatus": "not-notarized",
        "artifacts": {
            "zip": f"MacVitals-{version}.zip",
            "dmg": f"MacVitals-{version}.dmg",
        },
    }
    for key, expected_value in expected.items():
        if unsigned.get(key) != expected_value:
            raise ReleaseError(
                f"Unsigned manifest mismatch for {key}: "
                f"expected {expected_value!r}, found {unsigned.get(key)!r}"
            )
    result = dict(unsigned)
    result["signingStatus"] = "developer-id-signed"
    result["notarizationStatus"] = "ticket-present"
    return result


def status_text(manifest: dict[str, Any]) -> str:
    return "\n".join(
        [
            f"MacVitals {manifest['version']} ({manifest['buildNumber']})",
            f"Git commit: {manifest['gitCommit']}",
            f"Architectures: {' '.join(manifest['architectures'])}",
            f"Signing status: {manifest['signingStatus']}",
            f"Notarization status: {manifest['notarizationStatus']}",
            "",
            WARNING,
            "",
        ]
    )


def credentials(api_key: Path, key_id: str, issuer: str) -> list[str]:
    return ["--key", str(api_key), "--key-id", key_id, "--issuer", issuer]


def submit_and_retain(
    target: Path,
    label: str,
    evidence: Path,
    credential_args: list[str],
) -> str:
    response = run(
        [
            "xcrun", "notarytool", "submit", str(target), "--wait",
            "--output-format", "json", *credential_args,
        ]
    )
    response_text = response.stdout.strip()
    request_id, _ = parse_notary_response(response_text, label)
    write_redacted(evidence / f"{label}-submission.json", response_text)
    log_result = run(
        [
            "xcrun", "notarytool", "log", request_id,
            "--output-format", "json", *credential_args,
        ]
    )
    write_redacted(evidence / f"{label}-notary-log.json", log_result.stdout)
    return request_id


def verify_developer_id(app: Path, identity: str, team_id: str, evidence: Path) -> str:
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=4", str(app)])
    detail_result = run(["codesign", "-dv", "--verbose=4", str(app)], check=False)
    detail = detail_result.stdout + detail_result.stderr
    write_redacted(evidence / "codesign-details.txt", detail)
    if detail_result.returncode != 0:
        raise ReleaseError("Could not inspect Developer ID signature")
    if f"Authority={identity}" not in detail:
        raise ReleaseError("Signed app authority does not match the requested identity")
    if f"TeamIdentifier={team_id}" not in detail:
        raise ReleaseError("Signed app TeamIdentifier does not match the requested team")
    if "runtime" not in detail.lower():
        raise ReleaseError("Signed app does not advertise Hardened Runtime")
    if not re.search(r"^Timestamp=.+$", detail, re.MULTILINE):
        raise ReleaseError("Signed app does not contain a trusted timestamp")
    architecture = output("lipo", "-archs", str(app / "Contents" / "MacOS" / "MacVitals"))
    if architecture != "arm64":
        raise ReleaseError(f"Signed executable must be exactly arm64; found {architecture!r}")
    return detail


def gatekeeper(app: Path, dmg: Path, evidence: Path) -> None:
    app_result = run(
        ["spctl", "--assess", "--type", "execute", "--verbose=4", str(app)],
        check=False,
    )
    write_redacted(evidence / "gatekeeper-app.txt", app_result.stdout + app_result.stderr)
    if app_result.returncode != 0:
        raise ReleaseError("Gatekeeper rejected the stapled application")
    dmg_result = run(
        [
            "spctl", "--assess", "--type", "open",
            "--context", "context:primary-signature", "--verbose=4", str(dmg),
        ],
        check=False,
    )
    write_redacted(evidence / "gatekeeper-dmg.txt", dmg_result.stdout + dmg_result.stderr)
    if dmg_result.returncode != 0:
        raise ReleaseError("Gatekeeper rejected the stapled DMG")


def privacy_scan(root: Path) -> None:
    violations: list[str] = []
    home = str(Path.home())
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if (home and home in text) or HOME_RE.search(text):
            violations.append(str(path.relative_to(root)))
    if violations:
        raise ReleaseError(
            "Signed-release evidence contains a user home path: "
            + ", ".join(sorted(violations))
        )


def preflight(args: argparse.Namespace) -> dict[str, str]:
    validate_release_inputs(
        args.version,
        args.build_number,
        args.expected_commit,
        args.identity,
        args.team_id,
        args.key_id,
        args.issuer,
        args.authorization,
    )
    api_key = validate_api_key(args.api_key)
    require_commands(
        "bash", "codesign", "ditto", "git", "hdiutil", "lipo", "plutil",
        "security", "shasum", "spctl", "xcodebuild", "xcodegen", "xcrun",
    )
    if platform.machine() != "arm64":
        raise ReleaseError(f"Native arm64 host is required; found {platform.machine()!r}")
    root = args.repository.resolve()
    if not (root / ".git").exists():
        raise ReleaseError("Repository does not contain .git")
    actual_commit = output("git", "-C", str(root), "rev-parse", "HEAD")
    if actual_commit != args.expected_commit:
        raise ReleaseError(
            f"Checked-out commit {actual_commit} does not match {args.expected_commit}"
        )
    identity_result = output("security", "find-identity", "-v", "-p", "codesigning")
    if args.identity not in identity_result:
        raise ReleaseError("Requested Developer ID identity is not available in the keychain")
    run(["xcrun", "--find", "notarytool"])
    run(["xcrun", "--find", "stapler"])
    return {
        "apiKey": str(api_key),
        "commit": actual_commit,
        "identity": args.identity,
        "teamID": args.team_id,
    }


def safe_create(path: Path) -> None:
    if path.exists():
        raise ReleaseError(f"Refusing to reuse existing release directory: {path.name}")
    path.mkdir(parents=True, exist_ok=False)


def run_release(args: argparse.Namespace) -> int:
    values = preflight(args)
    root = args.repository.resolve()
    output_root = strict_child(args.output_root, root, "signed output root")
    work_root = strict_child(args.work_root, root, "signed work root")
    evidence_root = strict_child(args.evidence_root, root, "signed evidence root")
    if len({output_root, work_root, evidence_root}) != 3:
        raise ReleaseError("Signed output, work and evidence roots must be distinct")

    run_id = f"{args.version}-{args.build_number}-{args.expected_commit[:12]}"
    final_dist = output_root / run_id
    work = work_root / f"run-{utc_now().replace('-', '').replace(':', '')}-{os.getpid()}"
    evidence = evidence_root / run_id
    safe_create(final_dist)
    safe_create(work)
    safe_create(evidence)

    build_dir = work / "build"
    unsigned_dist = work / "unsigned-dist"
    package_env = {
        "BUILD_NUMBER": args.build_number,
        "BUILD_DIR": str(build_dir),
        "DIST_DIR": str(unsigned_dist),
        "CODE_SIGNING_ALLOWED": "NO",
        "GITHUB_SHA": args.expected_commit,
    }
    try:
        run(["bash", str(root / "scripts" / "package_release.sh"), args.version], env=package_env)
        app = build_dir / "MacVitals.xcarchive" / "Products" / "Applications" / "MacVitals.app"
        if not app.is_dir():
            raise ReleaseError("Unsigned archive does not contain MacVitals.app")
        unsigned_manifest = read_json(unsigned_dist / "BUILD_MANIFEST.json")
        manifest = signed_manifest(
            unsigned_manifest, args.version, args.build_number, args.expected_commit
        )

        sign_result = run(
            [
                "codesign", "--force", "--sign", args.identity,
                "--options", "runtime", "--timestamp", "--generate-entitlement-der",
                "--entitlements", str(root / "MacVitals" / "Resources" / "MacVitals.entitlements"),
                str(app),
            ]
        )
        write_redacted(evidence / "codesign-command-output.txt", sign_result.stdout + sign_result.stderr)
        verify_developer_id(app, args.identity, args.team_id, evidence)

        credential_args = credentials(Path(values["apiKey"]), args.key_id, args.issuer)
        pre_notary_zip = work / f"MacVitals-{args.version}-pre-notary.zip"
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(pre_notary_zip)])
        app_request_id = submit_and_retain(
            pre_notary_zip, "application", evidence, credential_args
        )
        run(["xcrun", "stapler", "staple", str(app)])
        run(["xcrun", "stapler", "validate", str(app)])
        verify_developer_id(app, args.identity, args.team_id, evidence)

        zip_name = f"MacVitals-{args.version}.zip"
        dmg_name = f"MacVitals-{args.version}.dmg"
        zip_path = final_dist / zip_name
        dmg_path = final_dist / dmg_name
        dmg_root = work / "dmg-root"
        dmg_root.mkdir()
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(zip_path)])
        run(["ditto", str(app), str(dmg_root / "MacVitals.app")])
        (dmg_root / "Applications").symlink_to("/Applications")
        run(
            [
                "hdiutil", "create", "-volname", "MacVitals",
                "-srcfolder", str(dmg_root), "-ov", "-format", "UDZO", str(dmg_path),
            ]
        )
        dmg_request_id = submit_and_retain(dmg_path, "dmg", evidence, credential_args)
        run(["xcrun", "stapler", "staple", str(dmg_path)])
        run(["xcrun", "stapler", "validate", str(dmg_path)])
        gatekeeper(app, dmg_path, evidence)

        manifest_path = final_dist / "BUILD_MANIFEST.json"
        status_path = final_dist / "BUILD_STATUS.txt"
        checksums_path = final_dist / "SHA256SUMS.txt"
        write_json(manifest_path, manifest)
        status_path.write_text(status_text(manifest), encoding="utf-8")
        checksum_entries = [zip_path, dmg_path, status_path, manifest_path]
        checksums_path.write_text(
            "".join(f"{sha256(path)}  {path.name}\n" for path in checksum_entries),
            encoding="utf-8",
        )

        verify_env = {"DIST_DIR": str(final_dist), "GITHUB_SHA": args.expected_commit}
        verify_result = run(
            ["bash", str(root / "scripts" / "verify_release.sh"), args.version],
            env=verify_env,
        )
        write_redacted(evidence / "release-verifier.txt", verify_result.stdout + verify_result.stderr)
        run(["xcrun", "stapler", "validate", str(dmg_path)])

        report = {
            "schemaVersion": 1,
            "status": "verified-private-candidate",
            "createdAt": utc_now(),
            "repository": "mishkacher/-MacVitals",
            "version": args.version,
            "buildNumber": args.build_number,
            "gitCommit": args.expected_commit,
            "architectures": ["arm64"],
            "identity": args.identity,
            "teamID": args.team_id,
            "hardenedRuntime": True,
            "trustedTimestamp": True,
            "applicationNotarySubmissionID": app_request_id,
            "dmgNotarySubmissionID": dmg_request_id,
            "applicationStaplerValidation": "pass",
            "dmgStaplerValidation": "pass",
            "applicationGatekeeperAssessment": "pass",
            "dmgGatekeeperAssessment": "pass",
            "publicReleaseCreated": False,
            "artifacts": {
                path.name: sha256(path)
                for path in [zip_path, dmg_path, status_path, manifest_path, checksums_path]
            },
        }
        write_json(evidence / "SIGNED_RELEASE_REPORT.json", report)
        privacy_scan(evidence)
        privacy_scan(final_dist)
        print(f"Verified private signed candidate created: {final_dist.relative_to(root)}")
        print(f"Signed release evidence created: {evidence.relative_to(root)}")
        print("No GitHub Release was created.")
    except Exception:
        write_json(
            evidence / "FAILURE.json",
            {
                "schemaVersion": 1,
                "status": "failed",
                "failedAt": utc_now(),
                "version": args.version,
                "buildNumber": args.build_number,
                "gitCommit": args.expected_commit,
                "publicReleaseCreated": False,
            },
        )
        privacy_scan(evidence)
        raise
    finally:
        if not args.keep_work and work.exists():
            shutil.rmtree(work)
    return 0


def self_test(_args: argparse.Namespace | None = None) -> int:
    valid = {
        "schemaVersion": 1,
        "product": "MacVitals",
        "version": "1.2.3",
        "buildNumber": "45",
        "bundleIdentifier": "com.mishkacher.MacVitals",
        "minimumMacOS": "13.0",
        "gitCommit": "a" * 40,
        "xcodeVersion": "Xcode 16.4; Build version 16F6",
        "architectures": ["arm64"],
        "signingStatus": "unsigned",
        "notarizationStatus": "not-notarized",
        "artifacts": {"zip": "MacVitals-1.2.3.zip", "dmg": "MacVitals-1.2.3.dmg"},
    }
    validate_release_inputs(
        "1.2.3", "45", "a" * 40,
        "Developer ID Application: Example (ABCDEFGHIJ)", "ABCDEFGHIJ",
        "KLMNOPQRST", "12345678-1234-1234-1234-123456789abc", AUTHORIZATION,
    )
    accepted = json.dumps(
        {"id": "12345678-1234-1234-1234-123456789abc", "status": "Accepted"}
    )
    assert parse_notary_response(accepted, "fixture") == (
        "12345678-1234-1234-1234-123456789abc", "Accepted"
    )
    rejected = json.dumps(
        {"id": "12345678-1234-1234-1234-123456789abc", "status": "Invalid"}
    )
    try:
        parse_notary_response(rejected, "fixture")
    except ReleaseError:
        pass
    else:
        raise AssertionError("Rejected notarization response was accepted")
    transformed = signed_manifest(valid, "1.2.3", "45", "a" * 40)
    assert transformed["signingStatus"] == "developer-id-signed"
    assert transformed["notarizationStatus"] == "ticket-present"
    assert "Signing status: developer-id-signed" in status_text(transformed)
    assert redact("/Users/alice/a /home/bob/b") == "<HOME>/a <HOME>/b"
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        key = root / "AuthKey_TEST.p8"
        key.write_text("PRIVATE KEY", encoding="utf-8")
        key.chmod(0o600)
        assert validate_api_key(key) == key.resolve()
        evidence = root / "evidence"
        evidence.mkdir()
        write_json(evidence / "report.json", {"ok": True})
        privacy_scan(evidence)
    print("Signed release pipeline self-test passed")
    return 0


def add_common(parser: argparse.ArgumentParser) -> None:
    root = Path(__file__).resolve().parent.parent
    parser.add_argument("--repository", type=Path, default=root)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--api-key", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer", required=True)
    parser.add_argument("--authorization", required=True)


def preflight_command(args: argparse.Namespace) -> int:
    preflight(args)
    print("Signed release preflight passed")
    return 0


def build_parser() -> argparse.ArgumentParser:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preflight_parser = commands.add_parser("preflight")
    add_common(preflight_parser)
    preflight_parser.set_defaults(function=preflight_command)
    run_parser = commands.add_parser("run")
    add_common(run_parser)
    run_parser.add_argument("--output-root", type=Path, default=root / "signed-dist")
    run_parser.add_argument("--work-root", type=Path, default=root / "signed-release-work")
    run_parser.add_argument("--evidence-root", type=Path, default=root / "signed-release-evidence")
    run_parser.add_argument("--keep-work", action="store_true")
    run_parser.set_defaults(function=run_release)
    test_parser = commands.add_parser("self-test")
    test_parser.set_defaults(function=self_test)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return int(args.function(args))
    except ReleaseError as error:
        fail(str(error))


if __name__ == "__main__":
    raise SystemExit(main())
