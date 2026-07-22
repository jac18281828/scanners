#!/usr/bin/env bash
#
# make-dist.sh — zip build/Scanners.app as build/Scanners-<version>-arm64.zip.
# Assumes Scripts/make-app.sh has already produced build/Scanners.app (does not
# rebuild it, so callers control exactly what version gets zipped).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
APP_DIR="$BUILD_DIR/Scanners.app"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: $APP_DIR missing — run Scripts/make-app.sh first" >&2
  exit 1
fi

RAW_VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --tags --always 2>/dev/null || echo 0.0.0-dev)}"
RAW_VERSION="${RAW_VERSION#v}"

ZIP_NAME="Scanners-${RAW_VERSION}-arm64.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"
echo "==> ditto -c -k --keepParent $APP_DIR -> $ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> done: $ZIP_PATH"
ls -lh "$ZIP_PATH"
