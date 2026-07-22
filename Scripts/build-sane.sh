#!/usr/bin/env bash
#
# build-sane.sh — build the vendored SANE stack (libsane + hp5590, preloaded) and
# libusb, arm64, and drop the finished dylibs in Vendor/lib.
#
# Reproducible: pinned tarball URLs + SHA-256, no floating "latest" anything.
# Idempotent: wipes its own scratch/output dirs and rebuilds from scratch every run;
# downloaded tarballs are cached (by verified hash) under Vendor/.cache to avoid
# re-fetching on every invocation.
#
# See Vendor/README.md for the sane-backends 1.4.0 --enable-preload duplicate-symbol
# bug this script works around, and why the fix patches backend/Makefile.in by hand
# instead of regenerating it via autoreconf.

set -euo pipefail

# ---------------------------------------------------------------------------
# Pinned versions (do not float these — bump deliberately, re-verify hashes)
# ---------------------------------------------------------------------------
SANE_VERSION="1.4.0"
SANE_URL="https://gitlab.com/-/project/429008/uploads/843c156420e211859e974f78f64c3ea3/sane-backends-1.4.0.tar.gz"
SANE_SHA256="f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72"

LIBUSB_VERSION="1.0.30"
LIBUSB_URL="https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2"
LIBUSB_SHA256="fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf"

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
PATCH_FILE="$VENDOR_DIR/patches/sane-backends-1.4.0-dedupe-preload-libadd.patch"

CACHE_DIR="$VENDOR_DIR/.cache"       # downloaded tarballs, gitignored
BUILD_DIR="$VENDOR_DIR/.build"       # scratch: extract + configure + make, gitignored
STAGE_USB="$BUILD_DIR/stage-usb"     # libusb `make install` staging prefix
STAGE_SANE="$BUILD_DIR/stage-sane"   # sane-backends `make install` staging prefix

OUT_LIB="$VENDOR_DIR/lib"            # final dylibs the app bundles, gitignored
OUT_INCLUDE="$VENDOR_DIR/include"    # sane/*.h for the Phase 3 CSane module map, gitignored

log() { printf '==> %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: this script builds arm64-only dylibs; host is $(uname -m)" >&2
  exit 1
fi

for tool in curl shasum tar patch make clang libtool codesign otool install_name_tool; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' not found" >&2
    exit 1
  fi
done

if ! command -v pkg-config >/dev/null 2>&1; then
  log "pkg-config not found, installing via brew (recorded in Vendor/README.md)"
  brew install pkgconf
fi

# ---------------------------------------------------------------------------
# Clean scratch + output (idempotent: always a from-scratch rebuild)
# ---------------------------------------------------------------------------
log "Cleaning previous build output"
rm -rf "$BUILD_DIR" "$OUT_LIB" "$OUT_INCLUDE"
mkdir -p "$CACHE_DIR" "$BUILD_DIR" "$STAGE_USB" "$STAGE_SANE" "$OUT_LIB" "$OUT_INCLUDE"

# ---------------------------------------------------------------------------
# Download + verify
# ---------------------------------------------------------------------------
download_verified() {
  local url="$1" sha256="$2" out="$3"
  if [[ -f "$out" ]] && echo "$sha256  $out" | shasum -a 256 -c - >/dev/null 2>&1; then
    log "Using cached $(basename "$out") (hash verified)"
    return
  fi
  log "Downloading $(basename "$out")"
  curl -fsSL -o "$out" "$url"
  echo "$sha256  $out" | shasum -a 256 -c -
}

SANE_TARBALL="$CACHE_DIR/sane-backends-$SANE_VERSION.tar.gz"
LIBUSB_TARBALL="$CACHE_DIR/libusb-$LIBUSB_VERSION.tar.bz2"

download_verified "$SANE_URL" "$SANE_SHA256" "$SANE_TARBALL"
download_verified "$LIBUSB_URL" "$LIBUSB_SHA256" "$LIBUSB_TARBALL"

# ---------------------------------------------------------------------------
# libusb: extract, configure, build, install (arm64, shared only)
# ---------------------------------------------------------------------------
log "Extracting libusb $LIBUSB_VERSION"
tar xjf "$LIBUSB_TARBALL" -C "$BUILD_DIR"
LIBUSB_SRC="$BUILD_DIR/libusb-$LIBUSB_VERSION"

log "Configuring libusb"
(
  cd "$LIBUSB_SRC"
  ./configure --prefix="$STAGE_USB" --enable-shared --disable-static \
    CFLAGS="-arch arm64" LDFLAGS="-arch arm64"
)

log "Building libusb"
make -C "$LIBUSB_SRC" -j"$(sysctl -n hw.ncpu)"

log "Installing libusb to staging prefix"
make -C "$LIBUSB_SRC" install

# ---------------------------------------------------------------------------
# sane-backends: extract, patch, configure (hp5590 preloaded), build, install
# ---------------------------------------------------------------------------
log "Extracting sane-backends $SANE_VERSION"
tar xzf "$SANE_TARBALL" -C "$BUILD_DIR"
SANE_SRC="$BUILD_DIR/sane-backends-$SANE_VERSION"

log "Applying dedupe-preload-LIBADD patch (see Vendor/README.md)"
(cd "$SANE_SRC" && patch -p1 --no-backup-if-mismatch < "$PATCH_FILE")

log "Configuring sane-backends (BACKENDS=hp5590, --enable-preload)"
(
  cd "$SANE_SRC"
  export PKG_CONFIG_PATH="$STAGE_USB/lib/pkgconfig"
  BACKENDS="hp5590" ./configure \
    --enable-preload \
    --prefix="$STAGE_SANE" \
    --without-snmp \
    --without-poppler-glib \
    --without-libcurl \
    --without-gphoto2 \
    --without-v4l \
    CC="clang -arch arm64 -Wno-error=incompatible-function-pointer-types" \
    CFLAGS="-arch arm64" LDFLAGS="-arch arm64"
)

log "Building sane-backends (this is the step that used to fail with 30 duplicate symbols)"
make -C "$SANE_SRC" -j"$(sysctl -n hw.ncpu)"

log "Installing sane-backends to staging prefix"
make -C "$SANE_SRC" install

# ---------------------------------------------------------------------------
# Assemble Vendor/lib: concrete dylibs, @rpath install names, fixed-up refs
# ---------------------------------------------------------------------------
log "Assembling Vendor/lib"

resolve_symlink() {
  local link="$1" resolved
  resolved="$(readlink -f "$link" 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    echo "error: could not resolve symlink $link" >&2
    exit 1
  fi
  echo "$resolved"
}

# libusb's real file is libusb-1.0.0.dylib with a libusb-1.0.dylib symlink;
# copy the real bytes in under the plain name so Vendor/lib has no symlinks.
LIBUSB_REAL="$(resolve_symlink "$STAGE_USB/lib/libusb-1.0.dylib")"
cp "$LIBUSB_REAL" "$OUT_LIB/libusb-1.0.dylib"

# sane's real file is libsane.<major>.dylib with a libsane.dylib symlink; same deal.
LIBSANE_REAL="$(resolve_symlink "$STAGE_SANE/lib/libsane.dylib")"
cp "$LIBSANE_REAL" "$OUT_LIB/libsane.dylib"

chmod u+w "$OUT_LIB"/*.dylib

install_name_tool -id "@rpath/libusb-1.0.dylib" "$OUT_LIB/libusb-1.0.dylib"
install_name_tool -id "@rpath/libsane.dylib" "$OUT_LIB/libsane.dylib"
install_name_tool -change "$STAGE_USB/lib/libusb-1.0.0.dylib" "@rpath/libusb-1.0.dylib" "$OUT_LIB/libsane.dylib"

# Re-sign after install_name_tool invalidates the existing signature (required
# for dyld to load the dylib on Apple Silicon, even ad-hoc).
codesign -s - -f "$OUT_LIB/libusb-1.0.dylib" "$OUT_LIB/libsane.dylib"

# ---------------------------------------------------------------------------
# Headers for the Phase 3 CSane module map
# ---------------------------------------------------------------------------
cp -R "$STAGE_SANE/include/sane" "$OUT_INCLUDE/"

# ---------------------------------------------------------------------------
# Verify: no Homebrew paths, only @rpath + system libs
# ---------------------------------------------------------------------------
log "Verifying install names (otool -L)"
fail=0
for dylib in "$OUT_LIB"/*.dylib; do
  echo "--- $dylib ---"
  otool -L "$dylib"
  if otool -L "$dylib" | tail -n +2 | grep -qE '/opt/homebrew|/usr/local/(Cellar|opt)'; then
    echo "error: $dylib links a Homebrew path" >&2
    fail=1
  fi
done
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

log "Build complete: $OUT_LIB/libsane.dylib, $OUT_LIB/libusb-1.0.dylib"
