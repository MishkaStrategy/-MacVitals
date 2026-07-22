#!/usr/bin/env python3
"""Materialize and validate the deterministic MacVitals application icon."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_GLOB = "AppIcon.icns.base64.part*"
SOURCE_DIRECTORY = ROOT / "AssetsSource"
OUTPUT = ROOT / "MacVitals" / "Resources" / "AppIcon.icns"

EXPECTED_PNG_DIMENSIONS: dict[bytes, tuple[int, int]] = {
    b"icp4": (16, 16),
    b"icp5": (32, 32),
    b"icp6": (64, 64),
    b"ic07": (128, 128),
    b"ic08": (256, 256),
    b"ic09": (512, 512),
    b"ic10": (1024, 1024),
}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
EXPECTED_SOURCE_SHA256 = "ec94e8a136730d1bd133f6bd5d7418b050b3bdad3d06ff759b03e4c0fb39398e"


class IconValidationError(ValueError):
    """Raised when the source icon is malformed or incomplete."""


def source_parts(directory: Path = SOURCE_DIRECTORY) -> list[Path]:
    parts = sorted(directory.glob(SOURCE_GLOB))
    if not parts:
        raise IconValidationError(f"No icon source parts found in {directory}")
    expected_names = [f"AppIcon.icns.base64.part{index:02d}" for index in range(len(parts))]
    actual_names = [part.name for part in parts]
    if actual_names != expected_names:
        raise IconValidationError(
            f"Icon source parts must be contiguous: expected {expected_names}, found {actual_names}"
        )
    return parts


def decode_source(directory: Path = SOURCE_DIRECTORY) -> bytes:
    parts = source_parts(directory)
    try:
        encoded = b"".join(part.read_bytes() for part in parts)
    except OSError as error:
        raise IconValidationError(f"Cannot read icon source parts: {error}") from error
    try:
        compact = b"".join(encoded.split())
        decoded = base64.b64decode(compact, validate=True)
    except binascii.Error as error:
        raise IconValidationError(f"Icon source is not valid base64: {error}") from error
    if not decoded:
        raise IconValidationError("Decoded icon is empty")
    return decoded


def png_dimensions(payload: bytes, chunk_type: bytes) -> tuple[int, int]:
    if len(payload) < 33 or not payload.startswith(PNG_SIGNATURE):
        raise IconValidationError(f"{chunk_type.decode()} does not contain a PNG payload")

    offset = len(PNG_SIGNATURE)
    dimensions: tuple[int, int] | None = None
    saw_iend = False
    while offset < len(payload):
        if offset + 12 > len(payload):
            raise IconValidationError(f"{chunk_type.decode()} has a truncated PNG chunk")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        name = payload[offset + 4 : offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        crc_end = data_end + 4
        if crc_end > len(payload):
            raise IconValidationError(f"{chunk_type.decode()} has an invalid PNG chunk length")
        stored_crc = struct.unpack(">I", payload[data_end:crc_end])[0]
        actual_crc = zlib.crc32(name)
        actual_crc = zlib.crc32(payload[data_start:data_end], actual_crc) & 0xFFFFFFFF
        if stored_crc != actual_crc:
            raise IconValidationError(
                f"{chunk_type.decode()} has a CRC mismatch in {name.decode(errors='replace')}"
            )

        if offset == len(PNG_SIGNATURE):
            if name != b"IHDR" or length != 13:
                raise IconValidationError(f"{chunk_type.decode()} has an invalid PNG IHDR")
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", payload[data_start:data_end]
            )
            if bit_depth != 8 or color_type not in (2, 6):
                raise IconValidationError(
                    f"{chunk_type.decode()} must be an 8-bit RGB/RGBA PNG, "
                    f"found bit depth {bit_depth}, color type {color_type}"
                )
            if compression != 0 or filtering != 0 or interlace != 0:
                raise IconValidationError(
                    f"{chunk_type.decode()} uses unsupported PNG encoding flags"
                )
            dimensions = (width, height)

        if name == b"IEND":
            if length != 0 or crc_end != len(payload):
                raise IconValidationError(f"{chunk_type.decode()} has an invalid PNG terminator")
            saw_iend = True
            break
        offset = crc_end

    if dimensions is None or not saw_iend:
        raise IconValidationError(f"{chunk_type.decode()} has an incomplete PNG payload")
    return dimensions


def validate_icns(data: bytes) -> str:
    if len(data) < 8 or data[:4] != b"icns":
        raise IconValidationError("Icon does not start with an ICNS header")
    declared_length = struct.unpack(">I", data[4:8])[0]
    if declared_length != len(data):
        raise IconValidationError(
            f"ICNS length mismatch: header {declared_length}, actual {len(data)}"
        )

    offset = 8
    seen: set[bytes] = set()
    while offset < len(data):
        if offset + 8 > len(data):
            raise IconValidationError("Truncated ICNS chunk header")
        chunk_type = data[offset : offset + 4]
        chunk_length = struct.unpack(">I", data[offset + 4 : offset + 8])[0]
        if chunk_length < 8 or offset + chunk_length > len(data):
            raise IconValidationError(
                f"Invalid {chunk_type!r} chunk length {chunk_length} at offset {offset}"
            )
        if chunk_type in seen:
            raise IconValidationError(f"Duplicate ICNS chunk {chunk_type!r}")
        seen.add(chunk_type)
        payload = data[offset + 8 : offset + chunk_length]
        expected = EXPECTED_PNG_DIMENSIONS.get(chunk_type)
        if expected is not None:
            actual = png_dimensions(payload, chunk_type)
            if actual != expected:
                raise IconValidationError(
                    f"{chunk_type.decode()} must be {expected[0]}x{expected[1]}, "
                    f"found {actual[0]}x{actual[1]}"
                )
        offset += chunk_length

    missing = set(EXPECTED_PNG_DIMENSIONS) - seen
    unexpected = seen - set(EXPECTED_PNG_DIMENSIONS)
    if missing:
        names = ", ".join(sorted(item.decode() for item in missing))
        raise IconValidationError(f"ICNS is missing required chunks: {names}")
    if unexpected:
        names = ", ".join(sorted(item.decode(errors="replace") for item in unexpected))
        raise IconValidationError(f"ICNS contains unexpected chunks: {names}")

    return hashlib.sha256(data).hexdigest()


def validate_source() -> tuple[bytes, str]:
    data = decode_source()
    digest = validate_icns(data)
    if digest != EXPECTED_SOURCE_SHA256:
        raise IconValidationError(
            f"Icon source digest {digest} does not match reviewed digest "
            f"{EXPECTED_SOURCE_SHA256}"
        )
    return data, digest


def materialize() -> str:
    data, digest = validate_source()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUTPUT.with_suffix(".icns.tmp")
    temporary.write_bytes(data)
    temporary.replace(OUTPUT)
    if OUTPUT.read_bytes() != data:
        raise IconValidationError("Materialized icon differs from its validated source")
    return digest


def validate_packaged_file(path: Path) -> str:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise IconValidationError(f"Cannot read packaged icon {path}: {error}") from error
    digest = validate_icns(data)
    _, source_digest = validate_source()
    if digest != source_digest:
        raise IconValidationError(
            f"Packaged icon digest {digest} does not match source digest {source_digest}"
        )
    return digest


def expect_invalid(data: bytes, label: str) -> None:
    try:
        validate_icns(data)
    except IconValidationError:
        return
    raise IconValidationError(f"Self-test did not reject {label}")


def run_self_test() -> None:
    source, _ = validate_source()

    bad_header = bytearray(source)
    bad_header[:4] = b"bad!"
    expect_invalid(bytes(bad_header), "invalid header")

    bad_length = bytearray(source)
    bad_length[4:8] = struct.pack(">I", len(source) + 1)
    expect_invalid(bytes(bad_length), "invalid total length")

    first_chunk_length = struct.unpack(">I", source[12:16])[0]
    missing_first = b"icns" + struct.pack(">I", len(source) - first_chunk_length)
    missing_first += source[8 + first_chunk_length :]
    expect_invalid(missing_first, "missing required chunk")

    wrong_dimension = bytearray(source)
    first_png_width_offset = 8 + 8 + 16
    wrong_dimension[first_png_width_offset : first_png_width_offset + 4] = struct.pack(">I", 17)
    expect_invalid(bytes(wrong_dimension), "wrong PNG dimension")


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check-only",
        action="store_true",
        help="validate the encoded source without writing AppIcon.icns",
    )
    mode.add_argument(
        "--validate-file",
        type=Path,
        help="validate a materialized or packaged icon and compare it with the source",
    )
    mode.add_argument(
        "--self-test",
        action="store_true",
        help="exercise validator rejection paths without writing files",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(sys.argv[1:] if argv is None else argv)
    try:
        if arguments.self_test:
            run_self_test()
            print("App icon validator self-test passed")
            return 0
        if arguments.validate_file is not None:
            digest = validate_packaged_file(arguments.validate_file)
            print(f"Validated packaged MacVitals app icon (sha256 {digest})")
            return 0
        if arguments.check_only:
            _, digest = validate_source()
            print(f"Validated MacVitals app icon source (sha256 {digest})")
            return 0
        digest = materialize()
        print(f"Materialized MacVitals AppIcon.icns (sha256 {digest})")
        return 0
    except IconValidationError as error:
        print(f"App icon validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
