#!/usr/bin/env bash
# Build an unsigned GridBack.app zip for a GitHub Release.
# Run this on an Apple Silicon Mac with Xcode and the macOS 26 SDK.
# It cannot be run on Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ROOT}/build"
DERIVED="${BUILD}/DerivedData"
VERSION="0.1.0"
APP_NAME="GridBack"
ZIP="${BUILD}/${APP_NAME}-${VERSION}-unsigned-arm64.zip"

rm -rf "${BUILD}"
mkdir -p "${BUILD}"

echo "Building ${APP_NAME} (Release, arm64, signing off)…"
xcodebuild \
  -project "${ROOT}/GridBack.xcodeproj" \
  -scheme GridBack \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${DERIVED}" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_SRC="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${APP_SRC}" ]]; then
  echo "Build finished but ${APP_SRC} was not found." >&2
  exit 1
fi

STAGE="${BUILD}/stage"
mkdir -p "${STAGE}"
cp -R "${APP_SRC}" "${STAGE}/${APP_NAME}.app"

if command -v codesign >/dev/null 2>&1; then
  codesign --remove-signature "${STAGE}/${APP_NAME}.app" || true
fi

rm -f "${ZIP}" "${ZIP}.sha256"
ditto -c -k --keepParent "${STAGE}/${APP_NAME}.app" "${ZIP}"
shasum -a 256 "${ZIP}" | tee "${ZIP}.sha256"

cat <<EOF

Created:
  ${ZIP}

This zip is unsigned. On another Mac, the person opening it will see a
Gatekeeper warning. They can allow it from System Settings → Privacy & Security
→ Open Anyway, or by Control-clicking the app and choosing Open.

Attach the zip and the .sha256 file to the GitHub Release. Note that the app
is unsigned, early, and built for Apple Silicon on macOS 26 or later.
EOF
