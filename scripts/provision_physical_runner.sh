#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/provision_physical_runner.sh --check [--xcode-app /Applications/Xcode.app]
  bash scripts/provision_physical_runner.sh --apply [--xcode-app /Applications/Xcode.app]

Modes:
  --check  Inspect the physical Apple Silicon runner without changing it.
  --apply  Select an installed full Xcode, finish first-launch setup, install
           xcodegen through an existing Homebrew installation, and verify the
           complete MacVitals physical-validation toolchain.

This script never downloads Xcode, uses Apple/signing credentials, signs code,
notarizes artifacts, merges branches, creates tags, or publishes releases.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '==> %s\n' "$*"
}

mode=""
requested_xcode_app=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|--apply)
      [[ -z "${mode}" ]] || fail "Choose exactly one mode"
      mode="${1#--}"
      shift
      ;;
    --xcode-app)
      [[ $# -ge 2 ]] || fail "--xcode-app requires a path"
      requested_xcode_app="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${mode}" ]] || {
  usage >&2
  exit 2
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ "$(uname -m)" == "arm64" ]] || fail "Native Apple Silicon arm64 is required"

find_brew() {
  local candidate
  for candidate in "$(command -v brew 2>/dev/null || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

validate_xcode_app() {
  local app="$1"
  local developer_dir="${app}/Contents/Developer"
  [[ -d "${app}" && ! -L "${app}" ]] || return 1
  [[ -x "${developer_dir}/usr/bin/xcodebuild" ]] || return 1
  [[ -x "${developer_dir}/usr/bin/xcrun" ]] || return 1

  local xcode_output swift_output swift_major
  xcode_output="$(env DEVELOPER_DIR="${developer_dir}" xcodebuild -version 2>/dev/null || true)"
  [[ "${xcode_output}" == Xcode* ]] || return 1

  swift_output="$(env DEVELOPER_DIR="${developer_dir}" xcrun swift --version 2>/dev/null || true)"
  swift_major="$(printf '%s\n' "${swift_output}" | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -n 1)"
  [[ "${swift_major}" =~ ^[0-9]+$ && "${swift_major}" -ge 6 ]] || return 1

  env DEVELOPER_DIR="${developer_dir}" xcrun --find xctrace >/dev/null 2>&1 || return 1
  printf '%s\n' "${app}"
}

select_xcode_app() {
  local candidate

  if [[ -n "${requested_xcode_app}" ]]; then
    validate_xcode_app "${requested_xcode_app}" || fail "The requested Xcode is not a usable Swift 6 full Xcode: ${requested_xcode_app}"
    return 0
  fi

  for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    if validate_xcode_app "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  while IFS= read -r candidate; do
    if validate_xcode_app "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done < <(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print 2>/dev/null | LC_ALL=C sort)

  return 1
}

xcode_app="$(select_xcode_app || true)"
if [[ -z "${xcode_app}" ]]; then
  cat >&2 <<'EOF'
ERROR: No usable full Xcode with Swift 6 and xctrace was found in /Applications.

Install Xcode from the Mac App Store or Apple Developer downloads, move it to
/Applications, then rerun this script. Command Line Tools alone are insufficient
for xcodebuild and Instruments/xctrace physical validation.
EOF
  exit 3
fi

developer_dir="${xcode_app}/Contents/Developer"
brew_path="$(find_brew || true)"
xcodegen_path="$(command -v xcodegen 2>/dev/null || true)"
if [[ -z "${xcodegen_path}" ]]; then
  for candidate in /opt/homebrew/bin/xcodegen /usr/local/bin/xcodegen; do
    if [[ -x "${candidate}" ]]; then
      xcodegen_path="${candidate}"
      break
    fi
  done
fi

note "Runner: $(scutil --get ComputerName 2>/dev/null || hostname)"
note "Architecture: $(uname -m)"
note "Selected Xcode: ${xcode_app}"
env DEVELOPER_DIR="${developer_dir}" xcodebuild -version
env DEVELOPER_DIR="${developer_dir}" xcrun swift --version
env DEVELOPER_DIR="${developer_dir}" xcrun --find xctrace

if [[ "${mode}" == "apply" ]]; then
  if [[ -z "${xcodegen_path}" ]]; then
    [[ -n "${brew_path}" ]] || fail "Homebrew is required to install xcodegen; install Homebrew first and rerun"
    note "Installing xcodegen with ${brew_path}"
    "${brew_path}" install xcodegen
    xcodegen_path="$("${brew_path}" --prefix)/bin/xcodegen"
  fi

  [[ -x "${xcodegen_path}" ]] || fail "xcodegen installation did not produce an executable"

  note "Selecting full Xcode system-wide"
  sudo xcode-select --switch "${developer_dir}"

  note "Accepting the Xcode license for the selected installation"
  sudo env DEVELOPER_DIR="${developer_dir}" xcodebuild -license accept

  note "Installing required Xcode first-launch components"
  sudo env DEVELOPER_DIR="${developer_dir}" xcodebuild -runFirstLaunch
fi

active_developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "${mode}" == "apply" && "${active_developer_dir}" != "${developer_dir}" ]]; then
  fail "xcode-select did not retain the selected full Xcode developer directory"
fi

[[ -n "${xcodegen_path}" && -x "${xcodegen_path}" ]] || fail "xcodegen is unavailable"

note "Active developer directory: ${active_developer_dir:-unset}"
"${xcodegen_path}" --version
env DEVELOPER_DIR="${developer_dir}" xcodebuild -version
env DEVELOPER_DIR="${developer_dir}" xcrun swift --version
env DEVELOPER_DIR="${developer_dir}" xcrun --find xctrace >/dev/null

if [[ "$(env DEVELOPER_DIR="${developer_dir}" xcrun --sdk macosx --show-sdk-platform-path 2>/dev/null || true)" == "" ]]; then
  fail "The macOS SDK is unavailable in the selected Xcode"
fi

cat <<EOF

Physical runner toolchain is ready.
Xcode app: ${xcode_app}
Developer directory: ${developer_dir}
XcodeGen: ${xcodegen_path}

Next step:
  Synchronize feature/macvitals-v1 to run Physical Apple Silicon Validation.
EOF
