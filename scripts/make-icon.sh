#!/usr/bin/env bash
# make-icon.sh — render the iconset PNGs and pack them into Resources/clipi.icns.
# Re-run any time make-icon.swift changes.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="Resources/clipi.iconset"
ICNS="Resources/clipi.icns"

rm -rf "${ICONSET}"
xcrun swift scripts/make-icon.swift "${ICONSET}"
iconutil -c icns "${ICONSET}" -o "${ICNS}"
rm -rf "${ICONSET}"
echo "✓ Wrote ${ICNS}"
