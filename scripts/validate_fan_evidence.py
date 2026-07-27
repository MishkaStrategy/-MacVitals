#!/usr/bin/env python3
"""Validate read-only MacVitals AppleSMC fan evidence."""

from __future__ import annotations

import argparse
import json
import math
import re
import tempfile
from pathlib import Path
from typing import Any, NoReturn

MAX_EVIDENCE_BYTES = 1024 * 1024
EXPECTED_ROOT_KEYS = {
    "schemaVersion",
    "recordedAt",
    "architecture",
    "source",
    "availability",
    "quality",
    "unit",
    "fanCount",
    "fans",
    "message",
}
EXPECTED_FAN_KEYS = {
    "index",
    "currentRPM",
    "targetRPM",
    "minimumRPM",
    "maximumRPM",
    "mode",
}
SYSTEM_CONTROLLED_MODES = {"automatic", "system"}
ISO8601_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\Z")
HOME_RE = re.compile(r"/(?:Users|home)/[^/\s]+")


class ValidationError(RuntimeError):
    pass


def fail(message: str) -> NoReturn:
    raise ValidationError(message)


def finite_number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{label} must be a number")
    number = float(value)
    if not math.isfinite(number):
        fail(f"{label} must be finite")
    return number


def read_document(path: Path) -> dict[str, Any]:
    path = path.expanduser()
    if not path.exists() or path.is_symlink() or not path.is_file():
        fail("Fan evidence must be a regular non-symlink file")
    size = path.stat().st_size
    if size <= 0 or size > MAX_EVIDENCE_BYTES:
        fail("Fan evidence size is invalid")
    raw = path.read_text(encoding="utf-8", errors="strict")
    if "\x00" in raw or HOME_RE.search(raw):
        fail("Fan evidence contains unsafe or private text")
    try:
        value = json.loads(
            raw,
            parse_constant=lambda constant: fail(
                f"Fan evidence contains non-standard numeric constant: {constant}"
            ),
        )
    except json.JSONDecodeError as error:
        raise ValidationError(f"Fan evidence is not valid JSON: {error}") from error
    if not isinstance(value, dict):
        fail("Fan evidence root must be an object")
    return value


def validate_document(
    value: dict[str, Any], *, require_available: bool, require_automatic: bool
) -> None:
    if set(value) != EXPECTED_ROOT_KEYS:
        fail("Fan evidence root key scope is invalid")
    if value.get("schemaVersion") != 1:
        fail("Fan evidence schemaVersion must be 1")
    if value.get("architecture") != "arm64":
        fail("Fan evidence architecture must be exactly arm64")
    if value.get("source") != "appleSMC":
        fail("Fan evidence source must be appleSMC")
    if value.get("unit") != "RPM":
        fail("Fan evidence unit must be RPM")
    if value.get("quality") != "experimental":
        fail("Fan evidence quality must be experimental")
    recorded_at = value.get("recordedAt")
    if not isinstance(recorded_at, str) or not ISO8601_RE.fullmatch(recorded_at):
        fail("Fan evidence recordedAt must be an ISO-8601 UTC timestamp")
    availability = value.get("availability")
    if availability not in {
        "available",
        "temporarilyUnavailable",
        "unsupported",
        "providerError",
    }:
        fail("Fan evidence availability is invalid")
    if require_available and availability != "available":
        fail(f"Fan evidence is not available: {availability}")
    message = value.get("message")
    if not isinstance(message, str) or len(message) > 1024:
        fail("Fan evidence message is invalid")

    fans = value.get("fans")
    fan_count = value.get("fanCount")
    if isinstance(fan_count, bool) or not isinstance(fan_count, int):
        fail("fanCount must be an integer")
    if not isinstance(fans, list) or fan_count != len(fans):
        fail("fanCount does not match the fans array")
    if fan_count < 0 or fan_count > 8:
        fail("fanCount is outside the supported range")
    if require_available and fan_count == 0:
        fail("Available fan evidence must contain at least one fan")

    seen: set[int] = set()
    for position, fan in enumerate(fans):
        if not isinstance(fan, dict) or set(fan) != EXPECTED_FAN_KEYS:
            fail(f"Fan {position} key scope is invalid")
        index = fan.get("index")
        if isinstance(index, bool) or not isinstance(index, int):
            fail(f"Fan {position} index must be an integer")
        if index in seen or index != position:
            fail("Fan indexes must be unique and contiguous from zero")
        seen.add(index)

        minimum = finite_number(fan.get("minimumRPM"), f"Fan {index} minimumRPM")
        maximum = finite_number(fan.get("maximumRPM"), f"Fan {index} maximumRPM")
        current = finite_number(fan.get("currentRPM"), f"Fan {index} currentRPM")
        target = finite_number(fan.get("targetRPM"), f"Fan {index} targetRPM")
        if not (0 < minimum < maximum <= 20_000):
            fail(f"Fan {index} hardware RPM range is invalid")
        for label, number in (("currentRPM", current), ("targetRPM", target)):
            if number != 0 and not (minimum <= number <= maximum):
                fail(f"Fan {index} {label} is outside the hardware range")

        mode = fan.get("mode")
        if mode not in {"automatic", "system", "manual", "unknown"}:
            fail(f"Fan {index} mode is invalid")
        if require_automatic and mode not in SYSTEM_CONTROLLED_MODES:
            fail(f"Fan {index} is not controlled by macOS")


def validate_path(
    path: Path, *, require_available: bool = False, require_automatic: bool = False
) -> None:
    validate_document(
        read_document(path),
        require_available=require_available,
        require_automatic=require_automatic,
    )


def valid_fixture() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "recordedAt": "2026-07-27T12:00:00Z",
        "architecture": "arm64",
        "source": "appleSMC",
        "availability": "available",
        "quality": "experimental",
        "unit": "RPM",
        "fanCount": 2,
        "fans": [
            {
                "index": 0,
                "currentRPM": 0.0,
                "targetRPM": 0.0,
                "minimumRPM": 1200.0,
                "maximumRPM": 6000.0,
                "mode": "automatic",
            },
            {
                "index": 1,
                "currentRPM": 2000.0,
                "targetRPM": 2200.0,
                "minimumRPM": 1300.0,
                "maximumRPM": 6100.0,
                "mode": "system",
            },
        ],
        "message": "",
    }


def expect_invalid(value: dict[str, Any], root: Path, label: str) -> None:
    path = root / f"{label}.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    try:
        validate_path(path, require_available=True, require_automatic=True)
    except ValidationError:
        return
    raise AssertionError(f"Invalid fan evidence was accepted: {label}")


def self_test() -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        valid = root / "valid.json"
        valid.write_text(json.dumps(valid_fixture()), encoding="utf-8")
        validate_path(valid, require_available=True, require_automatic=True)

        unavailable = valid_fixture()
        unavailable["availability"] = "providerError"
        expect_invalid(unavailable, root, "unavailable")

        manual = valid_fixture()
        manual["fans"][0]["mode"] = "manual"
        expect_invalid(manual, root, "manual")

        unknown = valid_fixture()
        unknown["fans"][0]["mode"] = "unknown"
        expect_invalid(unknown, root, "unknown")

        out_of_range = valid_fixture()
        out_of_range["fans"][0]["currentRPM"] = 7000.0
        expect_invalid(out_of_range, root, "out-of-range")

        duplicate = valid_fixture()
        duplicate["fans"][1]["index"] = 0
        expect_invalid(duplicate, root, "duplicate")

        wrong_source = valid_fixture()
        wrong_source["source"] = "iokitRegistry"
        expect_invalid(wrong_source, root, "wrong-source")

        nan_path = root / "nan.json"
        nan_path.write_text(json.dumps(valid_fixture()).replace("2000.0", "NaN", 1), encoding="utf-8")
        try:
            validate_path(nan_path, require_available=True, require_automatic=True)
        except ValidationError:
            pass
        else:
            raise AssertionError("NaN fan evidence was accepted")

    print("Fan evidence validator self-test passed")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path, nargs="?")
    parser.add_argument("--require-available", action="store_true")
    parser.add_argument("--require-automatic", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    if args.evidence is None:
        raise SystemExit("evidence is required unless --self-test is used")
    try:
        validate_path(
            args.evidence,
            require_available=args.require_available,
            require_automatic=args.require_automatic,
        )
    except ValidationError as error:
        print(f"Fan evidence validation failed: {error}", file=__import__("sys").stderr)
        return 1
    print("Read-only AppleSMC fan evidence is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
