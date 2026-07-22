#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${VERSION:-dev}}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
ZIP_PATH="${DIST_DIR}/MacVitals-${VERSION}.zip"
DMG_PATH="${DIST_DIR}/MacVitals-${VERSION}.dmg"
STATUS_PATH="${DIST_DIR}/BUILD_STATUS.txt"
CHECKSUM_PATH="${DIST_DIR}/SHA256SUMS.txt"
WORK_DIR="$(mktemp -d)"
MOUNT_DIR="${WORK_DIR}/mounted"
ATTACHED=0

cleanup() {
  if [[ "${ATTACHED}" -eq 1 ]]; then
    hdiutil detach "${MOUNT_DIR}" -quiet || true
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

for path in "${ZIP_PATH}" "${DMG_PATH}" "${STATUS_PATH}" "${CHECKSUM_PATH}"; do
  [[ -s "${path}" ]] || {
    echo "Missing or empty release artifact: ${path}" >&2
    exit 1
  }
done

(
  cd "${DIST_DIR}"
  shasum -a 256 -c "$(basename "${CHECKSUM_PATH}")"
)

ditto -x -k "${ZIP_PATH}" "${WORK_DIR}/zip"
ZIP_APP="${WORK_DIR}/zip/MacVitals.app"
[[ -d "${ZIP_APP}" ]] || {
  echo "ZIP does not contain MacVitals.app at its root" >&2
  exit 1
}

INFO_PLIST="${ZIP_APP}/Contents/Info.plist"
EXECUTABLE="${ZIP_APP}/Contents/MacOS/MacVitals"
plutil -lint "${INFO_PLIST}" >/dev/null
[[ -x "${EXECUTABLE}" ]] || {
  echo "Packaged executable is missing or not executable" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "${INFO_PLIST}"
}

bundle_id="$(plist_value CFBundleIdentifier)"
package_type="$(plist_value CFBundlePackageType)"
short_version="$(plist_value CFBundleShortVersionString)"
build_version="$(plist_value CFBundleVersion)"
executable_name="$(plist_value CFBundleExecutable)"
ui_element="$(plist_value LSUIElement)"

[[ "${bundle_id}" == "com.mishkacher.MacVitals" ]] || {
  echo "Unexpected bundle identifier: ${bundle_id}" >&2
  exit 1
}
[[ "${package_type}" == "APPL" ]] || {
  echo "Unexpected bundle package type: ${package_type}" >&2
  exit 1
}
[[ "${short_version}" == "${VERSION}" ]] || {
  echo "Embedded version ${short_version} does not match package version ${VERSION}" >&2
  exit 1
}
[[ "${build_version}" =~ ^[0-9]+([.][0-9]+)*$ ]] || {
  echo "Invalid embedded build number: ${build_version}" >&2
  exit 1
}
[[ "${executable_name}" == "MacVitals" ]] || {
  echo "Unexpected executable name: ${executable_name}" >&2
  exit 1
}
[[ "${ui_element}" == "true" ]] || {
  echo "LSUIElement must remain enabled for a menu bar application" >&2
  exit 1
}

hdiutil verify "${DMG_PATH}" >/dev/null
mkdir -p "${MOUNT_DIR}"
hdiutil attach -readonly -nobrowse -mountpoint "${MOUNT_DIR}" "${DMG_PATH}" >/dev/null
ATTACHED=1
[[ -d "${MOUNT_DIR}/MacVitals.app" ]] || {
  echo "DMG does not contain MacVitals.app" >&2
  exit 1
}
[[ -L "${MOUNT_DIR}/Applications" ]] || {
  echo "DMG does not contain the Applications shortcut" >&2
  exit 1
}

grep -q '^Signing status:' "${STATUS_PATH}"
grep -q '^Notarization status:' "${STATUS_PATH}"

echo "Verified MacVitals ${VERSION} (${build_version}): bundle metadata, ZIP, DMG and checksums are valid"
