#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${VERSION:-dev}}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
ARCHIVE_PATH="${BUILD_DIR}/MacVitals.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/MacVitals.app"
DMG_ROOT="${BUILD_DIR}/dmg-root"
ZIP_PATH="${DIST_DIR}/MacVitals-${VERSION}.zip"
DMG_PATH="${DIST_DIR}/MacVitals-${VERSION}.dmg"

if [[ ! "${VERSION}" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "Invalid release version: ${VERSION}" >&2
  exit 2
fi
if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
  echo "Invalid build number: ${BUILD_NUMBER}" >&2
  exit 2
fi

for command in xcodegen xcodebuild ditto hdiutil plutil shasum; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command is unavailable: ${command}" >&2
    exit 127
  }
done

rm -rf "${ARCHIVE_PATH}" "${DMG_ROOT}" "${DIST_DIR}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}" "${DMG_ROOT}"

cd "${ROOT_DIR}"
xcodegen generate
xcodebuild \
  -project MacVitals.xcodeproj \
  -scheme MacVitals \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  archive

[[ -d "${APP_PATH}" ]] || {
  echo "Archive did not contain MacVitals.app" >&2
  exit 1
}
[[ -x "${APP_PATH}/Contents/MacOS/MacVitals" ]] || {
  echo "MacVitals executable is missing or not executable" >&2
  exit 1
}
plutil -lint "${APP_PATH}/Contents/Info.plist" >/dev/null

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
ditto "${APP_PATH}" "${DMG_ROOT}/MacVitals.app"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create \
  -volname MacVitals \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

if codesign --verify --deep --strict "${APP_PATH}" >/dev/null 2>&1; then
  signing_status="signed"
else
  signing_status="unsigned"
fi

if xcrun stapler validate "${APP_PATH}" >/dev/null 2>&1; then
  notarization_status="notarization ticket present"
else
  notarization_status="not notarized"
fi

cat > "${DIST_DIR}/BUILD_STATUS.txt" <<EOF
MacVitals ${VERSION} (${BUILD_NUMBER})
Signing status: ${signing_status}
Notarization status: ${notarization_status}

Unless both statuses explicitly confirm signing and notarization, macOS Gatekeeper may require explicit user approval or a local source build.
EOF

(
  cd "${DIST_DIR}"
  shasum -a 256 "$(basename "${ZIP_PATH}")" "$(basename "${DMG_PATH}")" > SHA256SUMS.txt
)

bash "${ROOT_DIR}/scripts/verify_release.sh" "${VERSION}"
echo "Release artifacts are available in ${DIST_DIR}"
