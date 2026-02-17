#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "[release] gh CLI is required." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "[release] gh auth is not configured. Run: gh auth login" >&2
  exit 1
fi

ASSET_PATH="$($ROOT_DIR/scripts/build-release-artifact.sh)"
TAG="main-latest"
TITLE="CreditClock main latest"
COMMIT_SHA="$(git rev-parse --short HEAD)"
COMMIT_SUBJECT="$(git log -1 --pretty=%s)"
NOTES=$(cat <<EOF
Automated main build upload.

Commit: $COMMIT_SHA
Subject: $COMMIT_SUBJECT
Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
)

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "[release] Updating existing release: $TAG"
  gh release upload "$TAG" "$ASSET_PATH" --clobber
  gh release edit "$TAG" --title "$TITLE" --notes "$NOTES"
else
  echo "[release] Creating release: $TAG"
  gh release create "$TAG" "$ASSET_PATH" --title "$TITLE" --notes "$NOTES"
fi

echo "[release] Upload completed: $ASSET_PATH"
