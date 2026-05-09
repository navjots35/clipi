#!/usr/bin/env bash
#
# release.sh — produce a signed, notarized, stapled DMG ready to upload to
# GitHub Releases. Wraps build.sh with Developer ID signing and Apple's
# notarytool / stapler / hdiutil so a release candidate is one command:
#
#   ./scripts/release.sh
#
# Prerequisites (one-time):
#   1. Apple Developer Program membership.
#   2. "Developer ID Application" certificate installed in your login keychain.
#   3. notarytool keychain profile created once with:
#        xcrun notarytool store-credentials "clipi-notary" \
#            --apple-id "<your-apple-id>" \
#            --team-id "QCM34Y32SH" \
#            --password "<app-specific-password from appleid.apple.com>"
#      The profile name "clipi-notary" is what NOTARY_PROFILE expects below.
#
# Override any of these via env vars at invocation time, e.g.:
#   NOTARY_PROFILE=mine VERSION=0.2.0 ./scripts/release.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# ── Configuration ────────────────────────────────────────────────────────────
APP_NAME="clipi"
BUNDLE_ID="co.thebh.clipi"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Navjot Singh (QCM34Y32SH)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-clipi-notary}"

# Pull version from Info.plist so build artefacts always agree with what's shipped.
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_DIR="${BUILD_DIR}/dmg-staging"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

# ── Sanity checks ────────────────────────────────────────────────────────────
echo "▸ Checking signing identity…"
if ! security find-identity -v -p codesigning | grep -q "${SIGN_IDENTITY}"; then
    echo "✗ No matching code-signing identity in keychain:"
    echo "   ${SIGN_IDENTITY}"
    echo "  Run:  security find-identity -v -p codesigning"
    exit 1
fi

echo "▸ Checking notary profile '${NOTARY_PROFILE}'…"
if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "✗ notarytool profile '${NOTARY_PROFILE}' not found or invalid."
    echo "  Run once:"
    echo "    xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\"
    echo "        --apple-id \"<your-apple-id>\" \\"
    echo "        --team-id \"QCM34Y32SH\" \\"
    echo "        --password \"<app-specific-password>\""
    exit 1
fi

# ── Build (release optimization, signed with hardened runtime) ───────────────
echo "▸ Building release v${VERSION}…"
OPT_FLAG="-O" SIGN_IDENTITY="${SIGN_IDENTITY}" ./scripts/build.sh

# ── Verify the signature is releaseable ──────────────────────────────────────
echo "▸ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
codesign --display --verbose=2 "${APP_BUNDLE}" 2>&1 | grep -E "Authority|TeamIdentifier|Signature|Runtime"

# ── Notarize ─────────────────────────────────────────────────────────────────
# notarytool wants a flat archive (.zip) for upload. We toss the zip after
# notarization succeeds; the actual artifact is the DMG built below.
ZIP_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
echo "▸ Zipping for notarytool upload…"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "▸ Submitting to Apple notarization (this usually takes 1-3 minutes)…"
xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo "▸ Stapling notarization ticket…"
xcrun stapler staple "${APP_BUNDLE}"
xcrun stapler validate "${APP_BUNDLE}"
rm -f "${ZIP_PATH}"

# ── Build DMG ────────────────────────────────────────────────────────────────
echo "▸ Building DMG…"
rm -rf "${DMG_DIR}" "${DMG_PATH}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_BUNDLE}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}" >/dev/null

# Sign the DMG itself so Gatekeeper trusts the container, not just the app inside.
codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${DMG_PATH}"

# Notarize + staple the DMG too. Belt-and-braces: the .app inside is already
# stapled, but stapling the DMG means an offline first-launch from the mounted
# volume Just Works without the Gatekeeper prompt that hits unstapled DMGs.
echo "▸ Notarizing DMG…"
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo "▸ Stapling DMG…"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

rm -rf "${DMG_DIR}"

# ── Done ─────────────────────────────────────────────────────────────────────
DMG_BYTES=$(stat -f%z "${DMG_PATH}")
DMG_SIZE_MB=$(awk "BEGIN { printf \"%.1f\", ${DMG_BYTES} / 1048576 }")
echo ""
echo "✓ Release ready:"
echo "    ${DMG_PATH}  (${DMG_SIZE_MB} MB)"
echo ""
echo "  Verify on a clean machine:"
echo "    spctl --assess --type open --context context:primary-signature ${DMG_PATH}"
echo ""
echo "  Upload to GitHub:"
echo "    gh release create v${VERSION} ${DMG_PATH} --title 'clipi ${VERSION}' --notes 'See CHANGELOG'"
