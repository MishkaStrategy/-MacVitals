#!/bin/bash
# Accept non-zero xctrace exits only when a real trace bundle exports a valid XML TOC.
set -Eeuo pipefail
IFS=$'\n\t'

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

argument_after() {
  local wanted="$1"
  shift
  local previous=""
  local value
  for value in "$@"; do
    if [[ "${previous}" == "${wanted}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
    previous="${value}"
  done
  return 1
}

valid_xml_file() {
  local path="$1"
  [[ -f "${path}" && ! -L "${path}" && -s "${path}" ]] || return 1
  python3 - "${path}" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ET.parse(Path(sys.argv[1]))
PY
}

trace_has_payload() {
  local path="$1"
  [[ -d "${path}" && ! -L "${path}" ]] || return 1
  find "${path}" -type f -print -quit | grep -q .
}

run_self_test() {
  local root
  root="$(mktemp -d)"
  trap 'rm -rf "${root}"' RETURN

  cat > "${root}/fake-xcrun" <<'FAKE'
#!/bin/bash
set -Eeuo pipefail
if [[ "${1:-}" == "xctrace" && "${2:-}" == "record" ]]; then
  output=""
  previous=""
  for value in "$@"; do
    if [[ "${previous}" == "--output" ]]; then output="${value}"; fi
    previous="${value}"
  done
  mkdir -p "${output}"
  printf 'trace-data\n' > "${output}/data"
  exit 54
fi
if [[ "${1:-}" == "xctrace" && "${2:-}" == "export" ]]; then
  output=""
  previous=""
  for value in "$@"; do
    if [[ "${previous}" == "--output" ]]; then output="${value}"; fi
    previous="${value}"
  done
  [[ -n "${output}" && ! -e "${output}" ]] || exit 65
  printf '<trace-toc/>\n' > "${output}"
  exit 54
fi
exit 0
FAKE
  chmod 700 "${root}/fake-xcrun"

  MACVITALS_REAL_XCRUN="${root}/fake-xcrun" \
    bash "$0" xctrace record --output "${root}/sample.trace" >/dev/null 2>&1
  [[ -s "${root}/sample.trace/data" ]] || fail "xctrace shim self-test did not preserve trace output"

  MACVITALS_REAL_XCRUN="${root}/fake-xcrun" \
    bash "$0" xctrace export --input "${root}/sample.trace" --toc --output "${root}/toc.xml" >/dev/null 2>&1
  valid_xml_file "${root}/toc.xml" || fail "xctrace shim self-test did not preserve valid TOC output"

  printf 'Hardened xctrace exit validation self-test passed\n'
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

REAL_XCRUN="${MACVITALS_REAL_XCRUN:-/usr/bin/xcrun}"
[[ -x "${REAL_XCRUN}" ]] || fail "Real xcrun is unavailable: ${REAL_XCRUN}"

if [[ "${1:-}" == "xctrace" && "${2:-}" == "record" ]]; then
  output_path="$(argument_after --output "$@" || true)"
  set +e
  "${REAL_XCRUN}" "$@"
  status=$?
  set -e
  [[ ${status} -ne 0 ]] || exit 0

  if [[ -n "${output_path}" ]] && trace_has_payload "${output_path}"; then
    toc_root="$(mktemp -d)"
    toc_path="${toc_root}/toc.xml"
    set +e
    "${REAL_XCRUN}" xctrace export --input "${output_path}" --toc --output "${toc_path}" >/dev/null 2>&1
    export_status=$?
    set -e
    if valid_xml_file "${toc_path}"; then
      printf 'MacVitals hardening: xctrace record returned %s and TOC export returned %s, but the saved trace has a valid XML TOC; retaining it for human review.\n' \
        "${status}" "${export_status}" >&2
      rm -rf "${toc_root}"
      exit 0
    fi
    rm -rf "${toc_root}"
  fi
  exit "${status}"
fi

if [[ "${1:-}" == "xctrace" && "${2:-}" == "export" ]]; then
  output_path="$(argument_after --output "$@" || true)"
  set +e
  "${REAL_XCRUN}" "$@"
  status=$?
  set -e
  [[ ${status} -ne 0 ]] || exit 0
  if [[ -n "${output_path}" ]] && valid_xml_file "${output_path}"; then
    printf 'MacVitals hardening: xctrace export returned %s, but produced valid XML; retaining it for human review.\n' \
      "${status}" >&2
    exit 0
  fi
  exit "${status}"
fi

exec "${REAL_XCRUN}" "$@"
