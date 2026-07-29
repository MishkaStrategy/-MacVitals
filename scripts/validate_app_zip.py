#!/usr/bin/env python3
"""Validate a MacVitals application ZIP before any filesystem extraction."""

from __future__ import annotations

import argparse
import stat
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

MAX_ARCHIVE_BYTES = 256 * 1024 * 1024
MAX_MEMBER_COUNT = 4096
MAX_MEMBER_UNCOMPRESSED_BYTES = 512 * 1024 * 1024
MAX_TOTAL_UNCOMPRESSED_BYTES = 768 * 1024 * 1024
MAX_TOTAL_COMPRESSED_BYTES = 256 * 1024 * 1024
MAX_COMPRESSION_RATIO = 100.0
RATIO_CHECK_MINIMUM_BYTES = 1024 * 1024
ALLOWED_COMPRESSION = {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}
REQUIRED_FILES = {
    "MacVitals.app/Contents/Info.plist",
    "MacVitals.app/Contents/MacOS/MacVitals",
    "MacVitals.app/Contents/Resources/AppIcon.icns",
    "MacVitals.app/Contents/Resources/en.lproj/Localizable.strings",
    "MacVitals.app/Contents/Resources/ru.lproj/Localizable.strings",
}


class ValidationError(RuntimeError):
    pass


def member_mode(info: zipfile.ZipInfo) -> int:
    return (info.external_attr >> 16) & 0xFFFF


def is_directory(info: zipfile.ZipInfo) -> bool:
    mode = member_mode(info)
    return info.is_dir() or stat.S_ISDIR(mode)


def is_regular_file(info: zipfile.ZipInfo) -> bool:
    mode = member_mode(info)
    return stat.S_ISREG(mode)


def validate_infos(infos: list[zipfile.ZipInfo]) -> None:
    if not infos:
        raise ValidationError("Application ZIP is empty")
    if len(infos) > MAX_MEMBER_COUNT:
        raise ValidationError("Application ZIP contains too many entries")

    names: set[str] = set()
    files: set[str] = set()
    total_uncompressed = 0
    total_compressed = 0

    for info in infos:
        raw_name = info.filename
        path = PurePosixPath(raw_name)
        if (
            not raw_name
            or path.is_absolute()
            or "\\" in raw_name
            or any(part in {"", ".", ".."} for part in path.parts)
            or not path.parts
            or path.parts[0] != "MacVitals.app"
        ):
            raise ValidationError(f"Unsafe application ZIP member: {raw_name!r}")
        if raw_name in names:
            raise ValidationError(f"Duplicate application ZIP member: {raw_name}")
        names.add(raw_name)

        if info.flag_bits & 0x1:
            raise ValidationError(f"Encrypted application ZIP member is forbidden: {raw_name}")
        if info.compress_type not in ALLOWED_COMPRESSION:
            raise ValidationError(f"Unsupported ZIP compression method for {raw_name}")
        if info.file_size < 0 or info.compress_size < 0:
            raise ValidationError(f"Invalid ZIP member size: {raw_name}")
        if info.file_size > MAX_MEMBER_UNCOMPRESSED_BYTES:
            raise ValidationError(f"ZIP member exceeds size limit: {raw_name}")

        total_uncompressed += info.file_size
        total_compressed += info.compress_size
        if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES:
            raise ValidationError("Application ZIP exceeds total uncompressed size limit")
        if total_compressed > MAX_TOTAL_COMPRESSED_BYTES:
            raise ValidationError("Application ZIP exceeds total compressed size limit")

        if info.file_size >= RATIO_CHECK_MINIMUM_BYTES:
            if info.compress_size == 0:
                raise ValidationError(f"Unsafe compression ratio for {raw_name}")
            if info.file_size / info.compress_size > MAX_COMPRESSION_RATIO:
                raise ValidationError(f"Unsafe compression ratio for {raw_name}")

        if is_directory(info):
            if info.file_size != 0:
                raise ValidationError(f"Directory entry must be empty: {raw_name}")
            continue
        if not is_regular_file(info):
            raise ValidationError(f"Special or symlink ZIP entry is forbidden: {raw_name}")
        files.add(raw_name)

    missing = sorted(REQUIRED_FILES - files)
    if missing:
        raise ValidationError(f"Application ZIP is missing required files: {missing}")

    executable = next(info for info in infos if info.filename == "MacVitals.app/Contents/MacOS/MacVitals")
    if member_mode(executable) & 0o111 == 0:
        raise ValidationError("MacVitals executable is not marked executable in the ZIP")


def validate_archive(path: Path) -> None:
    archive_path = path.expanduser().resolve()
    if not archive_path.is_file() or archive_path.is_symlink():
        raise ValidationError("Application ZIP must be a regular non-symlink file")
    if archive_path.stat().st_size <= 0:
        raise ValidationError("Application ZIP is empty")
    if archive_path.stat().st_size > MAX_ARCHIVE_BYTES:
        raise ValidationError("Application ZIP exceeds outer size limit")
    try:
        with zipfile.ZipFile(archive_path) as archive:
            validate_infos(archive.infolist())
            bad_member = archive.testzip()
            if bad_member is not None:
                raise ValidationError(f"Application ZIP CRC check failed: {bad_member}")
    except zipfile.BadZipFile as error:
        raise ValidationError("Application ZIP is malformed") from error


def zip_info(name: str, mode: int, data: bytes = b"") -> tuple[zipfile.ZipInfo, bytes]:
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    info.external_attr = mode << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    return info, data


def write_fixture(path: Path, *, mutation: str | None = None) -> None:
    entries = [
        zip_info("MacVitals.app/", stat.S_IFDIR | 0o755),
        zip_info("MacVitals.app/Contents/", stat.S_IFDIR | 0o755),
        zip_info("MacVitals.app/Contents/MacOS/", stat.S_IFDIR | 0o755),
        zip_info("MacVitals.app/Contents/MacOS/MacVitals", stat.S_IFREG | 0o755, b"binary"),
        zip_info("MacVitals.app/Contents/Info.plist", stat.S_IFREG | 0o644, b"plist"),
        zip_info("MacVitals.app/Contents/Resources/AppIcon.icns", stat.S_IFREG | 0o644, b"icon"),
        zip_info("MacVitals.app/Contents/Resources/en.lproj/Localizable.strings", stat.S_IFREG | 0o644, b"en"),
        zip_info("MacVitals.app/Contents/Resources/ru.lproj/Localizable.strings", stat.S_IFREG | 0o644, b"ru"),
    ]
    if mutation == "traversal":
        entries.append(zip_info("MacVitals.app/../escape", stat.S_IFREG | 0o644, b"x"))
    elif mutation == "foreign-root":
        entries.append(zip_info("Other.app/file", stat.S_IFREG | 0o644, b"x"))
    elif mutation == "symlink":
        entries.append(zip_info("MacVitals.app/link", stat.S_IFLNK | 0o777, b"/tmp"))
    elif mutation == "duplicate":
        entries.append(zip_info("MacVitals.app/Contents/Info.plist", stat.S_IFREG | 0o644, b"other"))
    elif mutation == "high-ratio":
        entries.append(zip_info("MacVitals.app/large", stat.S_IFREG | 0o644, b"0" * (2 * 1024 * 1024)))
    elif mutation == "missing-executable":
        entries = [entry for entry in entries if entry[0].filename != "MacVitals.app/Contents/MacOS/MacVitals"]

    with zipfile.ZipFile(path, "w") as archive:
        for info, data in entries:
            archive.writestr(info, data)


def expect_invalid(path: Path) -> None:
    try:
        validate_archive(path)
    except ValidationError:
        return
    raise AssertionError(f"Unsafe application ZIP was accepted: {path.name}")


def self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        valid = root / "valid.zip"
        write_fixture(valid)
        validate_archive(valid)
        for mutation in (
            "traversal",
            "foreign-root",
            "symlink",
            "duplicate",
            "high-ratio",
            "missing-executable",
        ):
            candidate = root / f"{mutation}.zip"
            write_fixture(candidate, mutation=mutation)
            expect_invalid(candidate)

        oversized = zipfile.ZipInfo("MacVitals.app/oversized")
        oversized.create_system = 3
        oversized.external_attr = (stat.S_IFREG | 0o644) << 16
        oversized.compress_type = zipfile.ZIP_STORED
        oversized.file_size = MAX_MEMBER_UNCOMPRESSED_BYTES + 1
        oversized.compress_size = oversized.file_size
        try:
            validate_infos([oversized])
        except ValidationError:
            pass
        else:
            raise AssertionError("Oversized ZIP member was accepted")
    print("Application ZIP validator self-test passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, nargs="?")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.archive is None:
        raise SystemExit("archive is required unless --self-test is used")
    try:
        validate_archive(args.archive)
    except ValidationError as error:
        print(f"Application ZIP validation failed: {error}", file=__import__("sys").stderr)
        return 1
    print("Application ZIP structure, resource limits and CRC are valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
