#!/usr/bin/env python3
"""Repair and fail-closed sanitize physical evidence without restoring private paths."""

from __future__ import annotations

import argparse
import os
import re
import socket
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

_XML_PLACEHOLDER_REPLACEMENTS = {
    'path="<HOME>': 'path="HOME_REDACTED',
    'path="<TEMP>': 'path="TEMP_REDACTED',
    'path="<TRACE_WORKSPACE>': 'path="TRACE_WORKSPACE_REDACTED',
    'path="<WORKSPACE>': 'path="WORKSPACE_REDACTED',
    'path="<USER>': 'path="USER_REDACTED',
    'path="<HOST>': 'path="HOST_REDACTED',
    'path="<RUNNER>': 'path="RUNNER_REDACTED',
}
_HOME_PATH_RE = re.compile(r"/(?:Users|home)/[^/\s\"'<>]+")
_TEMP_PATH_RE = re.compile(r"/private/(?:tmp|var)/[^\s\"'<>]+")
_REDACTED_RUNNER_TAIL_RE = re.compile(
    r"(?:HOME_REDACTED|<HOME>)/(?:GitHubActionsRunners|actions-runner)/[^\s\"'<>]+"
)
_FORBIDDEN_RUNNER_STRUCTURE_RE = re.compile(
    r"(?:GitHubActionsRunners|actions-runner|/_work/|\\_work\\)", re.IGNORECASE
)
_MAX_TEXT_FILE_BYTES = 32 * 1024 * 1024
_MAX_TREE_BYTES = 128 * 1024 * 1024


def _literal_replacements() -> list[tuple[str, str]]:
    candidates = [
        (os.environ.get("GITHUB_WORKSPACE", ""), "<WORKSPACE>"),
        (os.environ.get("RUNNER_NAME", ""), "<RUNNER>"),
        (str(Path.home()), "<HOME>"),
        (socket.gethostname(), "<HOST>"),
        (os.environ.get("USER", ""), "<USER>"),
    ]
    unique: dict[str, str] = {}
    for source, replacement in candidates:
        if source and len(source) >= 3:
            unique[source] = replacement
    return sorted(unique.items(), key=lambda item: len(item[0]), reverse=True)


def sanitize_text(text: str) -> str:
    for source, replacement in _literal_replacements():
        text = text.replace(source, replacement)
    text = _HOME_PATH_RE.sub("<HOME>", text)
    text = _TEMP_PATH_RE.sub("<TEMP>", text)
    text = _REDACTED_RUNNER_TAIL_RE.sub("<WORKSPACE>", text)
    return text


def verify_private_paths_absent(text: str, label: str) -> None:
    forbidden = [source for source, _ in _literal_replacements()]
    if any(source in text for source in forbidden):
        raise RuntimeError(f"Physical evidence retains a private literal: {label}")
    if _HOME_PATH_RE.search(text) or _TEMP_PATH_RE.search(text):
        raise RuntimeError(f"Physical evidence retains a private path: {label}")
    if _REDACTED_RUNNER_TAIL_RE.search(text) or _FORBIDDEN_RUNNER_STRUCTURE_RE.search(text):
        raise RuntimeError(f"Physical evidence retains runner workspace structure: {label}")


def sanitize_tree(root: Path) -> int:
    if root.is_symlink() or not root.is_dir():
        raise RuntimeError("Physical evidence root is missing or unsafe")
    sanitized = 0
    total = 0
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise RuntimeError(f"Symlink in physical evidence: {path}")
        if path.is_dir():
            continue
        if not path.is_file() or path.stat().st_nlink != 1:
            raise RuntimeError(f"Unsafe physical evidence file: {path}")
        size = path.stat().st_size
        total += size
        if size > _MAX_TEXT_FILE_BYTES or total > _MAX_TREE_BYTES:
            raise RuntimeError("Physical evidence exceeds the text sanitization limit")
        payload = path.read_bytes()
        if b"\x00" in payload:
            raise RuntimeError(f"Binary physical evidence is forbidden: {path}")
        text = payload.decode("utf-8", errors="strict")
        cleaned = sanitize_text(text)
        verify_private_paths_absent(cleaned, str(path.relative_to(root)))
        path.write_text(cleaned, encoding="utf-8")
        sanitized += 1
    return sanitized


def repair_xml(path: Path) -> None:
    if path.is_symlink() or not path.is_file() or path.stat().st_nlink != 1:
        raise RuntimeError(f"Unsafe XML evidence file: {path}")
    text = path.read_text(encoding="utf-8", errors="strict")
    for source, replacement in _XML_PLACEHOLDER_REPLACEMENTS.items():
        text = text.replace(source, replacement)
    verify_private_paths_absent(text, path.name)
    try:
        ET.fromstring(text)
    except ET.ParseError as error:
        raise RuntimeError(f"Sanitized Instruments XML is invalid: {path}: {error}") from error
    path.write_text(text, encoding="utf-8")


def repair_tree(root: Path) -> int:
    sanitize_tree(root)
    repaired = 0
    for path in sorted(root.rglob("*-toc.xml")):
        repair_xml(path)
        repaired += 1
    marker = root / "PRIVACY_SCAN_PASSED.txt"
    marker.write_text("privacy-scan=passed\n", encoding="utf-8")
    return repaired


def self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        valid = root / "time-profiler-toc.xml"
        valid.write_text(
            '<trace-toc><process path="<HOME>/Library/Test.app"/></trace-toc>\n',
            encoding="utf-8",
        )
        collector = root / "collector.log"
        collector.write_text(
            "summary at HOME_REDACTED/GitHubActionsRunners/account/runner/_work/repo/repo/out.json\n",
            encoding="utf-8",
        )
        assert repair_tree(root) == 1
        repaired = valid.read_text(encoding="utf-8")
        assert "<HOME>" not in repaired
        assert "HOME_REDACTED/Library/Test.app" in repaired
        ET.fromstring(repaired)
        cleaned_collector = collector.read_text(encoding="utf-8")
        assert "GitHubActionsRunners" not in cleaned_collector
        assert "_work" not in cleaned_collector
        assert "<WORKSPACE>" in cleaned_collector
        assert (root / "PRIVACY_SCAN_PASSED.txt").read_text(encoding="utf-8") == "privacy-scan=passed\n"

        invalid = root / "leaks-toc.xml"
        invalid.write_text('<trace-toc><process path="<HOME>"\n', encoding="utf-8")
        try:
            repair_xml(invalid)
        except RuntimeError:
            pass
        else:
            raise AssertionError("Malformed sanitized XML was accepted")

        residual = root / "residual.log"
        residual.write_text("HOME_REDACTED/GitHubActionsRunners/a/b/_work/r/r/file\n", encoding="utf-8")
        cleaned = sanitize_text(residual.read_text(encoding="utf-8"))
        verify_private_paths_absent(cleaned, residual.name)
        assert "GitHubActionsRunners" not in cleaned
    print("Sanitized physical evidence repair self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.root is None:
        parser.error("root is required unless --self-test is used")
    repaired = repair_tree(args.root.resolve())
    print(f"Sanitized physical evidence and validated {repaired} Instruments TOC XML file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
