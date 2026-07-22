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
   fetch on first use. `OCREngine` takes the language as a parameter (default `en-US`);
   Phase 5's Settings pane (⌘,) gets an OCR-language control that plugs into it. (Pinning
   language alone did not fix the CI hang described in decision #7 below — kept anyway
   since it removes a real network dependency with no downside.)
7. **⚠ `OCREngine.recognitionLevel` is a parameter: `.accurate` in the shipped app,
   `.fast` in CI.** Phase 4's CI runs hung for the full `.accurate` recognition path
   (15-22min, twice, on two different fix attempts — language pinning did not help) but
   completed in ~1.5min under `.fast` — isolating the cause to `.accurate` mode itself,
   not language detection. Suspected cause: GitHub's macOS Actions runners are
   virtualized with no Neural Engine/GPU passthrough, and `.accurate` mode's on-device
   model needs that acceleration to run in reasonable time. `.fast` doesn't have the same
   dependency. CI-run OCR tests request `.fast` explicitly and use a relaxed accuracy bar
   for that mode (real quality is only meaningfully validated locally, on real Mac
   hardware, at `.accurate`). Ship default stays `.accurate` — this is a CI-environment
   accommodation, not a product quality decision.
8. **Ad-hoc signing now, Developer ID later.** Release workflow signs with `-` unless
   `MACOS_CERT_P12`/`MACOS_CERT_PASSWORD`/`APPLE_TEAM_ID` secrets exist, then it switches to
   Developer ID + notarization with no workflow rewrite. README documents the one-time
   Gatekeeper right-click-open for ad-hoc builds.
9. **⚠ Auto-crop to detected document edges via `VNDetectDocumentSegmentationRequest`.**
   Full-bed scans include the platen/lid background around the actual document — surfaced
   by hands-on Phase 5 testing. Vision's document-segmentation request (already used for
   OCR elsewhere in OutputKit) detects the document's quadrilateral within the full-bed
   image; OutputKit crops to it (perspective-corrected to a rectangle) and recomputes
   `widthMM`/`heightMM` proportionally from the crop region against the original full-bed
   physical size, so PDF page sizing (decision from "PDF assembly" — true-size printing)
   stays correct post-crop. Pure CGImage-in/CGImage-out, no hardware dependency, testable
   with synthetic fixtures (a rendered "document" rect on a contrasting background) same as
   OCREngine. **Fallback: if no document boundary is detected (blank bed, low contrast,
   detection failure), keep the full, uncropped bed scan rather than fail or guess** — never
   block a scan on this. The UI shows the auto-cropped result; a manual override/adjust
   affordance is a reasonable follow-up but not required for v1 if time-constrained (note
   in the phase report if deferred).

   **Addendum (post-v0.1.0 bug fix): unconditional perspective correction was baking
   detection noise in as fake rotation.** John reported real-hardware scans coming out
   "rotated or crooked" post-crop even though the raw full-bed scan wasn't. Real-hardware
   repro (HP ScanJet 4570c, a flat document already square on the platen) confirmed it:
   `VNDetectDocumentSegmentationRequest` returned a confidently-detected (0.99) quad whose
   top edge read +2.82° off horizontal but whose bottom edge read -0.31° — two corners
   landed a few pixels apart on what turned out to be Vision's own coarse internal
   quantization grid, not a real rotated rectangle (a true rotated rectangle has parallel
   top/bottom edges; these disagreed by 3.1°). `CIPerspectiveCorrection` doesn't know the
   difference — it forces whatever quad it's given into a rectangle, so that per-corner
   noise came out as a visible, inconsistent shear in the cropped output (measured: text
   baselines that read flat pre-crop, within ~0.15°, showed 0°–0.51° of *varying* tilt
   post-crop — the hallmark of a keystone warp, not a uniform rotation).

   Fix: `DocumentCropper` now estimates the quad's rotation by averaging all four edges'
   implied angle (top, bottom, left-from-vertical, right-from-vertical) rather than reading
   any single edge — real rotation has all four edges agree, so noise on one or two edges
   mostly cancels out of the average while a genuine skew still survives it. On the
   measured real-hardware case that average is 0.63°. Below `maximumNoiseRotationDegrees`
   (2.0°, >3x that measured noise, still well under the tens-of-degrees a real skewed
   document produces), `crop` snaps to the quad's plain axis-aligned bounding box instead
   of running `CIPerspectiveCorrection` — no warp, because there's nothing real to correct.
   Above it, perspective correction runs exactly as before. Re-scanning the same real
   document post-fix: baseline tilt in the crop matches the pre-crop source again (~0.15°,
   flat/consistent, not the 0°–0.51° varying shear from before). Physical-mm recomputation
   post-crop (`widthMM`/`heightMM` from the corrected image's own pixel count) is unchanged
   by this — it already worked from the corrected output image's dimensions regardless of
   which correction path produced them.

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
