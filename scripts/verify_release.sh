#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${VERSION:-dev}}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
ZIP_NAME="MacVitals-${VERSION}.zip"
DMG_NAME="MacVitals-${VERSION}.dmg"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STATUS_PATH="${DIST_DIR}/BUILD_STATUS.txt"
MANIFEST_PATH="${DIST_DIR}/BUILD_MANIFEST.json"
CHECKSUM_PATH="${DIST_DIR}/SHA256SUMS.txt"
WORK_DIR="$(mktemp -d)"
MOUNT_DIR="${WORK_DIR}/mounted"
ATTACHED=0
TARGET_ARCHITECTURE="arm64"

cleanup() {
  if [[ "${ATTACHED}" -eq 1 ]]; then
    hdiutil detach "${MOUNT_DIR}" -quiet || true
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

for command in ditto hdiutil plutil shasum lipo codesign xcrun python3 cmp; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required verification command is unavailable: ${command}" >&2
    exit 127
  }
done

for path in "${ZIP_PATH}" "${DMG_PATH}" "${STATUS_PATH}" "${MANIFEST_PATH}" "${CHECKSUM_PATH}"; do
  [[ -s "${path}" ]] || {
    echo "Missing or empty release artifact: ${path}" >&2
    exit 1
  }
done

(
  cd "${DIST_DIR}"
  shasum -a 256 -c "$(basename "${CHECKSUM_PATH}")"
)

DIST_DIR="${DIST_DIR}" \
ZIP_NAME="${ZIP_NAME}" \
DMG_NAME="${DMG_NAME}" \
python3 - <<'PY'
import os
from pathlib import Path

expected = {
    os.environ["ZIP_NAME"],
    os.environ["DMG_NAME"],
    "BUILD_STATUS.txt",
    "BUILD_MANIFEST.json",
}
lines = (Path(os.environ["DIST_DIR"]) / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines()
found: set[str] = set()
for line in lines:
    parts = line.split(maxsplit=1)
    if len(parts) != 2 or len(parts[0]) != 64:
        raise SystemExit(f"Malformed checksum entry: {line}")
    name = parts[1].lstrip("*")
    if "/" in name or "\\" in name:
        raise SystemExit(f"Checksum entry must use a basename: {name}")
    if name in found:
        raise SystemExit(f"Duplicate checksum entry: {name}")
    found.add(name)
if found != expected:
    raise SystemExit(
        f"Checksum scope mismatch. Expected {sorted(expected)}, found {sorted(found)}"
    )
PY

python3 "${ROOT_DIR}/scripts/validate_app_zip.py" "${ZIP_PATH}"
ditto -x -k "${ZIP_PATH}" "${WORK_DIR}/zip"
ZIP_APP="${WORK_DIR}/zip/MacVitals.app"
[[ -d "${ZIP_APP}" ]] || {
  echo "ZIP does not contain MacVitals.app at its root" >&2
  exit 1
}

INFO_PLIST="${ZIP_APP}/Contents/Info.plist"
EXECUTABLE="${ZIP_APP}/Contents/MacOS/MacVitals"
RESOURCES="${ZIP_APP}/Contents/Resources"
ICON_PATH="${RESOURCES}/AppIcon.icns"
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
minimum_macos="$(plist_value LSMinimumSystemVersion)"
executable_name="$(plist_value CFBundleExecutable)"
icon_file="$(plist_value CFBundleIconFile)"
ui_element="$(plist_value LSUIElement)"
localizations="$(plist_value CFBundleLocalizations)"

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
[[ "${minimum_macos}" =~ ^[0-9]+([.][0-9]+){1,2}$ ]] || {
  echo "Invalid minimum macOS version: ${minimum_macos}" >&2
  exit 1
}
[[ "${executable_name}" == "MacVitals" ]] || {
  echo "Unexpected executable name: ${executable_name}" >&2
  exit 1
}
[[ "${icon_file}" == "AppIcon.icns" ]] || {
  echo "Unexpected or missing application icon declaration: ${icon_file}" >&2
  exit 1
}
[[ -s "${ICON_PATH}" ]] || {
  echo "Packaged application icon is missing or empty" >&2
  exit 1
}
python3 "${ROOT_DIR}/scripts/materialize_app_icon.py" --validate-file "${ICON_PATH}"
if find "${RESOURCES}" -type f -name '*.base64' -print -quit | grep -q .; then
  echo "Encoded icon source must not be included in the application bundle" >&2
  exit 1
fi
[[ "${ui_element}" == "true" ]] || {
  echo "LSUIElement must remain enabled for a menu bar application" >&2
  exit 1
}

for locale in en ru; do
  grep -q "${locale}" <<<"${localizations}" || {
    echo "CFBundleLocalizations is missing ${locale}" >&2
    exit 1
  }
  strings_path="${RESOURCES}/${locale}.lproj/Localizable.strings"
  [[ -s "${strings_path}" ]] || {
    echo "ZIP is missing ${locale} localization resources" >&2
    exit 1
  }
  plutil -lint "${strings_path}" >/dev/null
done

architectures="$(lipo -archs "${EXECUTABLE}")"
if [[ "${architectures}" != "${TARGET_ARCHITECTURE}" ]]; then
  echo "Packaged executable must contain only ${TARGET_ARCHITECTURE}; found: ${architectures}" >&2
  exit 1
fi

signature_info="$(codesign -dv --verbose=4 "${ZIP_APP}" 2>&1 || true)"
if codesign --verify --deep --strict "${ZIP_APP}" >/dev/null 2>&1; then
  if grep -q '^Signature=adhoc$' <<<"${signature_info}"; then
    actual_signing_status="ad-hoc-signed"
  elif grep -q '^Authority=Developer ID Application:' <<<"${signature_info}" \
    && grep -Eq '^TeamIdentifier=[A-Z0-9]+$' <<<"${signature_info}"; then
    actual_signing_status="developer-id-signed"
  else
    actual_signing_status="signed-unclassified"
  fi
else
  actual_signing_status="unsigned"
fi

if xcrun stapler validate "${ZIP_APP}" >/dev/null 2>&1; then
  actual_notarization_status="ticket-present"
else
  actual_notarization_status="not-notarized"
fi

metadata_arguments=(
  --manifest "${MANIFEST_PATH}"
  --status "${STATUS_PATH}"
  --version "${VERSION}"
  --build-number "${build_version}"
  --bundle-identifier "${bundle_id}"
  --minimum-macos "${minimum_macos}"
  --architectures "${architectures}"
  --signing-status "${actual_signing_status}"
  --notarization-status "${actual_notarization_status}"
  --zip-name "${ZIP_NAME}"
  --dmg-name "${DMG_NAME}"
)
if [[ -n "${GITHUB_SHA:-}" ]]; then
  metadata_arguments+=(--expected-git-commit "${GITHUB_SHA}")
fi
python3 "${ROOT_DIR}/scripts/validate_release_metadata.py" "${metadata_arguments[@]}"

hdiutil verify "${DMG_PATH}" >/dev/null
mkdir -p "${MOUNT_DIR}"
hdiutil attach -readonly -nobrowse -mountpoint "${MOUNT_DIR}" "${DMG_PATH}" >/dev/null
ATTACHED=1
DMG_APP="${MOUNT_DIR}/MacVitals.app"
[[ -d "${DMG_APP}" ]] || {
  echo "DMG does not contain MacVitals.app" >&2
  exit 1
}
[[ -L "${MOUNT_DIR}/Applications" ]] || {
  echo "DMG does not contain the Applications shortcut" >&2
  exit 1
}

cmp -s "${EXECUTABLE}" "${DMG_APP}/Contents/MacOS/MacVitals" || {
  echo "ZIP and DMG executables differ" >&2
  exit 1
}
cmp -s "${INFO_PLIST}" "${DMG_APP}/Contents/Info.plist" || {
  echo "ZIP and DMG Info.plist files differ" >&2
  exit 1
}
cmp -s "${ICON_PATH}" "${DMG_APP}/Contents/Resources/AppIcon.icns" || {
  echo "ZIP and DMG application icons differ" >&2
  exit 1
}
for locale in en ru; do
  zip_strings="${RESOURCES}/${locale}.lproj/Localizable.strings"
  dmg_strings="${DMG_APP}/Contents/Resources/${locale}.lproj/Localizable.strings"
  [[ -s "${dmg_strings}" ]] || {
    echo "DMG is missing ${locale} localization resources" >&2
    exit 1
  }
  cmp -s "${zip_strings}" "${dmg_strings}" || {
    echo "ZIP and DMG ${locale} localization resources differ" >&2
    exit 1
  }
done

codesign --verify --deep --strict "${DMG_APP}" >/dev/null 2>&1 || {
  if [[ "${actual_signing_status}" != "unsigned" ]]; then
    echo "DMG application signature does not match declared signing state" >&2
    exit 1
  fi
}

echo "Verified MacVitals ${VERSION} (${build_version}): provenance, app icon, bundle metadata, EN/RU resources, arm64 executable, ZIP, DMG and checksums are valid"
