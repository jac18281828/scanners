# Scanners — Design

A native macOS (arm64) document/image scanning app for the HP ScanJet 4570c, replacing
GNOME Document Scanner on a dying Linux box. Download, drag to Applications, scan.

## Validated hardware facts (2026-07-22, on this Mac)

- Scanner: HP ScanJet 4570c, USB `03f0:1305`, connected via CalDigit TS4 hub.
- Driver: SANE 1.4.0 `hp5590` backend. Detected as `hp5590:libusb:NNN:NNN` (bus/address
  vary per plug event — always re-enumerate, never hardcode the device string).
- A real 75dpi color scan succeeded end-to-end via `scanimage`. No kernel driver, no TWAIN,
  pure userspace libusb.
- Native resolutions: **100, 200, 300, 600, 1200, 2400** dpi.
- Modes: `Color`, `Color (48 bits)`, `Gray`, `Lineart`.
- Sources: `Flatbed` (default), `ADF`, `ADF Duplex`, `TMA Slides`, `TMA Negatives`.
- Max scan area: 215.889 × 297.699 mm (A4-ish).

## Architecture

```
Scanners.app
├── ScannersApp        SwiftUI app target (UI, presets, session flow)
├── ScannerKit         Swift library: SANE interop, device lifecycle, scan pipeline
│   └── CSane          C shim module (module map over sane/sane.h)
├── OutputKit          Swift library: PDF assembly, Vision OCR layer, image export
└── Vendor/            Bundled dylibs: libsane (hp5590 preloaded) + libusb, arm64
```

- **SwiftPM package, no .xcodeproj.** App bundle assembled by `Scripts/make-app.sh`
  (Info.plist, dylib embedding, install_name fixes, codesign). Everything reviewable text.
- **ScannerKit** defines a `SaneBackend` protocol; `RealSane` wraps the C API, `MockSane`
  drives tests. Scanning is blocking C — runs on a dedicated thread, publishes progress
  via AsyncStream.
- **OutputKit** is pure (CGImage in, bytes out) — fully unit-testable without hardware.

## Key decisions (⚠ = flagged, revisit if wrong)

1. **SANE bundled via `--enable-preload`.** Build sane-backends from source with
   `BACKENDS="hp5590" --enable-preload` so hp5590 is statically linked into one
   `libsane.dylib` — no dlopen path games, no dll.conf, no config dir. Bundle that plus
   libusb in `Contents/Frameworks` with `@rpath` fixes. Homebrew SANE stays a dev-only
   convenience.
2. **⚠ App Sandbox OFF.** libusb needs raw USB device access; sandboxed apps can't get it
   outside the App Store's entitlement process. Standard for SANE-based mac apps. Hardened
   runtime gets enabled when the Developer ID lands.
3. **⚠ 75/150 dpi are synthetic.** Device minimum is 100. For a requested dpi not in the
   native set, scan at the smallest native dpi ≥ requested and downscale with
   CoreGraphics (high interpolation quality). PDF page size always computed from physical
   mm so pages print at true size.
4. **⚠ "Black & white" = Lineart (1-bit).** Small files, crisp text. Phase 4 must validate
   Vision OCR quality on Lineart scans; if poor, switch text mode to Gray + Otsu threshold
   for display while feeding Gray to OCR. Escalate to John only if neither works.
5. **OCR text layer via CGContext PDF drawing.** Draw the page image, then draw recognized
   strings in invisible text mode (`.invisible`) at their Vision bounding boxes. PDFKit
   alone can't do this; CoreGraphics can.
6. **⚠ OCR language pinned to English (`en-US`), not Vision's automatic language
   detection.** `automaticallyDetectsLanguage` can trigger an on-device language-model
   fetch on first use; this hung indefinitely on a fresh GitHub Actions macOS runner
   (Phase 4, ~22min before manual cancellation — see STATE.md). Pinning a fixed language
   avoids that fetch entirely, in CI and in production, with no `.accurate`→`.fast`
   quality tradeoff. `OCREngine` takes the language as a parameter (default `en-US`);
   Phase 5's Settings pane (⌘,) gets an OCR-language control that plugs into it.
7. **Ad-hoc signing now, Developer ID later.** Release workflow signs with `-` unless
   `MACOS_CERT_P12`/`MACOS_CERT_PASSWORD`/`APPLE_TEAM_ID` secrets exist, then it switches to
   Developer ID + notarization with no workflow rewrite. README documents the one-time
   Gatekeeper right-click-open for ad-hoc builds.

## Product behavior

- **Two modes.** Text: default 300dpi B&W; also color; dpi 75/150/300/600.
  Image: default 600dpi color; also B&W; dpi 300/600/1200/2400.
- **PDF flow (multipage).** Scan → page appears in thumbnail strip → "Scan Next Page" loop
  → "Save PDF…". Text-mode PDFs get the OCR layer.
- **Image flow (single).** One scan → "Save Image…" — JPEG default; PNG, TIFF, HEIC options.
- **New Document (⌘N)** resets the session; many documents per app session.
- **Settings: presets, not forms.** Preset chips in the main window (Text Doc, Photo,
  Archive 2400, + user-defined). One click = mode+dpi+color+format applied. Settings pane
  (⌘,) manages presets, default save folder, filename template (`scan-2026-07-22-001`),
  source (Flatbed/ADF), lamp timeout, OCR language (default English). Last-used settings
  persist. No modal ceremony:
  the main window always shows current mode/dpi/color inline, editable in place.

## Quality bar

- swift-format + SwiftLint enforced in CI (GitHub Actions, macos arm64 runner).
- Unit tests for ScannerKit (via MockSane) and OutputKit (golden files); no test may
  require hardware. Hardware smoke tests are explicit scripts run locally at phase gates.
- Every phase ends with an adversarial review by a fresh agent before its commit lands.
- BSD-3-Clause, public GitHub repo `scanners`, release = tagged build → .app zip on
  GitHub Releases.
