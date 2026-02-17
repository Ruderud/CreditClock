#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SHARED_SWIFT_FILES=()
while IFS= read -r file; do
  SHARED_SWIFT_FILES+=("$file")
done < <(find Shared -type f -name '*.swift' | sort)

APP_SWIFT_FILES=()
while IFS= read -r file; do
  APP_SWIFT_FILES+=("$file")
done < <(find CreditClockApp -type f -name '*.swift' | sort)

WIDGET_SWIFT_FILES=()
while IFS= read -r file; do
  WIDGET_SWIFT_FILES+=("$file")
done < <(find CreditClockWidget -type f -name '*.swift' | sort)

if [ "${#SHARED_SWIFT_FILES[@]}" -eq 0 ]; then
  echo "No Swift files found under Shared/."
  exit 1
fi

if [ "${#APP_SWIFT_FILES[@]}" -eq 0 ]; then
  echo "No Swift files found under CreditClockApp/."
  exit 1
fi

if [ "${#WIDGET_SWIFT_FILES[@]}" -eq 0 ]; then
  echo "No Swift files found under CreditClockWidget/."
  exit 1
fi

echo "[check] Type-check shared files"
xcrun swiftc -typecheck "${SHARED_SWIFT_FILES[@]}"

echo "[check] Type-check macOS app target"
xcrun swiftc -typecheck "${APP_SWIFT_FILES[@]}" "${SHARED_SWIFT_FILES[@]}"

echo "[check] Type-check widget target"
xcrun swiftc -typecheck "${WIDGET_SWIFT_FILES[@]}" "${SHARED_SWIFT_FILES[@]}"

echo "[check] All pre-commit checks passed."
