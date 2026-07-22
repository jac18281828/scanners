# Phase 3 — ScannerKit: Swift SANE interop and scan pipeline

You are implementing Phase 3 of the Scanners project. Read `DESIGN.md` first. Repo:
`/Users/john/src/scanners`. Phases 1–2 are done: SwiftPM skeleton exists and
`Scripts/build-sane.sh` produces vendored `libsane`/`libusb` in `Vendor/`. Hardware is
connected; one scanner process at a time.

## Design constraints (from DESIGN.md — do not re-decide)

- `CSane` C shim target: module map over the vendored `sane/sane.h`, linking `Vendor/lib`.
- `SaneBackend` protocol so all logic is testable against `MockSane`.
- Blocking SANE calls run on a dedicated thread; public API is async Swift.

## Tasks

1. `CSane` system-library target (header search path + linker settings pointed at
   `Vendor/`). Dev builds may use `DYLD`-free rpath linking: add `-rpath` to the package's
   linker settings so `swift test`/`swift run` find Vendor dylibs without env hacks.
2. `ScannerKit` public API (final names are yours; shape is not):
   - `ScannerDiscovery`: enumerate devices, return id + human name. Re-enumerate on demand
     — device strings like `hp5590:libusb:000:016` change across replugs.
   - `ScanConfiguration`: mode (`color`, `gray`, `blackAndWhite`), requested dpi,
     source (flatbed/adf), scan area (default full bed).
   - Resolution policy: native set {100,200,300,600,1200,2400}; a non-native request scans
     at smallest native ≥ requested and records both `requestedDPI` and `hardwareDPI` so
     OutputKit can downscale. Mode mapping: `blackAndWhite` → SANE `Lineart`,
     `gray` → `Gray`, `color` → `Color`.
   - `ScanSession.scan(config:) -> AsyncThrowingStream<ScanEvent, Error>` where events are
     `.started(parameters)`, `.progress(Double)`, `.completed(ScannedPage)`.
     `ScannedPage` carries CGImage + physical size (mm) + dpi metadata.
   - Frame decoding: handle SANE frame formats the hp5590 emits (RGB and gray/lineart
     bit-depth 1 and 8). 1-bit lineart must unpack to a proper CGImage.
   - Error taxonomy: deviceNotFound, deviceBusy, cancelled, ioError(status) — mapped from
     SANE_Status with readable messages.
   - Cancellation: `sane_cancel` wired to Swift task cancellation.
3. `MockSane`: scripted device list, option behavior (including dpi snapping with
   SANE_INFO_INEXACT semantics), and synthetic frame data for all three modes.
4. Tests (no hardware): discovery, option negotiation, dpi policy, 1-bit unpacking
   (golden bytes → expected pixels), cancellation, error mapping.
5. `scannerkit-cli` executable target: `scannerkit-cli list` and
   `scannerkit-cli scan --mode gray --dpi 100 -o /tmp/out.png`. This is the hardware smoke
   tool for this and later phases.

## Out of scope

PDF/OCR/export (Phase 4), UI (Phase 5), bundling (Phase 6).

## Acceptance gates

- `swift test` clean, lint/format clean, CI green.
- Local hardware check: `scannerkit-cli list` shows the 4570c;
  `scannerkit-cli scan` at 100dpi gray AND 300dpi lineart AND 200dpi color each produce a
  correct-looking PNG (open and eyeball them; sizes must match dpi × bed area).
- No public ScannerKit API takes or returns raw SANE types.

## Escalation

If hp5590 emits three-pass frames or an unexpected frame format, stop and report with the
actual `SANE_Parameters` dump rather than guessing a decoder.
