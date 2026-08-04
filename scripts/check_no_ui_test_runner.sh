#!/usr/bin/env bash
set -Eeuo pipefail

runner_name='MacVitalsUITests-Runner'

if pgrep -x "${runner_name}" >/dev/null 2>&1; then
  echo "${runner_name} is running unexpectedly" >&2
  pkill -x "${runner_name}" 2>/dev/null || true
  exit 1
fi

exit 0
