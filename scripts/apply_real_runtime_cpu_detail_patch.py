#!/usr/bin/env python3
"""Apply a deterministic, one-shot validation hook that opens the real CPU detail window.

The shipping repository source is never modified. The hook is applied only inside detached
measurement worktrees and is identical for baseline and candidate revisions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

EXPECTED_APP_DELEGATE_BLOB = "f334b3d4558ec0157be3aba498a42938921b3eaa"
TARGET_PATH = Path("MacVitals/App/AppDelegate.swift")
CALL_NEEDLE = '''    LifecycleMonitor.shared.start(coordinator: coordinator)\n    Logger.lifecycle.info("MacVitals started")\n'''
CALL_REPLACEMENT = '''    LifecycleMonitor.shared.start(coordinator: coordinator)\n    runValidationCPUDetailHookIfRequested()\n    Logger.lifecycle.info("MacVitals started")\n'''
METHOD_NEEDLE = '''  func applicationDidBecomeActive(_ notification: Notification) {\n'''
METHOD_REPLACEMENT = '''  private func runValidationCPUDetailHookIfRequested() {\n    let environment = ProcessInfo.processInfo.environment\n    guard\n      environment["MACVITALS_VALIDATION_OPEN_CPU_DETAIL"] == "1",\n      let readyPath = environment["MACVITALS_VALIDATION_READY_FILE"],\n      !readyPath.isEmpty\n    else { return }\n\n    Task { @MainActor [weak self] in\n      try? await Task.sleep(for: .seconds(3))\n      guard let self else { return }\n      MetricDetailWindowPresenter.shared.show(\n        kind: .cpu,\n        coordinator: coordinator,\n        settings: settings,\n        fanControl: fanControl)\n      try? await Task.sleep(for: .seconds(5))\n      try? Data("cpu-detail-ready\\n".utf8).write(\n        to: URL(fileURLWithPath: readyPath),\n        options: .atomic)\n    }\n  }\n\n  func applicationDidBecomeActive(_ notification: Notification) {\n'''


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(root: Path, path: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "hash-object", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit("could not hash AppDelegate source")
    return result.stdout.strip()


def patched_text(text: str) -> str:
    if text.count(CALL_NEEDLE) != 1:
        raise SystemExit("validation launch-hook call insertion point is not unique")
    if text.count(METHOD_NEEDLE) != 1:
        raise SystemExit("validation launch-hook method insertion point is not unique")
    if "MACVITALS_VALIDATION_OPEN_CPU_DETAIL" in text:
        raise SystemExit("validation launch hook is already present")
    text = text.replace(CALL_NEEDLE, CALL_REPLACEMENT, 1)
    text = text.replace(METHOD_NEEDLE, METHOD_REPLACEMENT, 1)
    return text


def apply(root: Path, report_path: Path) -> None:
    target = root / TARGET_PATH
    if not target.is_file() or target.is_symlink():
        raise SystemExit("AppDelegate source is missing or unsafe")
    original_blob = git_blob(root, TARGET_PATH)
    if original_blob != EXPECTED_APP_DELEGATE_BLOB:
        raise SystemExit(
            f"unexpected AppDelegate blob: {original_blob}; expected {EXPECTED_APP_DELEGATE_BLOB}"
        )
    original = target.read_bytes()
    text = original.decode("utf-8")
    patched = patched_text(text).encode("utf-8")
    target.write_bytes(patched)
    report = {
        "schemaVersion": 1,
        "target": str(TARGET_PATH),
        "expectedOriginalGitBlob": EXPECTED_APP_DELEGATE_BLOB,
        "originalSha256": sha256(original),
        "patchedSha256": sha256(patched),
        "hook": "one-shot-open-existing-cpu-detail-then-write-ready-marker",
        "preMeasurementSleepsSeconds": [3, 5],
        "recurringValidationTimer": False,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def self_test() -> None:
    fixture = (
        "header\n"
        + CALL_NEEDLE
        + "middle\n"
        + METHOD_NEEDLE
        + "tail\n"
    )
    value = patched_text(fixture)
    assert value.count("runValidationCPUDetailHookIfRequested()") == 2
    assert value.count("MACVITALS_VALIDATION_OPEN_CPU_DETAIL") == 1
    assert value.count("MetricDetailWindowPresenter.shared.show") == 1
    assert value.count("Task.sleep") == 2
    assert "while " not in METHOD_REPLACEMENT
    assert "Timer" not in METHOD_REPLACEMENT
    with tempfile.TemporaryDirectory() as temporary:
        report = Path(temporary) / "report.json"
        report.write_text(json.dumps({"ok": True}) + "\n", encoding="utf-8")
        assert json.loads(report.read_text(encoding="utf-8"))["ok"] is True
    print("Real-runtime CPU detail patch self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--root", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.root is None or args.report is None:
        parser.error("--root and --report are required unless --self-test is used")
    apply(args.root.resolve(), args.report.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
