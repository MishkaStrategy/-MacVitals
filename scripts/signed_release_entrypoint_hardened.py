#!/usr/bin/env python3
"""Route isolated private signing through the hardened provenance pipeline."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

import signed_release_entrypoint as base

_original_self_test = base.self_test


def run_pipeline(args: argparse.Namespace) -> int:
    repository, output_root, work_root, evidence_root = base.validate_release_roots(
        args.repository,
        args.output_root,
        args.work_root,
        args.evidence_root,
    )
    implementation = repository / "scripts" / "sign_notarize_release_hardened.py"
    if not implementation.is_file() or implementation.is_symlink():
        raise base.PathSafetyError(
            "Hardened signed-release implementation must be a regular repository file"
        )

    command: list[str] = [
        sys.executable,
        str(implementation),
        "run",
        "--repository",
        str(repository),
        "--version",
        args.version,
        "--build-number",
        args.build_number,
        "--expected-commit",
        args.expected_commit,
        "--identity",
        args.identity,
        "--team-id",
        args.team_id,
        "--api-key",
        str(args.api_key),
        "--key-id",
        args.key_id,
        "--issuer",
        args.issuer,
        "--authorization",
        args.authorization,
        "--output-root",
        str(output_root),
        "--work-root",
        str(work_root),
        "--evidence-root",
        str(evidence_root),
    ]
    if args.keep_work:
        command.append("--keep-work")
    result = subprocess.run(command, check=False, env=os.environ.copy())
    return int(result.returncode)


def self_test(_args: argparse.Namespace | None = None) -> int:
    _original_self_test(None)
    repository = Path(__file__).resolve().parent.parent
    implementation = repository / "scripts" / "sign_notarize_release_hardened.py"
    if not implementation.is_file() or implementation.is_symlink():
        raise AssertionError("Hardened signed-release implementation is missing or unsafe")
    print("Hardened signed release entrypoint self-test passed")
    return 0


base.run_pipeline = run_pipeline
base.self_test = self_test


if __name__ == "__main__":
    raise SystemExit(base.main())
