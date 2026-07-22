#!/usr/bin/env bash
#
# run-dev.sh — dev launcher for ScannersApp (Phase 5). Real .app bundling (Info.plist,
# dylib embedding, codesign) is Phase 6; until then this is how you run the SwiftUI app.
#
# `swift build`/`swift run` already resolve Vendor/lib's dylibs via the rpath baked into
# ScannerKit's linker settings (see Package.swift's `vendorLibDir`), so this script doesn't
# need any DYLD_LIBRARY_PATH games itself — it exists mainly to make mock-mode the
# convenient, discoverable default for UI development.
#
# Usage:
#   Scripts/run-dev.sh            # mock mode (SCANNERS_MOCK=1) -- no hardware needed
#   Scripts/run-dev.sh --real     # real hardware (SCANNERS_MOCK unset)
#
# Hardware discipline: at most one process may talk to the scanner at a time. --real
# refuses to start if another SANE-ish process already appears to be using it.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '==> %s\n' "$*"; }

mode="mock"
if [[ "${1:-}" == "--real" ]]; then
  mode="real"
fi

if [[ "$mode" == "real" ]]; then
  log "Checking for other SANE-ish processes (hardware discipline: one at a time)"
  other_procs="$(ps aux | grep -iE 'sane-probe|scanimage|saned|sane-find-scanner|scannerkit-cli|outputkit-cli' \
    | grep -v -E 'grep|run-dev\.sh' || true)"
  if [[ -n "$other_procs" ]]; then
    echo "error: another SANE-related process appears to be running; refusing to start a second one:" >&2
    echo "$other_procs" >&2
    exit 1
  fi
  log "Running ScannersApp against real hardware"
  exec swift run --package-path "$ROOT_DIR" ScannersApp
else
  log "Running ScannersApp in mock mode (SCANNERS_MOCK=1, no hardware needed)"
  exec env SCANNERS_MOCK=1 swift run --package-path "$ROOT_DIR" ScannersApp
fi
