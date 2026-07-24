#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="${ROOT_DIR}/scripts/collect_runtime_metrics.py"

command -v python3 >/dev/null 2>&1 || {
  echo "Required command is unavailable: python3" >&2
  exit 127
}

[[ -f "${COLLECTOR}" ]] || {
  echo "Runtime metrics collector is missing: ${COLLECTOR}" >&2
  exit 1
}

exec python3 "${COLLECTOR}" "$@"
