#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f "CreditClock.xcodeproj/project.pbxproj" ]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "[release] CreditClock.xcodeproj not found. Running xcodegen generate..." >&2
    xcodegen generate
  else
    echo "[release] xcodegen is required to generate CreditClock.xcodeproj" >&2
    exit 1
  fi
fi

DERIVED_DATA_DIR="$ROOT_DIR/.build/release/DerivedData"
ARTIFACT_DIR="$ROOT_DIR/.build/release"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/CreditClock.app"
ASSET_PATH="$ARTIFACT_DIR/CreditClock-main-latest.zip"
BUILD_LOG="$ARTIFACT_DIR/build.log"

mkdir -p "$ARTIFACT_DIR"
rm -rf "$DERIVED_DATA_DIR" "$ASSET_PATH"

echo "[release] Building Release app..." >&2
set +e
xcodebuild \
  -project "CreditClock.xcodeproj" \
  -scheme "CreditClock" \
  -configuration "Release" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e

if [ $BUILD_STATUS -ne 0 ]; then
  echo "[release] Build failed. Log: $BUILD_LOG" >&2
  tail -n 80 "$BUILD_LOG" >&2 || true
  exit $BUILD_STATUS
fi

if [ ! -d "$APP_PATH" ]; then
  echo "[release] Built app not found: $APP_PATH" >&2
  exit 1
fi

echo "[release] Packaging artifact..." >&2
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ASSET_PATH"

echo "$ASSET_PATH"
