#!/usr/bin/env bash
# Build a Release zip of GridBack for a GitHub Release.
#
# Apple silicon will not launch an arm64 app that has no code signature
# (launchd reports POSIX error 163). The Xcode project ad-hoc signs with
# CODE_SIGN_IDENTITY = "-". This script signs again after the app is copied
# out of DerivedData, zips with ditto, then refuses to finish unless the
# unzipped app passes every gate:
#   codesign --verify --deep --strict
#   codesign -dv shows a signature
#   the app launches, the process is running, and it quits
#
# The signature is ad-hoc, not a Developer ID signature, and the app is not
# notarized. A downloaded copy still shows the Gatekeeper warning.
# The file name is historical.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ROOT}/build"
DERIVED="${BUILD}/DerivedData"
APP_NAME="GridBack"

rm -rf "${BUILD}"
mkdir -p "${BUILD}"

echo "Building ${APP_NAME} (Release, arm64)…"
xcodebuild \
  -project "${ROOT}/GridBack.xcodeproj" \
  -scheme GridBack \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${DERIVED}" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_SRC="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${APP_SRC}" ]]; then
  echo "Build finished but ${APP_SRC} was not found." >&2
  exit 1
fi

STAGE="${BUILD}/stage"
mkdir -p "${STAGE}"
cp -R "${APP_SRC}" "${STAGE}/${APP_NAME}.app"

# Copying the bundle can leave it unsigned or with a stale seal.
# Sign only after that copy, and before the zip is made.
echo "Ad-hoc signing ${APP_NAME}.app…"
codesign --force --deep -s - "${STAGE}/${APP_NAME}.app"

PLIST="${STAGE}/${APP_NAME}.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}")"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}")"
ZIP="${BUILD}/${APP_NAME}-v${VERSION}.zip"

rm -f "${ZIP}" "${ZIP}.sha256"
ditto -c -k --keepParent "${STAGE}/${APP_NAME}.app" "${ZIP}"
shasum -a 256 "${ZIP}" | tee "${ZIP}.sha256"

VERIFY="${BUILD}/verify-unzipped"
rm -rf "${VERIFY}"
mkdir -p "${VERIFY}"
ditto -x -k "${ZIP}" "${VERIFY}"
APP="${VERIFY}/${APP_NAME}.app"

echo "Checking the signature on the unzipped app…"
codesign --verify --deep --strict "${APP}"
details="$(codesign -dv --verbose=2 "${APP}" 2>&1)" || {
  printf '%s\n' "${details}" >&2
  echo "codesign -dv failed on the unzipped app." >&2
  exit 1
}
printf '%s\n' "${details}"
if ! printf '%s\n' "${details}" | grep -q 'Signature='; then
  echo "codesign -dv did not show a signature." >&2
  exit 1
fi

echo "Launching the unzipped app…"
before="$(pgrep -x "${APP_NAME}" || true)"
open -n "${APP}"

executable_for() {
  lsof -a -p "$1" -d txt -Fn 2>/dev/null | awk '/^n/ { sub(/^n/, ""); print; exit }'
}

new_pid=""
expected="${APP}/Contents/MacOS/${APP_NAME}"
for _ in $(seq 1 40); do
  current="$(pgrep -x "${APP_NAME}" || true)"
  for pid in ${current}; do
    skip=0
    for old in ${before}; do
      if [[ "${pid}" == "${old}" ]]; then
        skip=1
        break
      fi
    done
    if [[ "${skip}" -eq 1 ]]; then
      continue
    fi
    exe="$(executable_for "${pid}")"
    if [[ "${exe}" == "${expected}" ]]; then
      new_pid="${pid}"
      break
    fi
  done
  if [[ -n "${new_pid}" ]]; then
    break
  fi
  sleep 0.25
done

if [[ -z "${new_pid}" ]]; then
  echo "The unzipped app did not launch." >&2
  exit 1
fi

echo "Unzipped app is running as pid ${new_pid}. Quitting it."
kill "${new_pid}"
for _ in $(seq 1 40); do
  if ! kill -0 "${new_pid}" 2>/dev/null; then
    break
  fi
  sleep 0.25
done
if kill -0 "${new_pid}" 2>/dev/null; then
  echo "The unzipped app did not quit." >&2
  exit 1
fi

cat <<EOF

Created:
  ${ZIP}
  version ${VERSION} (${BUILD_NUM})

The app is ad-hoc signed, not notarized. On another Mac, the person opening
a downloaded copy will see a Gatekeeper warning. They can allow it from
System Settings → Privacy & Security → Open Anyway.

Attach ${APP_NAME}-v${VERSION}.zip to the GitHub Release. Do not publish a
zip that failed the signature or launch checks above.
EOF
