#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="clipi"               # bundle name + executable filename (lowercase per brand)
MODULE_NAME="Clipi"            # Swift module identifier (UpperCamel per convention)
BUNDLE_ID="co.thebh.clipi"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
MIN_OS="13.0"

# Sources — flat list, ordered so file-private types are visible to consumers.
SOURCES=(
    Sources/Clipi/Models/AppSettings.swift
    Sources/Clipi/Models/ClipboardItem.swift
    Sources/Clipi/Models/HistoryPersistence.swift
    Sources/Clipi/Models/ClipboardStore.swift
    Sources/Clipi/Services/PasteboardWatcher.swift
    Sources/Clipi/Services/HotkeyManager.swift
    Sources/Clipi/Services/Paster.swift
    Sources/Clipi/Services/CaretLocator.swift
    Sources/Clipi/Services/SecureFieldDetector.swift
    Sources/Clipi/Services/StatusItemController.swift
    Sources/Clipi/UI/PanelController.swift
    Sources/Clipi/UI/ClipboardPanelView.swift
    Sources/Clipi/UI/ClipboardRowView.swift
    Sources/Clipi/UI/OnboardingWindow.swift
    Sources/Clipi/UI/SettingsWindow.swift
    Sources/Clipi/AppDelegate.swift
)

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"   # arm64 on Apple Silicon, x86_64 on Intel
TARGET="${ARCH}-apple-macos${MIN_OS}"

mkdir -p "${BUILD_DIR}"
BIN_OUT="${BUILD_DIR}/${APP_NAME}"

OPT_FLAG="${OPT_FLAG:--Onone}"   # default to fast build; pass OPT_FLAG=-O for release-grade optimization
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

echo "▸ Compiling for ${TARGET} (${OPT_FLAG}, ${JOBS} jobs)…"
xcrun swiftc \
    -target "${TARGET}" \
    -sdk "${SDK_PATH}" \
    ${OPT_FLAG} \
    -j "${JOBS}" \
    -parse-as-library \
    -module-name "${MODULE_NAME}" \
    -Xfrontend -warn-long-expression-type-checking=200 \
    -Xfrontend -warn-long-function-bodies=500 \
    -o "${BIN_OUT}" \
    "${SOURCES[@]}"

echo "▸ Assembling ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
mv "${BIN_OUT}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
# App icon. Auto-generate the .icns on first build (or when the source script
# is newer than the existing .icns) so a fresh checkout doesn't ship as a
# blank-icon bundle.
if [ ! -f Resources/clipi.icns ] || [ scripts/make-icon.swift -nt Resources/clipi.icns ]; then
    echo "▸ Regenerating app icon…"
    ./scripts/make-icon.sh >/dev/null
fi
cp Resources/clipi.icns "${APP_BUNDLE}/Contents/Resources/clipi.icns"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

# Sign. Default to ad-hoc for fast local iteration; pass SIGN_IDENTITY="Developer ID
# Application: …" (or set CLIPI_SIGN_IDENTITY in the environment) to produce a
# release-grade signed binary that's eligible for notarization.
SIGN_IDENTITY="${SIGN_IDENTITY:-${CLIPI_SIGN_IDENTITY:--}}"
ENTITLEMENTS="Resources/clipi.entitlements"

if [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "▸ Signing ad-hoc (dev build)…"
    codesign --force --deep --sign - \
        --identifier "${BUNDLE_ID}" \
        "${APP_BUNDLE}" >/dev/null
else
    echo "▸ Signing with hardened runtime: ${SIGN_IDENTITY}"
    codesign --force --deep --timestamp \
        --options runtime \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${SIGN_IDENTITY}" \
        --identifier "${BUNDLE_ID}" \
        "${APP_BUNDLE}"
fi

echo "✓ Built ${APP_BUNDLE}"
echo "  Run with:  open ${APP_BUNDLE}"
