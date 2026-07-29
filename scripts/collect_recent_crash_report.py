#!/usr/bin/env python3
"""Collect and sanitize recent MacVitals crash reports from macOS."""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MAX_REPORT_BYTES = 4 * 1024 * 1024
PRIVATE_PATH_RE = re.compile(
    r"/(?:Users|home)/[^/\s]+|/(?:private/)?(?:tmp|var/tmp)/[^\s]+|/(?:private/)?var/folders/[^\s]+"
)


def sanitize(text: str, replacements: list[str]) -> str:
    result = text.replace("\x00", "<NUL>")
    for value in sorted({item for item in replacements if len(item) >= 3}, key=len, reverse=True):
        result = result.replace(value, "<REDACTED>")
    result = PRIVATE_PATH_RE.sub("<REDACTED_PATH>", result)
    encoded = result.encode("utf-8", errors="replace")
    if len(encoded) > MAX_REPORT_BYTES:
        encoded = encoded[:MAX_REPORT_BYTES]
        result = encoded.decode("utf-8", errors="ignore") + "\n<TRUNCATED>\n"
    return result


def strict_output(path: Path, repository: Path) -> Path:
    root = repository.resolve()
    output = (path if path.is_absolute() else root / path).resolve()
    if output == root or root not in output.parents:
        raise ValueError("output must be a strict repository child")
    if output.exists() and (not output.is_dir() or output.is_symlink()):
        raise ValueError("output must be a regular directory")
    output.mkdir(parents=True, exist_ok=True)
    return output


def candidate_reports(cutoff: float) -> list[Path]:
    roots = [
        Path.home() / "Library" / "Logs" / "DiagnosticReports",
        Path("/Library/Logs/DiagnosticReports"),
    ]
    reports: list[Path] = []
    for root in roots:
        if not root.is_dir() or root.is_symlink():
            continue
        for pattern in ("MacVitals*.ips", "MacVitals*.crash"):
            for path in root.glob(pattern):
                try:
                    if path.is_file() and not path.is_symlink() and path.stat().st_mtime >= cutoff:
                        reports.append(path)
                except OSError:
                    continue
    return sorted(reports, key=lambda item: item.stat().st_mtime, reverse=True)


def collect_unified_log(minutes: int, replacements: list[str]) -> tuple[int, str]:
    predicate = 'process == "MacVitals" OR eventMessage CONTAINS[c] "MacVitals"'
    result = subprocess.run(
        [
            "/usr/bin/log",
            "show",
            "--last",
            f"{minutes}m",
            "--style",
            "compact",
            "--info",
            "--debug",
            "--predicate",
            predicate,
        ],
        check=False,
        capture_output=True,
        text=True,
        env={**os.environ, "LC_ALL": "C", "LANG": "C"},
    )
    combined = result.stdout
    if result.stderr:
        combined += "\n<stderr>\n" + result.stderr
    return result.returncode, sanitize(combined, replacements)


def collect(args: argparse.Namespace) -> int:
    repository = args.repository.resolve()
    output = strict_output(args.output, repository)
    if args.since_marker is not None:
        cutoff = args.since_marker.resolve().stat().st_mtime
        minutes = max(1, int((time.time() - cutoff) / 60) + 2)
    else:
        minutes = args.since_minutes
        cutoff = time.time() - minutes * 60

    replacements = [
        str(Path.home()),
        str(repository),
        os.environ.get("GITHUB_WORKSPACE", ""),
        os.environ.get("RUNNER_NAME", ""),
        os.environ.get("USER", ""),
        socket.gethostname(),
    ]

    reports = candidate_reports(cutoff)
    index: dict[str, object] = {
        "schemaVersion": 1,
        "cutoffEpoch": cutoff,
        "reportCount": len(reports),
        "reports": [],
    }
    for index_number, source in enumerate(reports[:5], start=1):
        try:
            raw = source.read_bytes()[:MAX_REPORT_BYTES]
            text = raw.decode("utf-8", errors="replace")
        except OSError:
            continue
        if "MacVitals" not in text:
            continue
        target_name = f"report-{index_number}{source.suffix}.txt"
        (output / target_name).write_text(sanitize(text, replacements), encoding="utf-8")
        index["reports"].append(
            {
                "artifact": target_name,
                "modifiedEpoch": source.stat().st_mtime,
                "sourceFormat": source.suffix.lstrip("."),
            }
        )

    log_status, unified_log = collect_unified_log(minutes, replacements)
    (output / "unified-log.txt").write_text(
        unified_log if unified_log else "<no matching unified log entries>\n",
        encoding="utf-8",
    )
    index["unifiedLogStatus"] = log_status
    index["sanitizedReportCount"] = len(index["reports"])
    (output / "index.json").write_text(
        json.dumps(index, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    forbidden = [value for value in replacements if len(value) >= 3]
    violations: list[str] = []
    for path in output.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if PRIVATE_PATH_RE.search(text) or any(value in text for value in forbidden):
            violations.append(path.name)
    if violations:
        print("Crash evidence privacy scan failed: " + ", ".join(sorted(set(violations))), file=sys.stderr)
        return 3
    (output / "PRIVACY_SCAN_PASSED.txt").write_text(
        "Privacy scan passed for sanitized crash evidence.\n",
        encoding="utf-8",
    )
    count = int(index["sanitizedReportCount"])
    print(f"Collected {count} sanitized MacVitals crash report(s); unified log status={log_status}")
    return 0 if count > 0 else 2


def self_test() -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        output = strict_output(root / "repo" / "out", root / "repo")
        assert output == (root / "repo" / "out").resolve()
        redacted = sanitize(
            "user /Users/example/private /private/tmp/secret token-value",
            ["example", "token-value"],
        )
        assert "/Users/" not in redacted
        assert "/private/tmp/" not in redacted
        assert "token-value" not in redacted
    print("Recent crash report collector self-test passed")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, default=Path("recent-crash-evidence"))
    parser.add_argument("--since-minutes", type=int, default=180)
    parser.add_argument("--since-marker", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.since_minutes <= 0:
        parser.error("--since-minutes must be positive")
    return args


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    try:
        return collect(args)
    except (OSError, ValueError) as error:
        print(f"Crash report collection failed: {error}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
