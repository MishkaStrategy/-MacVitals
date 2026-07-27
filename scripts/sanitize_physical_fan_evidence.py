#!/usr/bin/env python3
"""Sanitize and fail closed before uploading physical fan probe evidence."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from pathlib import Path
from typing import NoReturn

MAX_TOTAL_BYTES = 20 * 1024 * 1024
HOME_RE = re.compile(r"/(?:Users|home)/[^/\s<]+")
TEMP_RE = re.compile(
    r"(?:/private/(?:tmp|var)|/var/folders|/tmp)(?:/[^\s<]+)+"
)


class SanitizationError(RuntimeError):
    pass


def fail(message: str) -> NoReturn:
    raise SanitizationError(message)


def replacement_values() -> list[tuple[str, str]]:
    values = [
        (os.environ.get("REDACT_WORKSPACE", ""), "<WORKSPACE>"),
        (os.environ.get("REDACT_HOME", ""), "<HOME>"),
        (os.environ.get("REDACT_HOST", ""), "<HOST>"),
    ]
    user = os.environ.get("REDACT_USER", "")
    if len(user) >= 3:
        values.append((user, "<USER>"))
    return [(source, target) for source, target in values if source]


def clean(text: str, replacements: list[tuple[str, str]]) -> str:
    for source, target in replacements:
        text = text.replace(source, target)
    text = HOME_RE.sub("<HOME>", text)
    return TEMP_RE.sub("<TEMP>", text)


def verify_clean(
    text: str, relative: Path, replacements: list[tuple[str, str]]
) -> None:
    for source, _ in replacements:
        if source in text:
            fail(f"Private value remained in {relative}")
    if HOME_RE.search(text) or TEMP_RE.search(text):
        fail(f"Private path remained in {relative}")


def sanitize(root: Path, replacements: list[tuple[str, str]]) -> None:
    if not root.exists() or root.is_symlink() or not root.is_dir():
        fail("Fan evidence root must be a regular non-symlink directory")

    total = 0
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if path.is_symlink():
            fail(f"Symlink is forbidden in fan evidence: {relative}")
        if path.is_dir():
            continue
        if not path.is_file() or path.stat().st_nlink != 1:
            fail(f"Non-regular fan evidence entry: {relative}")
        total += path.stat().st_size
        if total > MAX_TOTAL_BYTES:
            fail("Fan evidence exceeds the total size limit")
        payload = path.read_bytes()
        if b"\x00" in payload:
            fail(f"Binary fan evidence is forbidden: {relative}")
        try:
            text = payload.decode("utf-8", errors="strict")
        except UnicodeDecodeError as error:
            raise SanitizationError(f"Fan evidence is not UTF-8 text: {relative}") from error
        sanitized = clean(text, replacements)
        verify_clean(sanitized, relative, replacements)
        path.write_text(sanitized, encoding="utf-8")

    marker = root / "PRIVACY_SCAN_PASSED.txt"
    marker.write_text("privacy-scan=passed\n", encoding="utf-8")


def expect_failure(root: Path, replacements: list[tuple[str, str]]) -> None:
    try:
        sanitize(root, replacements)
    except SanitizationError:
        return
    raise AssertionError("Unsafe fan evidence was accepted")


def self_test() -> int:
    replacements = [
        ("/Users/alice/work/project", "<WORKSPACE>"),
        ("/Users/alice", "<HOME>"),
        ("alice", "<USER>"),
        ("alice-mac", "<HOST>"),
    ]
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory) / "safe"
        root.mkdir()
        log = root / "build.log"
        log.write_text(
            "/Users/alice/work/project/build\n"
            "/private/tmp/probe.123/output\n"
            "/private/var/folders/aa/cache/file\n"
            "/var/folders/ld/session/cache.noindex\n"
            "/tmp/macvitals-probe/result\n"
            "alice-mac alice\n",
            encoding="utf-8",
        )
        sanitize(root, replacements)
        text = log.read_text(encoding="utf-8")
        assert "/Users/" not in text
        assert "/private/tmp/" not in text
        assert "/private/var/" not in text
        assert "/var/folders/" not in text
        assert "/tmp/" not in text
        assert "alice-mac" not in text
        assert text.count("<TEMP>") == 4
        assert (root / "PRIVACY_SCAN_PASSED.txt").read_text(encoding="utf-8") == (
            "privacy-scan=passed\n"
        )

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory) / "binary"
        root.mkdir()
        (root / "bad.log").write_bytes(b"text\x00binary")
        expect_failure(root, [])

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory) / "symlink"
        root.mkdir()
        target = Path(directory) / "target.log"
        target.write_text("safe\n", encoding="utf-8")
        (root / "linked.log").symlink_to(target)
        expect_failure(root, [])

    print("Physical fan evidence sanitization self-test passed")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, nargs="?")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    if args.root is None:
        raise SystemExit("root is required unless --self-test is used")
    try:
        sanitize(args.root.resolve(), replacement_values())
    except SanitizationError as error:
        print(f"Fan evidence sanitization failed: {error}", file=__import__("sys").stderr)
        return 1
    print("Physical fan evidence privacy scan passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
