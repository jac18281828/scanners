# Phase 2 — Vendored SANE build (libsane + hp5590 + libusb)

You are implementing Phase 2 of the Scanners project. Read `DESIGN.md` first. Repo:
`/Users/john/src/scanners`. The HP 4570c is physically connected — you may run hardware
smoke tests, but never two scanner processes at once.

## Goal

A reproducible script that produces the arm64 dylibs the app will bundle:
`libsane` with the hp5590 backend **preloaded** (statically linked in), plus `libusb-1.0`.
Binaries are build artifacts, not committed.

## Tasks

1. `Scripts/build-sane.sh`:
   - Pin versions: sane-backends 1.4.0, libusb (current stable; pin the exact tag).
     Download source tarballs, verify SHA-256 (record the hashes in the script).
   - Build libusb arm64 → `Vendor/lib/libusb-1.0.dylib`.
   - Build sane-backends: `BACKENDS="hp5590" ./configure --enable-preload
     --prefix=<staging> --without-snmp` (trim other optional deps; the goal is a minimal
     libsane that needs only libusb). If `--enable-preload` is absent/broken in 1.4.0,
     STOP and report — fallback is the dll-backend + SANE_CONFIG_DIR approach, which is a
     design change requiring sign-off.
   - Fix install names: every produced dylib gets `@rpath/...` install names and
     inter-dylib references via `install_name_tool`; verify with `otool -L` in the script.
   - Output to `Vendor/` (gitignored except a `Vendor/README.md` explaining regeneration).
2. `Scripts/smoke-sane.sh`: builds a tiny C or Swift probe against the vendored libsane
   (DYLD_LIBRARY_PATH pointed at Vendor/lib for the probe only), calls `sane_init` +
   `sane_get_devices`, asserts an `hp5590:` device is present, prints it.
3. CI: add a job (or extend ci.yml) that runs `build-sane.sh` and caches the result keyed
   on script hash + pinned versions. The smoke script's *device assertion* is skipped in CI
   (no scanner); it still asserts `sane_init` succeeds and the libraries load.

## Out of scope

No Swift interop layer (Phase 3). No app bundling (Phase 6).

## Acceptance gates

- `Scripts/build-sane.sh` runs clean from scratch on this Mac; re-run is idempotent.
- `otool -L` on every Vendor dylib shows only `@rpath`, system libs, and no Homebrew paths.
- `Scripts/smoke-sane.sh` finds the hp5590 device locally (real hardware check).
- CI green including the new cached job.

## Escalation

Missing build deps (autoconf etc.): install via brew, record them in Vendor/README.md.
Any configure flag that won't work as designed: stop and report, don't substitute a
different bundling strategy on your own.
