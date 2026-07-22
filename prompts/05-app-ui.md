# Phase 5 — ScannersApp: SwiftUI interface

You are implementing Phase 5 of the Scanners project. Read `DESIGN.md` first — the
"Product behavior" section is the spec. Repo: `/Users/john/src/scanners`. ScannerKit and
OutputKit are done and tested; build the UI on their public APIs only. Hardware connected;
one scanner process at a time (kill stray `scannerkit-cli` first).

## The interface (professional, zero ceremony)

Single window, three regions:

- **Toolbar / control strip**: mode segmented control (Text | Image), inline dpi picker
  and color picker whose option sets swap per mode (Text: 75/150/300/600, default 300 B&W;
  Image: 300/600/1200/2400, default 600 Color), preset chips, big Scan button (⌘S? no —
  use Return or ⌘R; ⌘S is Save). Current settings always visible, editable in place, no
  drill-down to change dpi.
- **Canvas**: the current page preview at fit-to-window; scanning shows determinate
  progress driven by ScanEvent stream, with Cancel.
- **Page strip** (PDF flow): thumbnails of scanned pages, drag to reorder, delete on
  hover/backspace. Visible only when the session has >1 page or mode is Text.

Flows:
- **Text/PDF**: Scan → page lands in strip → Scan Next Page → … → Save PDF… (⌘S). OCR
  runs per-page in the background between scans so Save is instant. NSSavePanel with
  filename pre-filled from the template engine.
- **Image**: Scan → Save Image… (⌘S), format picker in the save panel (JPEG default,
  PNG/TIFF/HEIC), pre-filled filename.
- **New Document (⌘N)**: confirm if unsaved pages exist, then reset session.
- Scanner unplugged/busy: non-modal inline banner with Retry (re-enumerate), never a
  blocking alert loop.

**Presets**: built-ins "Text Doc" (text/300/B&W/PDF), "Photo" (image/600/color/JPEG),
"Archive" (image/2400/color/TIFF); user presets creatable from current settings ("Save as
preset…"). One click applies everything. Stored via UserDefaults/@AppStorage.

**Settings pane (⌘,)**: preset management (rename/delete/reorder), default save folder,
filename template, source (Flatbed/ADF), lamp-timeout toggle. One compact pane; no tabs
unless it genuinely won't fit.

**Last-used settings persist** across launches.

## Architecture

- Observable `DocumentSession` (pages, mode, config) and `ScanController` orchestrating
  ScannerKit; views stay dumb. All ScannerKit access behind the existing protocol so the
  app runs against `MockSane` via a `SCANNERS_MOCK=1` env var — used for UI development
  and UI tests without hardware.
- `swift run ScannersApp` must work for dev (window appears, mock scan works). Real
  .app bundling is Phase 6; for now a `Scripts/run-dev.sh` sets rpath/env as needed.

## Tests

- Unit tests for DocumentSession/ScanController state machine (mock-driven): scan-loop,
  reorder/delete, unsaved-changes gate, preset apply, persistence round-trip.
- Manual checklist executed with real hardware and recorded in your report: both flows
  end-to-end, cancel mid-scan, unplug mid-session, preset switching.

## Acceptance gates

- `swift test` clean, lint/format clean, CI green.
- Mock-mode app runs and completes both flows without hardware.
- Real-hardware manual checklist: all items pass, artifacts (a PDF and a JPEG you
  produced through the UI) saved under `/tmp/scanners-phase5/` and named in the report.

## Escalation

Spec ambiguity in UI details (spacing, exact control types): decide and note it — don't
stop. Anything conflicting with DESIGN.md product behavior: stop and report.
