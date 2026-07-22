# Phase 4 — OutputKit: PDF assembly, OCR layer, image export

You are implementing Phase 4 of the Scanners project. Read `DESIGN.md` first. Repo:
`/Users/john/src/scanners`. ScannerKit (Phase 3) provides `ScannedPage` (CGImage +
physical mm + requested/hardware dpi). OutputKit is pure — CGImage in, bytes out; every
test runs without hardware.

## Tasks

1. **Resampling.** `ScannedPage` normalization: when `requestedDPI < hardwareDPI`,
   downscale with CGContext at `.high` interpolation. Exact expected pixel dimensions
   asserted in tests (e.g. 100→75dpi on 215.889mm width: 850→637 px, match Phase-0
   observation of 638±1).
2. **PDF assembly.** `PDFBuilder.append(page:)` / `.finish() -> Data` using a CGContext
   PDF. Page media box from physical mm (1pt = 1/72in) so pages print true-size regardless
   of dpi. Image compression inside the PDF: JPEG for color/gray, CCITT/flate for 1-bit
   lineart (whatever CGImage destination supports — verify actual encoded size; a 300dpi
   lineart A4 page must land well under 200KB).
3. **OCR layer (text mode only).** Vision `VNRecognizeTextRequest` (accurate mode,
   language autodetect) on each page; draw recognized strings into the PDF context in
   invisible text rendering mode at their bounding boxes, font-size-fitted to box height.
   Result: selectable/searchable text in Preview.app over an unchanged visual.
   - **Validate OCR on Lineart input** (DESIGN.md flag #4): OCR a lineart-scanned test
     fixture; if recognition is materially worse than gray, implement the documented
     fallback (scan gray, threshold for display, OCR the gray) inside OutputKit's
     normalization path and record the finding in your report.
4. **Image export.** Single `ScannedPage` → JPEG (quality 0.85 default), PNG, TIFF, HEIC
   via ImageIO. Embed dpi metadata (kCGImagePropertyDPIWidth/Height) — verify with
   `sips -g dpiWidth`.
5. **Filename template engine** (used by the app later): `scan-{date}-{seq}` with
   collision-avoiding sequence within the target directory. Pure function + tests.
6. Tests: golden-file PDFs are brittle — instead assert structure (page count, media box
   dims, embedded-text presence via PDFKit `string` extraction, byte-size ceilings).
   Fixture images generated in-test or tiny committed PNGs; OCR tests use a rendered
   known-text fixture, asserting recovered text ≥ 95% match.

## Out of scope

UI, save panels, ScannerKit changes (if you need a ScannerKit API tweak, make the minimal
change and call it out in your report).

## Acceptance gates

- `swift test` clean, lint/format clean, CI green (Vision is available on CI macOS runners).
- A locally-run end-to-end proof: `scannerkit-cli` scan → OutputKit → a 2-page searchable
  PDF you open and text-select in Preview, plus one exported JPEG with correct dpi
  metadata. Script this as `Scripts/smoke-output.sh`.

## Escalation

If invisible-text placement is off in Preview (common y-flip bug), fix it properly
(Vision's normalized coordinates are bottom-left origin) — do not ship offset text. If
CCITT encoding for lineart isn't reachable via ImageIO/CG, flate is acceptable; note it.
