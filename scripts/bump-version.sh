#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ "${CREDITCLOCK_SKIP_VERSION_BUMP:-0}" = "1" ]; then
  echo "[version] Skipping version bump (CREDITCLOCK_SKIP_VERSION_BUMP=1)."
  exit 0
fi

VERSION_FILE="VERSION"
GENERATED_FILE="Shared/Generated/BuildVersion.generated.swift"

if [ ! -f "$VERSION_FILE" ]; then
  echo "0.1.0" > "$VERSION_FILE"
fi

CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "[version] Invalid VERSION format: '$CURRENT_VERSION' (expected x.y.z)" >&2
  exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"
NEXT_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"

printf '%s\n' "$NEXT_VERSION" > "$VERSION_FILE"

CURRENT_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
DISPLAY_VERSION="creditclock-macos-${NEXT_VERSION}-${CURRENT_HEAD}"

cat > "$GENERATED_FILE" <<SWIFT
import Foundation

enum BuildVersion {
    static let semver = "${NEXT_VERSION}"
    static let sourceRevision = "${CURRENT_HEAD}"
    static let generatedAtUTC = "${GENERATED_AT}"
    static let display = "${DISPLAY_VERSION}"
}
SWIFT

git add "$VERSION_FILE" "$GENERATED_FILE"

echo "[version] ${CURRENT_VERSION} -> ${NEXT_VERSION}"
