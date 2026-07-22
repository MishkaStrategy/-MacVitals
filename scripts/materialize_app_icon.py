#!/usr/bin/env python3
"""Generate and validate the deterministic MacVitals application icon."""

from __future__ import annotations

import argparse
import hashlib
from functools import lru_cache
import math
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "MacVitals" / "Resources" / "AppIcon.icns"

ICON_REPRESENTATIONS: tuple[tuple[bytes, int], ...] = (
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),
)
EXPECTED_PNG_DIMENSIONS = {chunk: (size, size) for chunk, size in ICON_REPRESENTATIONS}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
EXPECTED_SOURCE_SHA256 = "c9e635f7881fd5c870b331fc628418895f01056ff5f8753132c67630947ed971"


class IconValidationError(ValueError):
    """Raised when generated or packaged icon data is invalid."""


def clamp(value: float, lower: float = 0.0, upper: float = 1.0) -> float:
    return max(lower, min(upper, value))


def smooth_coverage(distance: float, softness: float = 1.0) -> float:
    return clamp(0.5 - distance / max(softness, 0.001))


def rounded_rectangle_distance(
    x: float,
    y: float,
    left: float,
    top: float,
    right: float,
    bottom: float,
    radius: float,
) -> float:
    center_x = (left + right) / 2
    center_y = (top + bottom) / 2
    half_width = (right - left) / 2
    half_height = (bottom - top) / 2
    dx = abs(x - center_x) - (half_width - radius)
    dy = abs(y - center_y) - (half_height - radius)
    outside_x = max(dx, 0.0)
    outside_y = max(dy, 0.0)
    outside = math.hypot(outside_x, outside_y)
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def segment_distance(
    x: float,
    y: float,
    start: tuple[float, float],
    end: tuple[float, float],
) -> float:
    start_x, start_y = start
    end_x, end_y = end
    delta_x = end_x - start_x
    delta_y = end_y - start_y
    length_squared = delta_x * delta_x + delta_y * delta_y
    if length_squared == 0:
        return math.hypot(x - start_x, y - start_y)
    projection = ((x - start_x) * delta_x + (y - start_y) * delta_y) / length_squared
    projection = clamp(projection)
    closest_x = start_x + projection * delta_x
    closest_y = start_y + projection * delta_y
    return math.hypot(x - closest_x, y - closest_y)


def blend(
    destination: tuple[float, float, float, float],
    source_rgb: tuple[float, float, float],
    source_alpha: float,
) -> tuple[float, float, float, float]:
    source_alpha = clamp(source_alpha)
    destination_r, destination_g, destination_b, destination_alpha = destination
    output_alpha = source_alpha + destination_alpha * (1 - source_alpha)
    if output_alpha <= 0:
        return (0, 0, 0, 0)
    output_r = (
        source_rgb[0] * source_alpha
        + destination_r * destination_alpha * (1 - source_alpha)
    ) / output_alpha
    output_g = (
        source_rgb[1] * source_alpha
        + destination_g * destination_alpha * (1 - source_alpha)
    ) / output_alpha
    output_b = (
        source_rgb[2] * source_alpha
        + destination_b * destination_alpha * (1 - source_alpha)
    ) / output_alpha
    return output_r, output_g, output_b, output_alpha


def upscale_rgba_2x(source: bytes, source_size: int) -> bytes:
    row_length = source_size * 4
    output = bytearray(source_size * source_size * 16)
    destination = 0
    for row_index in range(source_size):
        row = source[row_index * row_length : (row_index + 1) * row_length]
        expanded = bytearray(row_length * 2)
        expanded_offset = 0
        for pixel_offset in range(0, row_length, 4):
            pixel = row[pixel_offset : pixel_offset + 4]
            expanded[expanded_offset : expanded_offset + 4] = pixel
            expanded[expanded_offset + 4 : expanded_offset + 8] = pixel
            expanded_offset += 8
        output[destination : destination + len(expanded)] = expanded
        destination += len(expanded)
        output[destination : destination + len(expanded)] = expanded
        destination += len(expanded)
    return bytes(output)


@lru_cache(maxsize=None)
def render_rgba(size: int) -> bytes:
    if size == 1024:
        return upscale_rgba_2x(render_rgba(512), 512)
    scale = float(size)
    outer = (0.07 * scale, 0.07 * scale, 0.93 * scale, 0.93 * scale)
    outer_radius = 0.19 * scale
    inner = (0.15 * scale, 0.15 * scale, 0.85 * scale, 0.85 * scale)
    inner_radius = 0.14 * scale
    border_width = max(1.0, 0.004 * scale)
    pulse_points = [
        (0.22 * scale, 0.54 * scale),
        (0.33 * scale, 0.54 * scale),
        (0.39 * scale, 0.38 * scale),
        (0.46 * scale, 0.70 * scale),
        (0.55 * scale, 0.30 * scale),
        (0.63 * scale, 0.54 * scale),
        (0.76 * scale, 0.54 * scale),
    ]
    glow_width = max(1.7, 0.022 * scale)
    pulse_width = max(1.0, 0.010 * scale)
    endpoint = (0.79 * scale, 0.54 * scale)
    endpoint_radius = max(2.2, 0.038 * scale)
    endpoint_inner_radius = max(1.0, 0.018 * scale)

    pixels = bytearray(size * size * 4)
    for pixel_y in range(size):
        y = pixel_y + 0.5
        normalized_y = y / scale
        for pixel_x in range(size):
            x = pixel_x + 0.5
            normalized_x = x / scale
            outer_distance = rounded_rectangle_distance(x, y, *outer, outer_radius)
            outer_alpha = smooth_coverage(outer_distance)
            if outer_alpha <= 0:
                continue

            vertical = clamp((normalized_y - 0.07) / 0.86)
            horizontal = clamp((normalized_x - 0.07) / 0.86)
            top_rgb = (43.0, 82.0, 100.0)
            bottom_rgb = (12.0, 54.0, 69.0)
            base_rgb = tuple(
                top_rgb[index] * (1 - vertical) + bottom_rgb[index] * vertical
                for index in range(3)
            )
            side_tint = 7.0 * horizontal
            color = (
                base_rgb[0],
                base_rgb[1] + side_tint * 0.5,
                base_rgb[2] + side_tint,
                outer_alpha,
            )

            ellipse_x = (normalized_x - 0.50) / 0.37
            ellipse_y = (normalized_y - 0.17) / 0.35
            ellipse_value = ellipse_x * ellipse_x + ellipse_y * ellipse_y
            if ellipse_value < 1 and normalized_y < 0.53:
                gloss_alpha = (1 - ellipse_value) * (1 - normalized_y / 0.58) * 0.15
                color = blend(color, (92.0, 132.0, 151.0), gloss_alpha * outer_alpha)

            inner_distance = abs(
                rounded_rectangle_distance(x, y, *inner, inner_radius)
            ) - border_width / 2
            border_alpha = smooth_coverage(inner_distance, max(0.8, border_width * 0.65))
            if border_alpha > 0:
                color = blend(color, (92.0, 139.0, 158.0), border_alpha * 0.32 * outer_alpha)

            minimum_pulse_distance = min(
                segment_distance(x, y, pulse_points[index], pulse_points[index + 1])
                for index in range(len(pulse_points) - 1)
            )
            glow_alpha = smooth_coverage(minimum_pulse_distance - glow_width, 1.2)
            if glow_alpha > 0:
                color = blend(color, (44.0, 245.0, 211.0), glow_alpha * 0.34 * outer_alpha)
            pulse_alpha = smooth_coverage(minimum_pulse_distance - pulse_width, 0.9)
            if pulse_alpha > 0:
                color = blend(color, (92.0, 255.0, 224.0), pulse_alpha * outer_alpha)
            core_alpha = smooth_coverage(minimum_pulse_distance - pulse_width * 0.35, 0.7)
            if core_alpha > 0:
                color = blend(color, (224.0, 255.0, 248.0), core_alpha * 0.86 * outer_alpha)

            endpoint_distance = math.hypot(x - endpoint[0], y - endpoint[1])
            endpoint_alpha = smooth_coverage(endpoint_distance - endpoint_radius, 1.0)
            if endpoint_alpha > 0:
                color = blend(color, (72.0, 250.0, 216.0), endpoint_alpha * outer_alpha)
            endpoint_inner_alpha = smooth_coverage(
                endpoint_distance - endpoint_inner_radius, 0.8
            )
            if endpoint_inner_alpha > 0:
                color = blend(
                    color,
                    (226.0, 255.0, 248.0),
                    endpoint_inner_alpha * outer_alpha,
                )

            offset = (pixel_y * size + pixel_x) * 4
            pixels[offset] = round(clamp(color[0], 0, 255))
            pixels[offset + 1] = round(clamp(color[1], 0, 255))
            pixels[offset + 2] = round(clamp(color[2], 0, 255))
            pixels[offset + 3] = round(clamp(color[3]) * 255)
    return bytes(pixels)


def png_chunk(name: bytes, payload: bytes) -> bytes:
    checksum = zlib.crc32(name)
    checksum = zlib.crc32(payload, checksum) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + name + payload + struct.pack(">I", checksum)


def encode_png(size: int, rgba: bytes) -> bytes:
    expected_length = size * size * 4
    if len(rgba) != expected_length:
        raise IconValidationError(
            f"RGBA length mismatch for {size}px: expected {expected_length}, found {len(rgba)}"
        )
    scanlines = bytearray()
    row_length = size * 4
    for row in range(size):
        scanlines.append(0)
        start = row * row_length
        scanlines.extend(rgba[start : start + row_length])
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        PNG_SIGNATURE
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(bytes(scanlines), level=9))
        + png_chunk(b"IEND", b"")
    )


def generate_icns() -> bytes:
    chunks = []
    for chunk_type, size in ICON_REPRESENTATIONS:
        png = encode_png(size, render_rgba(size))
        chunks.append(chunk_type + struct.pack(">I", len(png) + 8) + png)
    payload = b"".join(chunks)
    return b"icns" + struct.pack(">I", len(payload) + 8) + payload


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
            if bit_depth != 8 or color_type != 6:
                raise IconValidationError(
                    f"{chunk_type.decode()} must be an 8-bit RGBA PNG, "
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
        if expected is None:
            raise IconValidationError(f"ICNS contains unexpected chunk {chunk_type!r}")
        actual = png_dimensions(payload, chunk_type)
        if actual != expected:
            raise IconValidationError(
                f"{chunk_type.decode()} must be {expected[0]}x{expected[1]}, "
                f"found {actual[0]}x{actual[1]}"
            )
        offset += chunk_length

    missing = set(EXPECTED_PNG_DIMENSIONS) - seen
    if missing:
        names = ", ".join(sorted(item.decode() for item in missing))
        raise IconValidationError(f"ICNS is missing required chunks: {names}")
    return hashlib.sha256(data).hexdigest()


def validated_generated_icon() -> tuple[bytes, str]:
    data = generate_icns()
    digest = validate_icns(data)
    if EXPECTED_SOURCE_SHA256 != "TO_BE_REPLACED" and digest != EXPECTED_SOURCE_SHA256:
        raise IconValidationError(
            f"Generated icon digest {digest} does not match reviewed digest "
            f"{EXPECTED_SOURCE_SHA256}"
        )
    return data, digest


def materialize() -> str:
    data, digest = validated_generated_icon()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUTPUT.with_suffix(".icns.tmp")
    temporary.write_bytes(data)
    temporary.replace(OUTPUT)
    if OUTPUT.read_bytes() != data:
        raise IconValidationError("Materialized icon differs from generated data")
    return digest


def validate_packaged_file(path: Path) -> str:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise IconValidationError(f"Cannot read packaged icon {path}: {error}") from error
    digest = validate_icns(data)
    generated, generated_digest = validated_generated_icon()
    if digest != generated_digest or data != generated:
        raise IconValidationError(
            f"Packaged icon digest {digest} does not match generated digest {generated_digest}"
        )
    return digest


def expect_invalid(data: bytes, label: str) -> None:
    try:
        validate_icns(data)
    except IconValidationError:
        return
    raise IconValidationError(f"Self-test did not reject {label}")


def run_self_test() -> None:
    source, _ = validated_generated_icon()

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
        help="generate and validate the icon without writing AppIcon.icns",
    )
    mode.add_argument(
        "--validate-file",
        type=Path,
        help="validate a materialized or packaged icon against generated data",
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
            print("App icon generator self-test passed")
            return 0
        if arguments.validate_file is not None:
            digest = validate_packaged_file(arguments.validate_file)
            print(f"Validated packaged MacVitals app icon (sha256 {digest})")
            return 0
        if arguments.check_only:
            _, digest = validated_generated_icon()
            print(f"Validated generated MacVitals app icon (sha256 {digest})")
            return 0
        digest = materialize()
        print(f"Materialized MacVitals AppIcon.icns (sha256 {digest})")
        return 0
    except IconValidationError as error:
        print(f"App icon validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
