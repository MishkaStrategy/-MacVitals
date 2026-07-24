#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${ROOT_DIR}/scripts/collect_runtime_metrics.py"

command -v python3 >/dev/null 2>&1 || {
  echo "Required command is unavailable: python3" >&2
  exit 127
}

[[ -f "${COLLECTOR}" ]] || {
  echo "Runtime metrics collector is missing" >&2
  exit 1
}

redact_output() {
  while IFS= read -r line; do
    if [[ "${line}" == "Runtime summary generated at "* ]]; then
      printf '%s\n' "Runtime summary generated."
      continue
    fi
    if [[ -n "${HOME:-}" ]]; then
      line="${line//${HOME}/<HOME>}"
    fi
    printf '%s\n' "${line}"
  done
}

python3 "${COLLECTOR}" "$@" 2>&1 | redact_output
