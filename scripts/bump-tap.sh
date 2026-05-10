#!/usr/bin/env bash
#
# bump-tap.sh — push a new clipi version into navjots35/homebrew-tap.
#
# Reads the version from Resources/Info.plist and the SHA256 from the freshly
# built DMG, then PUTs an updated Casks/clipi.rb into the tap repo via the
# GitHub API (no clone of the tap needed). After this runs, anyone with the
# tap installed gets the new version on their next `brew upgrade --cask`.
#
# Usage (after `./scripts/release.sh` produces a notarized DMG):
#   ./scripts/bump-tap.sh
#
# Override the tap target:
#   TAP_OWNER=otheruser TAP_REPO=homebrew-tap ./scripts/bump-tap.sh

set -euo pipefail
cd "$(dirname "$0")/.."

TAP_OWNER="${TAP_OWNER:-navjots35}"
TAP_REPO="${TAP_REPO:-homebrew-tap}"
CASK_PATH="Casks/clipi.rb"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DMG="build/clipi-${VERSION}.dmg"

if [ ! -f "${DMG}" ]; then
    echo "✗ ${DMG} not found. Run ./scripts/release.sh first." >&2
    exit 1
fi

SHA256=$(shasum -a 256 "${DMG}" | awk '{print $1}')
echo "▸ Updating ${TAP_OWNER}/${TAP_REPO}/${CASK_PATH}"
echo "    version: ${VERSION}"
echo "    sha256:  ${SHA256}"

# Render the cask in place — the only fields that change between releases
# are version + sha256, so the rest of the formula stays static.
CASK=$(cat <<EOF
cask "clipi" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/navjots35/clipi/releases/download/v#{version}/clipi-#{version}.dmg"
  name "clipi"
  desc "Keyboard-first clipboard manager"
  homepage "https://github.com/navjots35/clipi"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "clipi.app"

  zap trash: [
    "~/Library/Application Support/clipi",
    "~/Library/Preferences/co.thebh.clipi.plist",
  ]
end
EOF
)

CONTENT_B64=$(printf "%s\n" "${CASK}" | base64)
EXISTING_SHA=$(gh api "repos/${TAP_OWNER}/${TAP_REPO}/contents/${CASK_PATH}" --jq .sha 2>/dev/null || echo "")

if [ -n "${EXISTING_SHA}" ]; then
    gh api -X PUT "repos/${TAP_OWNER}/${TAP_REPO}/contents/${CASK_PATH}" \
        -f message="clipi ${VERSION}" \
        -f content="${CONTENT_B64}" \
        -f sha="${EXISTING_SHA}" \
        --jq '.commit.html_url' | sed 's|^|✓ Pushed: |'
else
    gh api -X PUT "repos/${TAP_OWNER}/${TAP_REPO}/contents/${CASK_PATH}" \
        -f message="clipi ${VERSION}" \
        -f content="${CONTENT_B64}" \
        --jq '.commit.html_url' | sed 's|^|✓ Created: |'
fi

echo ""
echo "✓ Tap updated. Users get it on their next:"
echo "    brew update && brew upgrade --cask clipi"
