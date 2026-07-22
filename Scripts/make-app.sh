#!/usr/bin/env bash
#
# make-app.sh — assemble build/Scanners.app from a release build + the vendored SANE
# dylibs. See DESIGN.md decision #8 (ad-hoc signing now, Developer ID later) and
# Phase 6's packaging task.
#
# Env:
#   VERSION            override the version string (default: `git describe --tags`)
#   CODESIGN_IDENTITY  if set, sign with this identity + hardened runtime + timestamp
#                       (Developer ID). Unset/empty -> ad-hoc ("-") signing.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
APP_DIR="$BUILD_DIR/Scanners.app"
VENDOR_LIB="$REPO_ROOT/Vendor/lib"

echo "==> make-app.sh: repo=$REPO_ROOT build=$BUILD_DIR"

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
if [[ ! -f "$VENDOR_LIB/libsane.dylib" || ! -f "$VENDOR_LIB/libusb-1.0.dylib" ]]; then
  echo "error: Vendor/lib dylibs missing — run Scripts/build-sane.sh first" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Version (from git tag/describe; overridable)
# ---------------------------------------------------------------------------
RAW_VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --tags --always 2>/dev/null || echo 0.0.0-dev)}"
RAW_VERSION="${RAW_VERSION#v}"
SHORT_VERSION="${RAW_VERSION%%-*}"
if [[ ! "$SHORT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  SHORT_VERSION="0.0.0"
fi
echo "==> version: short=$SHORT_VERSION full=$RAW_VERSION"

# ---------------------------------------------------------------------------
# 2. Release build
# ---------------------------------------------------------------------------
echo "==> swift build -c release --arch arm64"
(cd "$REPO_ROOT" && swift build -c release --arch arm64 --product ScannersApp)

BUILT_BIN="$REPO_ROOT/.build/release/ScannersApp"
if [[ ! -x "$BUILT_BIN" ]]; then
  echo "error: expected release binary at $BUILT_BIN" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Bundle layout
# ---------------------------------------------------------------------------
echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"

cp "$BUILT_BIN" "$APP_DIR/Contents/MacOS/Scanners"
cp "$VENDOR_LIB/libsane.dylib" "$APP_DIR/Contents/Frameworks/"
cp "$VENDOR_LIB/libusb-1.0.dylib" "$APP_DIR/Contents/Frameworks/"

# App icon: flat SF-Symbol-derived scanner glyph, generated fresh every build.
"$REPO_ROOT/Scripts/make-icon.sh"
cp "$BUILD_DIR/Scanners.icns" "$APP_DIR/Contents/Resources/Scanners.icns"

COPYRIGHT_YEAR="$(date +%Y)"
cat >"$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Scanners</string>
	<key>CFBundleIconFile</key>
	<string>Scanners</string>
	<key>CFBundleIdentifier</key>
	<string>com.2ad.scanners</string>
	<key>CFBundleName</key>
	<string>Scanners</string>
	<key>CFBundleDisplayName</key>
	<string>Scanners</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$SHORT_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$RAW_VERSION</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>BSD 3-Clause License. Copyright (c) $COPYRIGHT_YEAR, John A Cairns.</string>
	<key>LSApplicationSecondaryDeviceOnly</key>
	<false/>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------------------
# 4. install_name_tool — resolve dylibs via @executable_path/../Frameworks
# ---------------------------------------------------------------------------
EXE="$APP_DIR/Contents/MacOS/Scanners"
echo "==> fixing rpaths on $EXE"

# Drop build-machine-specific rpaths baked in by SwiftPM's linker settings
# (Package.swift's vendorLibDir is an absolute path on this checkout, and the Xcode
# toolchain rpath is local-machine-only) so the shipped binary carries no build-tree
# paths and can't silently fall back to reading dylibs off this developer's disk.
existing_rpaths="$(otool -l "$EXE" | awk '/cmd LC_RPATH/{getline; getline; print $2}')"
while IFS= read -r rp; do
  [[ -z "$rp" ]] && continue
  case "$rp" in
  "$REPO_ROOT"/Vendor/lib | */Xcode.app/*)
    install_name_tool -delete_rpath "$rp" "$EXE"
    ;;
  esac
done <<<"$existing_rpaths"

install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"

# ---------------------------------------------------------------------------
# 5. Codesign — ad-hoc by default, Developer ID if CODESIGN_IDENTITY is set
# ---------------------------------------------------------------------------
DYLIBS=("$APP_DIR/Contents/Frameworks/libsane.dylib" "$APP_DIR/Contents/Frameworks/libusb-1.0.dylib")

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> codesign: Developer ID identity '$CODESIGN_IDENTITY', hardened runtime + timestamp"
  SIGN_ARGS=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY")
else
  echo "==> codesign: ad-hoc ('-')"
  SIGN_ARGS=(--force --sign -)
fi

for dylib in "${DYLIBS[@]}"; do
  codesign "${SIGN_ARGS[@]}" "$dylib"
done
codesign "${SIGN_ARGS[@]}" "$APP_DIR"

echo "==> verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "==> otool -L $EXE"
otool -L "$EXE"

echo "==> done: $APP_DIR (version $SHORT_VERSION)"
