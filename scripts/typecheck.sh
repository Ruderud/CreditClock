#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SHARED_SWIFT_FILES=()
while IFS= read -r file; do
  SHARED_SWIFT_FILES+=("$file")
done < <(find Shared -type f -name '*.swift' | sort)

if [ "${#SHARED_SWIFT_FILES[@]}" -eq 0 ]; then
  echo "No Swift files found under Shared/."
  exit 1
fi

APP_SWIFT_FILES=(
  CreditClockApp/CreditClockApp.swift
  CreditClockApp/ContentView.swift
)

WIDGET_SWIFT_FILES=(
  CreditClockWidget/CreditClockWidgetBundle.swift
  CreditClockWidget/CreditClockWidget.swift
)

echo "[check] Type-check shared files"
xcrun swiftc -typecheck "${SHARED_SWIFT_FILES[@]}"

echo "[check] Type-check macOS app target"
xcrun swiftc -typecheck "${APP_SWIFT_FILES[@]}" "${SHARED_SWIFT_FILES[@]}"

echo "[check] Type-check widget target"
xcrun swiftc -typecheck "${WIDGET_SWIFT_FILES[@]}" "${SHARED_SWIFT_FILES[@]}"

echo "[check] All pre-commit checks passed."
