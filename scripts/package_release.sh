#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${VERSION:-0.0.0}}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"

if [[ ! "${VERSION}" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || (( ${#VERSION} > 64 )); then
  echo "Invalid release version: ${VERSION}. Use one to three numeric components (64 characters maximum)." >&2
  exit 2
fi
if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+([.][0-9]+)*$ ]] || (( ${#BUILD_NUMBER} > 64 )); then
  echo "Invalid build number: ${BUILD_NUMBER}" >&2
  exit 2
fi

for command in xcodegen xcodebuild ditto hdiutil plutil shasum codesign lipo xcrun python3 git; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command is unavailable: ${command}" >&2
    exit 127
  }
done

BUILD_DIR="$(python3 "${ROOT_DIR}/scripts/validate_output_path.py" --root "${ROOT_DIR}" --path "${BUILD_DIR}")"
DIST_DIR="$(python3 "${ROOT_DIR}/scripts/validate_output_path.py" --root "${ROOT_DIR}" --path "${DIST_DIR}")"
ARCHIVE_PATH="${BUILD_DIR}/MacVitals.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/MacVitals.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/MacVitals"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
DMG_ROOT="${BUILD_DIR}/dmg-root"
ZIP_NAME="MacVitals-${VERSION}.zip"
DMG_NAME="MacVitals-${VERSION}.dmg"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STATUS_PATH="${DIST_DIR}/BUILD_STATUS.txt"
MANIFEST_PATH="${DIST_DIR}/BUILD_MANIFEST.json"
CHECKSUM_PATH="${DIST_DIR}/SHA256SUMS.txt"
CODE_SIGNING_ALLOWED_VALUE="${CODE_SIGNING_ALLOWED:-NO}"

rm -rf -- "${ARCHIVE_PATH}" "${DMG_ROOT}"
mkdir -p -- "${BUILD_DIR}" "${DIST_DIR}" "${DMG_ROOT}"
DIST_DIR="${DIST_DIR}" python3 - <<'PY'
import os
import re
from pathlib import Path

directory = Path(os.environ["DIST_DIR"])
release_name = re.compile(r"MacVitals-[0-9]+(?:[.][0-9]+){0,2}[.](?:zip|dmg)\Z")
metadata_names = {"BUILD_STATUS.txt", "BUILD_MANIFEST.json", "SHA256SUMS.txt"}
entries = list(directory.iterdir())
unexpected = [
    entry.name
    for entry in entries
    if not (entry.is_file() and (entry.name in metadata_names or release_name.fullmatch(entry.name)))
]
if unexpected:
    raise SystemExit(
        "Refusing to clean DIST_DIR because it contains unexpected entries: "
        + ", ".join(sorted(unexpected))
    )
for entry in entries:
    entry.unlink()
PY

cd "${ROOT_DIR}"
python3 scripts/materialize_app_icon.py
xcodegen generate
xcodebuild \
  -project MacVitals.xcodeproj \
  -scheme MacVitals \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED_VALUE}" \
  archive

[[ -d "${APP_PATH}" ]] || {
  echo "Archive did not contain MacVitals.app" >&2
  exit 1
}
[[ -x "${EXECUTABLE_PATH}" ]] || {
  echo "MacVitals executable is missing or not executable" >&2
  exit 1
}
plutil -lint "${INFO_PLIST}" >/dev/null

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "${INFO_PLIST}"
}

bundle_id="$(plist_value CFBundleIdentifier)"
minimum_macos="$(plist_value LSMinimumSystemVersion)"
architectures="$(lipo -archs "${EXECUTABLE_PATH}")"
git_commit="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
xcode_version="$(xcodebuild -version | python3 -c 'import sys; print("; ".join(line.strip() for line in sys.stdin if line.strip()))')"

signature_info="$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1 || true)"
if codesign --verify --deep --strict "${APP_PATH}" >/dev/null 2>&1; then
  if grep -q '^Signature=adhoc$' <<<"${signature_info}"; then
    signing_status="ad-hoc-signed"
  elif grep -q '^Authority=Developer ID Application:' <<<"${signature_info}" \
    && grep -Eq '^TeamIdentifier=[A-Z0-9]+$' <<<"${signature_info}"; then
    signing_status="developer-id-signed"
  else
    signing_status="signed-unclassified"
  fi
elif [[ "${CODE_SIGNING_ALLOWED_VALUE}" == "NO" ]]; then
  signing_status="unsigned"
else
  signing_status="invalid-or-missing-signature"
fi

if xcrun stapler validate "${APP_PATH}" >/dev/null 2>&1; then
  notarization_status="ticket-present"
else
  notarization_status="not-notarized"
fi

if [[ "${signing_status}" == "invalid-or-missing-signature" ]]; then
  echo "Signing was requested, but the archived application failed strict verification." >&2
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
ditto "${APP_PATH}" "${DMG_ROOT}/MacVitals.app"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create \
  -volname MacVitals \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

cat > "${STATUS_PATH}" <<EOF
MacVitals ${VERSION} (${BUILD_NUMBER})
Git commit: ${git_commit}
Architectures: ${architectures}
Signing status: ${signing_status}
Notarization status: ${notarization_status}

Only a Developer ID signed app with a validated stapled notarization ticket and a successful Gatekeeper assessment may be described as ready for frictionless distribution.
EOF

VERSION="${VERSION}" \
BUILD_NUMBER="${BUILD_NUMBER}" \
BUNDLE_ID="${bundle_id}" \
MINIMUM_MACOS="${minimum_macos}" \
GIT_COMMIT="${git_commit}" \
XCODE_VERSION="${xcode_version}" \
ARCHITECTURES="${architectures}" \
SIGNING_STATUS="${signing_status}" \
NOTARIZATION_STATUS="${notarization_status}" \
ZIP_NAME="${ZIP_NAME}" \
DMG_NAME="${DMG_NAME}" \
MANIFEST_PATH="${MANIFEST_PATH}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

manifest = {
    "schemaVersion": 1,
    "product": "MacVitals",
    "version": os.environ["VERSION"],
    "buildNumber": os.environ["BUILD_NUMBER"],
    "bundleIdentifier": os.environ["BUNDLE_ID"],
    "minimumMacOS": os.environ["MINIMUM_MACOS"],
    "gitCommit": os.environ["GIT_COMMIT"],
    "xcodeVersion": os.environ["XCODE_VERSION"],
    "architectures": os.environ["ARCHITECTURES"].split(),
    "signingStatus": os.environ["SIGNING_STATUS"],
    "notarizationStatus": os.environ["NOTARIZATION_STATUS"],
    "artifacts": {
        "zip": os.environ["ZIP_NAME"],
        "dmg": os.environ["DMG_NAME"],
    },
}
Path(os.environ["MANIFEST_PATH"]).write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

(
  cd "${DIST_DIR}"
  shasum -a 256 \
    "${ZIP_NAME}" \
    "${DMG_NAME}" \
    "$(basename "${STATUS_PATH}")" \
    "$(basename "${MANIFEST_PATH}")" \
    > "$(basename "${CHECKSUM_PATH}")"
)

bash "${ROOT_DIR}/scripts/verify_release.sh" "${VERSION}"
echo "Release artifacts are available in ${DIST_DIR}"
