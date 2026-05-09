#!/usr/bin/env bash
#
# bump-version.sh — bump clipi's version numbers in Resources/Info.plist.
#
# Two values get bumped:
#   • CFBundleShortVersionString — user-visible "0.1.0" (semver). Bumped only
#                                  when an arg of major|minor|patch is given.
#   • CFBundleVersion           — monotonic build number. Bumped on every run.
#
# macOS requires CFBundleVersion to strictly increase between notarized uploads
# of the same CFBundleShortVersionString — otherwise notarytool rejects with
# "The bundle version must be higher than the previously uploaded version".
# Running this before every `release.sh` keeps you out of that ditch.
#
# Usage:
#   ./scripts/bump-version.sh              # bump build number only
#   ./scripts/bump-version.sh patch        # 0.1.0 → 0.1.1, build = build + 1
#   ./scripts/bump-version.sh minor        # 0.1.x → 0.2.0
#   ./scripts/bump-version.sh major        # 0.x.x → 1.0.0

set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="Resources/Info.plist"
BUMP_TYPE="${1:-build}"

short=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PLIST}")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${PLIST}")

case "${BUMP_TYPE}" in
    major|minor|patch)
        IFS='.' read -r major minor patch <<<"${short}"
        case "${BUMP_TYPE}" in
            major) major=$((major + 1)); minor=0; patch=0 ;;
            minor) minor=$((minor + 1)); patch=0 ;;
            patch) patch=$((patch + 1)) ;;
        esac
        new_short="${major}.${minor}.${patch}"
        ;;
    build)
        new_short="${short}"
        ;;
    *)
        echo "✗ unknown bump type: ${BUMP_TYPE}" >&2
        echo "  expected one of: major, minor, patch, build" >&2
        exit 1
        ;;
esac

new_build=$((build + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${new_short}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${new_build}" "${PLIST}"

echo "✓ ${short} (${build})  →  ${new_short} (${new_build})"
