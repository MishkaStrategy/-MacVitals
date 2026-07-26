#!/usr/bin/env python3
"""Repair redacted Instruments TOC XML without restoring private paths."""

from __future__ import annotations

import argparse
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

_XML_PLACEHOLDER_REPLACEMENTS = {
    'path="<HOME>': 'path="HOME_REDACTED',
    'path="<TEMP>': 'path="TEMP_REDACTED',
    'path="<TRACE_WORKSPACE>': 'path="TRACE_WORKSPACE_REDACTED',
    'path="<USER>': 'path="USER_REDACTED',
    'path="<HOST>': 'path="HOST_REDACTED',
}


def repair_xml(path: Path) -> None:
    if path.is_symlink() or not path.is_file() or path.stat().st_nlink != 1:
        raise RuntimeError(f"Unsafe XML evidence file: {path}")
    text = path.read_text(encoding="utf-8", errors="strict")
    for source, replacement in _XML_PLACEHOLDER_REPLACEMENTS.items():
        text = text.replace(source, replacement)
    try:
        ET.fromstring(text)
    except ET.ParseError as error:
        raise RuntimeError(f"Sanitized Instruments XML is invalid: {path}: {error}") from error
    path.write_text(text, encoding="utf-8")


def repair_tree(root: Path) -> int:
    if root.is_symlink() or not root.is_dir():
        raise RuntimeError("Physical evidence root is missing or unsafe")
    repaired = 0
    for path in sorted(root.rglob("*-toc.xml")):
        repair_xml(path)
        repaired += 1
    return repaired


def self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        valid = root / "time-profiler-toc.xml"
        valid.write_text(
            '<trace-toc><process path="<HOME>/Library/Test.app"/></trace-toc>\n',
            encoding="utf-8",
        )
        assert repair_tree(root) == 1
        repaired = valid.read_text(encoding="utf-8")
        assert "<HOME>" not in repaired
        assert "HOME_REDACTED/Library/Test.app" in repaired
        ET.fromstring(repaired)

        invalid = root / "leaks-toc.xml"
        invalid.write_text('<trace-toc><process path="<HOME>"\n', encoding="utf-8")
        try:
            repair_xml(invalid)
        except RuntimeError:
            pass
        else:
            raise AssertionError("Malformed sanitized XML was accepted")
    print("Sanitized Instruments XML repair self-test passed")


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
    print(f"Validated {repaired} sanitized Instruments TOC XML file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
