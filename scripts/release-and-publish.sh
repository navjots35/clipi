#!/usr/bin/env bash
#
# release-and-publish.sh — one-command release.
#
# Three phases, executed in order:
#   1. build + sign + notarize + DMG (scripts/release.sh)
#   2. publish to GitHub Releases (gh release create)
#   3. bump the Homebrew tap so existing tap users get it on next upgrade
#
# Each phase is *idempotent* — if the DMG already exists, phase 1 is skipped;
# if the GitHub release already exists, phase 2 is skipped. So if notarization
# completes but `gh release create` fails (e.g., flaky network), you can re-run
# this script and it'll pick up where it left off without rebuilding.
#
# Release-notes resolution, in order of preference:
#   1. First positional arg, e.g.:
#        ./scripts/release-and-publish.sh "Bug fix: panel position now works in VS Code."
#   2. release-notes/v$VERSION.md if you've staged a notes file
#   3. Last resort: synthesized from `git log` since the previous tag

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
TAG="v${VERSION}"
DMG="build/clipi-${VERSION}.dmg"

# ── Pre-flight checks (fail fast before any expensive work) ──────────────────
gh auth status >/dev/null 2>&1 || {
    echo "✗ gh CLI not authenticated. Run: gh auth login" >&2
    exit 1
}

# Soft warning if there are uncommitted changes — the release will use whatever
# is in the working tree, but uncommitted work makes "what got released" hard
# to reproduce later.
if [ -n "$(git status --porcelain)" ]; then
    echo "⚠ Working tree has uncommitted changes. The release will include them."
    echo "  Press ⌃C now to abort, or wait 3s to continue…"
    sleep 3
fi

# Soft warning if not on main — most releases should come from main, not dev branches.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "${CURRENT_BRANCH}" != "main" ]; then
    echo "⚠ You're on '${CURRENT_BRANCH}', not main. Releases usually cut from main."
    echo "  Press ⌃C to abort, or wait 3s to continue…"
    sleep 3
fi

# ── Resolve release notes ────────────────────────────────────────────────────
PREPARED_NOTES="release-notes/${TAG}.md"
NOTES_FILE=""
NOTES_TMP=""

if [ $# -gt 0 ] && [ -n "$1" ]; then
    NOTES_TMP=$(mktemp)
    printf "%s\n" "$1" > "${NOTES_TMP}"
    NOTES_FILE="${NOTES_TMP}"
elif [ -f "${PREPARED_NOTES}" ]; then
    NOTES_FILE="${PREPARED_NOTES}"
    echo "ℹ Using ${PREPARED_NOTES} for release notes."
else
    NOTES_TMP=$(mktemp)
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
    {
        echo "Changes${LAST_TAG:+ since ${LAST_TAG}}:"
        echo ""
        if [ -n "${LAST_TAG}" ]; then
            git log --pretty="- %s" "${LAST_TAG}..HEAD" -- . ':!build/'
        else
            git log --pretty="- %s" HEAD -- . ':!build/' | head -30
        fi
    } > "${NOTES_TMP}"
    NOTES_FILE="${NOTES_TMP}"
    echo "ℹ Synthesized release notes from git log. Override by passing as arg or"
    echo "  by creating ${PREPARED_NOTES} before re-running."
fi

# Clean up temp notes on exit so they don't accumulate in $TMPDIR.
trap '[ -n "${NOTES_TMP}" ] && rm -f "${NOTES_TMP}"' EXIT

# ── Phase 1: build + sign + notarize ─────────────────────────────────────────
if [ -f "${DMG}" ]; then
    echo "ℹ Phase 1/3 skipped — ${DMG} already exists."
    echo "  (Run \`rm ${DMG}\` first if you want to force a rebuild.)"
else
    echo "▸ Phase 1/3: build + sign + notarize (5-30 minutes, mostly Apple's queue)…"
    ./scripts/release.sh
fi

# ── Phase 2: publish to GitHub Releases ──────────────────────────────────────
if gh release view "${TAG}" >/dev/null 2>&1; then
    echo "ℹ Phase 2/3 skipped — release ${TAG} already exists on GitHub."
    echo "  (Run \`gh release delete ${TAG}\` first if you want to recreate it.)"
else
    echo "▸ Phase 2/3: publishing GitHub release ${TAG}…"
    gh release create "${TAG}" "${DMG}" \
        --title "clipi ${VERSION}" \
        --notes-file "${NOTES_FILE}"
fi

# ── Phase 3: bump the Homebrew tap ───────────────────────────────────────────
echo "▸ Phase 3/3: updating navjots35/homebrew-tap…"
./scripts/bump-tap.sh

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "✓ clipi ${VERSION} (build ${BUILD}) shipped."
echo "  Release: https://github.com/navjots35/clipi/releases/tag/${TAG}"
echo "  DMG:     ${DMG}"
echo "  Update:  brew update && brew upgrade --cask clipi"
