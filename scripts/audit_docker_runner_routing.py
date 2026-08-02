from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

WORKFLOW_ROOT = Path(".github/workflows")
WORKFLOW_PATTERNS = ("*.yml", "*.yaml")
EXPECTED_SELECTOR = "[self-hosted, macOS, ARM64]"

JOB_RE = re.compile(r"^  (?P<job>[A-Za-z0-9_.-]+):(?:\s*(?:#.*)?)$")
RUNS_ON_RE = re.compile(r"^    runs-on:\s*(?P<value>.*?)(?:\s+#.*)?$")


@dataclass(frozen=True)
class JobBlock:
    name: str
    lines: list[str]


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _workflow_files(root: Path) -> list[Path]:
    workflow_root = root / WORKFLOW_ROOT
    return sorted(
        path
        for pattern in WORKFLOW_PATTERNS
        for path in workflow_root.glob(pattern)
        if path.is_file()
    )


def _job_blocks(text: str) -> list[JobBlock]:
    lines = text.splitlines()
    jobs_index = next((index for index, line in enumerate(lines) if line == "jobs:"), None)
    if jobs_index is None:
        return []

    blocks: list[JobBlock] = []
    current_name: str | None = None
    current_lines: list[str] = []

    for line in lines[jobs_index + 1 :]:
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and _indent(line) == 0:
            break

        match = JOB_RE.match(line)
        if match:
            if current_name is not None:
                blocks.append(JobBlock(current_name, current_lines))
            current_name = match.group("job")
            current_lines = [line]
        elif current_name is not None:
            current_lines.append(line)

    if current_name is not None:
        blocks.append(JobBlock(current_name, current_lines))

    return blocks


def _selector(job: JobBlock) -> str | None:
    for line in job.lines:
        match = RUNS_ON_RE.match(line)
        if match:
            return match.group("value").strip()
    return None


def audit(root: Path) -> list[str]:
    errors: list[str] = []

    for path in _workflow_files(root):
        relative_path = path.relative_to(root)
        text = path.read_text(encoding="utf-8")

        for job in _job_blocks(text):
            selector = _selector(job)
            if selector is None:
                errors.append(
                    f"{relative_path}:{job.name}: missing runs-on; "
                    f"use runs-on: {EXPECTED_SELECTOR}"
                )
                continue

            if selector != EXPECTED_SELECTOR:
                errors.append(
                    f"{relative_path}:{job.name}: runs-on is {selector!r}; "
                    f"expected exactly {EXPECTED_SELECTOR!r}"
                )

    return errors


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    errors = audit(root)

    if errors:
        print("Mac ARM64 runner routing violations:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Every workflow job uses runs-on: {EXPECTED_SELECTOR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
