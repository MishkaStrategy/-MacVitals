#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_XCODEGEN_VERSION='2.46.0'

extract_semantic_version() {
  local output=${1-}
  if [[ "${output}" =~ ([0-9]+[.][0-9]+[.][0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

self_test() {
  [[ "$(extract_semantic_version 'Version: 2.46.0')" == '2.46.0' ]]
  [[ "$(extract_semantic_version 'xcodegen 2.46.0')" == '2.46.0' ]]
  ! extract_semantic_version 'Version unavailable' >/dev/null
  [[ "${EXPECTED_XCODEGEN_VERSION}" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]
  printf 'XcodeGen installer self-test passed for %s.\n' "${EXPECTED_XCODEGEN_VERSION}"
}

if [[ "${1-}" == '--self-test' ]]; then
  [[ $# -eq 1 ]] || {
    printf 'The --self-test mode accepts no additional arguments.\n' >&2
    exit 2
  }
  self_test
  exit 0
fi

[[ $# -eq 0 ]] || {
  printf 'Usage: %s [--self-test]\n' "$0" >&2
  exit 2
}

command -v brew >/dev/null 2>&1 || {
  printf 'Homebrew is required to install XcodeGen.\n' >&2
  exit 1
}

export HOMEBREW_NO_ANALYTICS=1
brew install xcodegen

command -v xcodegen >/dev/null 2>&1 || {
  printf 'XcodeGen was not found after Homebrew installation.\n' >&2
  exit 1
}

version_output="$(xcodegen --version 2>&1)"
actual_version="$(extract_semantic_version "${version_output}")" || {
  printf 'Could not parse XcodeGen version output: %s\n' "${version_output}" >&2
  exit 1
}

[[ "${actual_version}" == "${EXPECTED_XCODEGEN_VERSION}" ]] || {
  printf 'Unexpected XcodeGen version: expected %s, got %s (%s)\n' \
    "${EXPECTED_XCODEGEN_VERSION}" "${actual_version}" "${version_output}" >&2
  exit 1
}

printf 'Verified XcodeGen %s.\n' "${actual_version}"
