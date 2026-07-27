#!/usr/bin/env python3
"""Validate the exact MacVitals fan-control helper embedded in an application bundle."""

from __future__ import annotations

import argparse
import os
import plistlib
import stat
import struct
import tempfile
from pathlib import Path

HELPER_RELATIVE_PATH = Path("Contents/Resources/MacVitalsFanHelper")
PLIST_RELATIVE_PATH = Path(
    "Contents/Library/LaunchDaemons/com.mishkacher.MacVitals.FanControl.plist"
)
SERVICE_NAME = "com.mishkacher.MacVitals.FanControl"
APP_BUNDLE_ID = "com.mishkacher.MacVitals"
BUNDLE_PROGRAM = "Contents/Resources/MacVitalsFanHelper"
MACHO_64_MAGIC = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C


class ValidationError(RuntimeError):
    pass


def strict_regular_file(path: Path, label: str, *, executable: bool = False) -> Path:
    if not path.exists() or path.is_symlink() or not path.is_file():
        raise ValidationError(f"{label} must be a regular non-symlink file")
    mode = stat.S_IMODE(path.stat().st_mode)
    if executable and mode & 0o111 == 0:
        raise ValidationError(f"{label} is not executable")
    if path.stat().st_size <= 0:
        raise ValidationError(f"{label} is empty")
    return path


def validate_arm64_macho(path: Path) -> None:
    with path.open("rb") as handle:
        header = handle.read(8)
    if len(header) != 8:
        raise ValidationError("Fan helper Mach-O header is truncated")
    magic, cpu_type = struct.unpack("<II", header)
    if magic != MACHO_64_MAGIC:
        raise ValidationError("Fan helper must be a thin 64-bit Mach-O executable")
    if cpu_type != CPU_TYPE_ARM64:
        raise ValidationError(
            f"Fan helper must contain only arm64; found CPU type 0x{cpu_type:08x}"
        )


def validate_plist(path: Path) -> None:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValidationError(f"Fan helper launch daemon plist is invalid: {error}") from error
    if not isinstance(value, dict):
        raise ValidationError("Fan helper launch daemon plist root must be a dictionary")

    expected_exact = {
        "Label": SERVICE_NAME,
        "BundleProgram": BUNDLE_PROGRAM,
        "AssociatedBundleIdentifiers": [APP_BUNDLE_ID],
        "RunAtLoad": False,
        "KeepAlive": False,
        "ProcessType": "Interactive",
    }
    for key, expected in expected_exact.items():
        if value.get(key) != expected:
            raise ValidationError(
                f"Fan helper launch daemon plist mismatch for {key}: "
                f"expected {expected!r}, found {value.get(key)!r}"
            )
    if value.get("MachServices") != {SERVICE_NAME: True}:
        raise ValidationError("Fan helper launch daemon plist has an unexpected MachServices scope")

    forbidden = {
        "Program",
        "ProgramArguments",
        "UserName",
        "GroupName",
        "RootDirectory",
        "EnvironmentVariables",
        "WatchPaths",
        "QueueDirectories",
        "Sockets",
        "inetdCompatibility",
    }
    present = sorted(forbidden.intersection(value))
    if present:
        raise ValidationError(
            "Fan helper launch daemon plist contains forbidden keys: " + ", ".join(present)
        )


def validate_bundle(app: Path) -> None:
    app = app.expanduser().resolve()
    if not app.is_dir() or app.is_symlink() or app.name != "MacVitals.app":
        raise ValidationError("MacVitals.app must be a regular application bundle directory")
    helper = strict_regular_file(
        app / HELPER_RELATIVE_PATH, "Fan helper", executable=True
    )
    plist = strict_regular_file(app / PLIST_RELATIVE_PATH, "Fan helper launch daemon plist")
    validate_arm64_macho(helper)
    validate_plist(plist)


def macho_header(cpu_type: int = CPU_TYPE_ARM64, magic: int = MACHO_64_MAGIC) -> bytes:
    return struct.pack("<II", magic, cpu_type) + bytes(24)


def fixture(root: Path) -> Path:
    app = root / "MacVitals.app"
    helper = app / HELPER_RELATIVE_PATH
    plist = app / PLIST_RELATIVE_PATH
    helper.parent.mkdir(parents=True)
    plist.parent.mkdir(parents=True)
    helper.write_bytes(macho_header())
    helper.chmod(0o755)
    with plist.open("wb") as handle:
        plistlib.dump(
            {
                "Label": SERVICE_NAME,
                "BundleProgram": BUNDLE_PROGRAM,
                "MachServices": {SERVICE_NAME: True},
                "AssociatedBundleIdentifiers": [APP_BUNDLE_ID],
                "RunAtLoad": False,
                "KeepAlive": False,
                "ProcessType": "Interactive",
            },
            handle,
        )
    return app


def expect_invalid(app: Path) -> None:
    try:
        validate_bundle(app)
    except ValidationError:
        return
    raise AssertionError("Invalid fan helper bundle was accepted")


def self_test() -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        valid = fixture(root / "valid")
        validate_bundle(valid)

        missing_helper = fixture(root / "missing-helper")
        (missing_helper / HELPER_RELATIVE_PATH).unlink()
        expect_invalid(missing_helper)

        symlink_helper = fixture(root / "symlink-helper")
        helper = symlink_helper / HELPER_RELATIVE_PATH
        helper.unlink()
        helper.symlink_to("/tmp/foreign-helper")
        expect_invalid(symlink_helper)

        not_executable = fixture(root / "not-executable")
        (not_executable / HELPER_RELATIVE_PATH).chmod(0o644)
        expect_invalid(not_executable)

        x86_helper = fixture(root / "x86-helper")
        (x86_helper / HELPER_RELATIVE_PATH).write_bytes(macho_header(cpu_type=0x01000007))
        expect_invalid(x86_helper)

        fat_helper = fixture(root / "fat-helper")
        (fat_helper / HELPER_RELATIVE_PATH).write_bytes(macho_header(magic=0xCAFEBABE))
        expect_invalid(fat_helper)

        foreign_service = fixture(root / "foreign-service")
        plist = foreign_service / PLIST_RELATIVE_PATH
        with plist.open("rb") as handle:
            value = plistlib.load(handle)
        value["MachServices"] = {"com.example.Foreign": True}
        with plist.open("wb") as handle:
            plistlib.dump(value, handle)
        expect_invalid(foreign_service)

        arbitrary_arguments = fixture(root / "arguments")
        plist = arbitrary_arguments / PLIST_RELATIVE_PATH
        with plist.open("rb") as handle:
            value = plistlib.load(handle)
        value["ProgramArguments"] = ["/bin/sh", "-c", "id"]
        with plist.open("wb") as handle:
            plistlib.dump(value, handle)
        expect_invalid(arbitrary_arguments)

    print("Fan helper bundle validator self-test passed")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, nargs="?")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    if args.app is None:
        raise SystemExit("app is required unless --self-test is used")
    try:
        validate_bundle(args.app)
    except ValidationError as error:
        print(f"Fan helper bundle validation failed: {error}", file=__import__("sys").stderr)
        return 1
    print("Fan helper path, launchd scope and arm64 Mach-O identity are valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
