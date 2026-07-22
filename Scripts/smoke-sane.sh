#!/usr/bin/env bash
#
# smoke-sane.sh — hardware smoke test for the vendored SANE stack.
#
# Builds a tiny C probe (Scripts/sane-probe.c) against Vendor/lib/libsane.dylib,
# runs it with DYLD_LIBRARY_PATH scoped to that single invocation (the probe
# binary itself carries no rpath), and checks that sane_init works and an
# hp5590: device is present.
#
# In CI (no scanner attached) set SANE_PROBE_SKIP_DEVICE_CHECK=1: sane_init and
# library loading are still asserted, only the "hp5590: device present" check
# is skipped.
#
# Hardware discipline: at most one process may talk to the scanner at a time.
# This script refuses to run if another SANE-ish process already appears to be
# using the device.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
OUT_LIB="$VENDOR_DIR/lib"
OUT_INCLUDE="$VENDOR_DIR/include"
PROBE_SRC="$ROOT_DIR/Scripts/sane-probe.c"
PROBE_BUILD_DIR="$VENDOR_DIR/.build/smoke"
PROBE_BIN="$PROBE_BUILD_DIR/sane-probe"

log() { printf '==> %s\n' "$*"; }

if [[ ! -f "$OUT_LIB/libsane.dylib" || ! -f "$OUT_LIB/libusb-1.0.dylib" ]]; then
  echo "error: Vendor/lib is missing libsane.dylib/libusb-1.0.dylib — run Scripts/build-sane.sh first" >&2
  exit 1
fi

if [[ "${SANE_PROBE_SKIP_DEVICE_CHECK:-}" != "1" ]]; then
  log "Checking for other SANE-ish processes (hardware discipline: one at a time)"
  # Exclude this script/grep itself; look for anything else that talks to a scanner.
  other_procs="$(ps aux | grep -iE 'sane-probe|scanimage|saned|sane-find-scanner' | grep -v -E 'grep|smoke-sane\.sh' || true)"
  if [[ -n "$other_procs" ]]; then
    echo "error: another SANE-related process appears to be running; refusing to start a second one:" >&2
    echo "$other_procs" >&2
    exit 1
  fi
fi

log "Building probe"
mkdir -p "$PROBE_BUILD_DIR"
clang -arch arm64 -I "$OUT_INCLUDE" -L "$OUT_LIB" -lsane -o "$PROBE_BIN" "$PROBE_SRC"
codesign -s - -f "$PROBE_BIN" >/dev/null 2>&1

log "Running probe (DYLD_LIBRARY_PATH scoped to this invocation only)"
set +e
DYLD_LIBRARY_PATH="$OUT_LIB" "$PROBE_BIN"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  log "Smoke test passed"
  exit 0
elif [[ "$status" -eq 2 ]]; then
  echo "error: sane_init succeeded but no hp5590: device was found" >&2
  exit 2
else
  echo "error: probe failed (exit $status) — sane_init or sane_get_devices did not succeed" >&2
  exit 1
fi
