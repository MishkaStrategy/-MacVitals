#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ENTRY_RE = re.compile(
    r'^\s*"(?P<key>(?:\\.|[^"\\])*)"\s*=\s*"(?P<value>(?:\\.|[^"\\])*)"\s*;\s*$'
)
FORMAT_RE = re.compile(
    r'%(?!%)(?:\d+\$)?(?:[-+ 0#]*)?(?:\d+|\*)?(?:\.\d+|\.\*)?[hlLzjtq]*[@diuoxXfFeEgGcCsSp]'
)


@dataclass(frozen=True)
class Entry:
    key: str
    value: str
    line: int


def decode(value: str) -> str:
    return bytes(value, "utf-8").decode("unicode_escape") if "\\u" in value else value


def parse(path: Path) -> dict[str, Entry]:
    entries: dict[str, Entry] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*"):
            continue
        match = ENTRY_RE.match(line)
        if not match:
            raise ValueError(f"{path}:{line_number}: invalid .strings syntax")
        key = decode(match.group("key"))
        value = decode(match.group("value"))
        if key in entries:
            previous = entries[key]
            raise ValueError(
                f"{path}:{line_number}: duplicate key {key!r}; first declared on line {previous.line}"
            )
        entries[key] = Entry(key=key, value=value, line=line_number)
    return entries


def placeholders(value: str) -> list[str]:
    without_escaped_percent = value.replace("%%", "")
    return FORMAT_RE.findall(without_escaped_percent)


def validate(base_path: Path, localized_path: Path) -> list[str]:
    errors: list[str] = []
    base = parse(base_path)
    localized = parse(localized_path)

    missing = sorted(set(base) - set(localized))
    extra = sorted(set(localized) - set(base))
    if missing:
        errors.append(f"{localized_path}: missing keys: {missing}")
    if extra:
        errors.append(f"{localized_path}: extra keys: {extra}")

    for key in sorted(set(base) & set(localized)):
        base_formats = placeholders(base[key].value)
        localized_formats = placeholders(localized[key].value)
        if base_formats != localized_formats:
            errors.append(
                f"{localized_path}:{localized[key].line}: placeholder mismatch for {key!r}: "
                f"expected {base_formats}, found {localized_formats}"
            )
        if not localized[key].value.strip():
            errors.append(f"{localized_path}:{localized[key].line}: empty translation for {key!r}")

    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    base = root / "MacVitals/Resources/en.lproj/Localizable.strings"
    localized_files = sorted(
        path
        for path in (root / "MacVitals/Resources").glob("*.lproj/Localizable.strings")
        if path != base
    )

    if not base.is_file():
        print(f"Missing base localization: {base}", file=sys.stderr)
        return 1
    if not localized_files:
        print("No localized Localizable.strings files found", file=sys.stderr)
        return 1

    errors: list[str] = []
    try:
        parse(base)
        for path in localized_files:
            errors.extend(validate(base, path))
    except (OSError, UnicodeError, ValueError) as error:
        errors.append(str(error))

    if errors:
        print("Localization validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        f"Localization validation passed: base={base.name}, locales={len(localized_files)}, "
        f"keys={len(parse(base))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
