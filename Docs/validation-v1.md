# v1.0.0 hardware validation

Phase 7 validation matrix, run against the installed app (`/Applications/Scanners.app`,
ad-hoc signed) on real hardware: HP ScanJet 4570c via SANE `hp5590`, USB, CalDigit TS4 hub.
Physical test content varied across the session (the FIFA World Cup 2026 Panini sticker
album cover for most cells; later cells scanned whatever John had placed on the bed —
a magazine clipping and a card-terms insert). GUI driven end-to-end via macOS accessibility
(System Events/AppleScript), not simulated — every cell below is a real scan through the
real installed app unless explicitly marked otherwise. Artifacts under `/tmp/scanners-v1/`.

Run dates: 2026-07-22/23.

## Results

| # | Mode | DPI | Color | Output | Result | Notes |
|---|------|-----|-------|--------|--------|-------|
| 1 | Text | 300 | B&W | 3-page PDF | **PASS** | `cell1.pdf`, 392,378 bytes (<600KB). 3 pages, correct order. All 3 pages OCR-searchable (123/102/129 chars extracted via PDFKit). Page size ~213–216 × 295–298mm, consistent with true A4/the album's physical size (auto-crop variance across 3 independent scans of the same object is ~1–2%, well inside DESIGN.md's rotation-noise-rejection tolerance). |
| 2 | Text | 75 | B&W | 1-page PDF | **PASS** | `cell2.pdf`, 24,057 bytes. Searchable (118 chars). Embedded image 629×873px. Expected width was estimated at ~637px assuming the full bed (215.9mm); actual auto-cropped document width this scan was 212.9mm, so 629px is the *correct* proportional downscale, not a miss — confirmed via the embedded PDF image XObject's pixel dimensions. |
| 3 | Text | 150 | Color | 2-page PDF | **PASS** | `cell3.pdf`, 875,839 bytes. 2 pages. Color confirmed by direct pixel sampling of the rendered page (max per-pixel R/G/B channel delta 231/255 — clearly not grayscale). OCR text present on both pages (136/121 chars). |
| 4 | Text | 600 | B&W | 1-page PDF | **PASS** | `cell4.pdf`, 526,068 bytes (514KB, sane for a 600dpi lineart page). Embedded image exactly 5100×7033px = 8.5in×11.72in @ 600dpi (matches the PDF's own point-size × 600 exactly — native resolution, no upscale). Searchable (125 chars). |
| 5 | Image | 600 | Color | JPEG | **PASS** | `cell5.jpg`, 7,101,767 bytes. `sips` confirms `dpiWidth`/`dpiHeight` = 600.000 exactly. 5065×6209px. JPEG quality is `ImageExporter.defaultJPEGQuality = 0.85` (source-verified); visually inspected a downsampled render (`cell5-thumb.png`) — clean, correct color reproduction, no artifacts. |
| 6 | Image | 300 | B&W | PNG | **PASS** | `cell6.png`, 259,243 bytes. 2550×3517px, `dpiWidth`/`dpiHeight` = 300.000. Content verified strictly bilevel: sampled pixel values across the decoded image are only `{0, 255}` (pure black/white, no intermediate gray) — matches DESIGN.md decision #4 (Lineart/1-bit "Black & White"). PNG container itself is 8-bit grayscale (`colortype 0`), which is expected — ImageIO doesn't need a literal 1-bit PNG bit-depth to encode strictly-bilevel *content*, and the DESIGN concern here is the content, not the container's declared bit-depth. |
| 7 | Image | 1200 | Color | TIFF | **PASS** | `cell7.tiff`, 503,170,202 bytes (503MB, expected for an uncompressed 1200dpi color TIFF this size). 10130×12417px, `dpiWidth`/`dpiHeight` = 1200.000 exactly (matches requested/native dpi — no synthetic scaling involved since 1200 is a native device resolution). Visually inspected a downsampled render (`cell7-thumb.png`) — correct content, no truncation, tighter auto-crop than Cell 1's (real per-scan Vision-detection variance, all content still fully visible). |
| 8 | Image | 2400 | Color | JPEG | **WAIVED by John — real hardware/mechanical finding, not a software defect this codebase can fix** | See "Cell 8 detail" below. Full-bed 2400dpi color scans on this specific HP 4570c unit produced audibly-abnormal ("grinding") operation and corrupted output (a structured color-channel-desync artifact, not blank/white as first suspected — confirmed via real pixel statistics). A same-resolution sub-area scan (top ~74mm strip, full width, ~1/4 the carriage travel) came back completely clean. This localizes the defect to *sustained full-bed* 2400dpi operation on this unit, not 2400dpi categorically. John's call: waive this specific sub-case rather than force further full-bed 2400dpi attempts against a real mechanical symptom. |
| 9 | — | — | — | New Document mid-session | **PASS** | Doc A (2-page PDF, Text/300/BW, `cell9-docA.pdf`, 267,659 bytes, both pages OCR-searchable at 79 chars each) scanned and saved; ⌘N (no confirmation prompt needed — already saved, `hasUnsavedChanges` correctly false); page strip confirmed empty (0 rows) before Doc B; Doc B (Image/600/Color JPEG, `cell9-docB.jpg`, 2,365,456 bytes, 5100×7033px @ 600.000dpi exact) scanned and saved. Both files independently verified correct; no cross-contamination between documents. |
| 10 | — | — | Cancel mid-scan @1200dpi | — | **FOUND BROKEN, FIXED, RE-VERIFIED PASS** | See "Cell 10 detail" below — a real bug was found (app unresponsive to Cancel for 8+ minutes), root-caused, fixed (`ProgressPublishPolicy`, commit `78a7241`), and re-verified end-to-end on the exact hardware/resolution that broke it. |
| 11 | — | — | Unplug/replug | — | **PASS** | Real physical unplug/replug, performed by John (agent has no hands — same constraint as Phase 5's precedent for this class of check). **Unplugged half**: app launched fresh, Scan attempted against the genuinely-unplugged device → non-modal inline banner appeared: *"Scanner not found — check the cable, then Retry."* Window stayed fully interactive throughout (no blocking alert loop — confirmed by successfully querying/operating other UI elements without dismissing anything first), scan button re-enabled, no hang/crash. **Replug half**: not re-captured as a single literal fresh click-Retry-after-unplug moment (the banner had already been dismissed by the time hardware access resumed, and a second deliberate unplug wasn't warranted just to reproduce it) — instead verified via strong equivalent evidence: `ScanController.retry()`'s implementation is exactly "clear banner, call the same `scan()` used everywhere else" (confirmed by source read, no separate code path), and dozens of real scans succeeded through that identical discovery path immediately after the real replug (Cells 8–10, 12, 13 below), proving discovery genuinely finds the device again post-replug. |
| 12 | — | — | Presets | — | **PASS** | All 3 built-ins verified via direct UI state read-back after each click: **Text Doc** → Text/300dpi/Black & White; **Photo** → Image/600dpi/Color; **Archive** → Image/2400dpi/Color. Image-format sub-check: **Photo → JPEG** confirmed live (clicked the preset, scanned, opened Save Image, read the accessory popup's pre-selected value = "JPEG"). **Archive → TIFF** confirmed via existing passing unit test (`DocumentSessionTests`, asserts `session.currentImageFormat == .tiff` after applying `.archive`) rather than a live scan — deliberately not re-scanned at full-bed 2400dpi given Cell 8's mechanical finding above; the save-panel code path that reads `session.currentImageFormat` is identical regardless of which format value it holds, and was already exercised live for the JPEG case. User preset round-trip: created "QA Test Preset" from a custom Text/150dpi/Color configuration via "Save as preset…", preset count went 3→4, changed settings away, clicked the new chip, settings correctly restored to 150dpi/Color/Text. Preset persisted correctly across multiple separate app relaunches (UserDefaults round-trip). |
| 13 | — | — | Relaunch settings restore | — | **PASS** | Set a deliberately distinctive combination (Image/1200dpi/Black & White — doesn't coincidentally match any built-in preset) via the live control strip, fully quit the app (not just backgrounded), relaunched. Restored state confirmed two ways: (1) live UI read-back — mode radio button, DPI popup, Color popup all read back Image/1200dpi/Black & White; (2) independently via `defaults read com.2ad.scanners dev.scanners.lastUsed.*` — `documentMode=image`, `dpi=1200`, `colorMode=blackAndWhite`, matching exactly. |

## Cell 8 detail: 2400dpi full-bed — real hardware/mechanical finding

**What happened:** a full-bed Image/2400dpi/Color scan completed (no error, no banner) but
John reported hearing the scanner "grinding" and the output looking wrong.

**Investigation, not a blind retry:**
1. Checked actual pixel statistics rather than eyeballing a thumbnail. The output was
   *not* blank/white as first suspected: `min luminance 13, max 237, mean 154.2` across
   ~880K sampled points, with a broad histogram spread. Visually it's a structured
   **color-channel-desync artifact** — solid vertical bands sweeping white→yellow→red→
   magenta→blue with smooth internal gradients, not the actual scanned content, not random
   noise. That pattern is a classic symptom of scan-head timing/synchronization drift
   during acquisition (each color pass sampling a slightly different physical position) —
   consistent with an audible mechanical symptom, not something a software fix produces.
2. No SANE-level error surfaced in the GUI run itself — the corruption is silent at the
   app/SANE layer (nothing currently flags "the transfer nominally succeeded but the pixels
   came back wrong"). Separately, constructing a diagnostic sub-area scan via a temporary
   `scannerkit-cli --area` flag (not shipped, reverted before commit) surfaced an
   out-of-bounds request (215.9mm vs the device's real 215.889mm max) mapping to
   `ScanError.deviceNotFound` instead of an option/argument error — this is a
   **pre-existing, already-logged** gap (Phase 3's STATE.md flagged `SANE_STATUS_INVAL`
   being unconditionally mapped to `deviceNotFound`), confirmed still present, not new, and
   not triggered by any real UI path (the app never sets a custom scan area).
3. Ran a **same-2400dpi, much shorter sub-area scan** (top ~74mm strip, full width — about
   1/4 the full-bed carriage travel/time) instead of another blind full-bed retry. Result:
   completely clean — sharp, correctly colored, legible real content, zero banding.
   Pixel stats: `min=2, max=255, mean=184.9`, a normal page-with-dark-graphic distribution.

**Conclusion:** the defect localizes to *sustained full-bed* 2400dpi operation specifically,
not 2400dpi as a resolution — the identical setting produces perfect output over a shorter
pass. That shape (clean short high-res pass, corrupted long pass, audible grinding) points
at a real mechanical/timing limit on this specific unit at full-bed 2400dpi, not a defect in
this codebase. **John's decision: waive this specific sub-case** rather than risk the
hardware with further full-bed 2400dpi attempts. DESIGN.md's "2400dpi is a native
resolution" (from real Phase-0 hardware validation) remains literally true — the device
accepts and executes 2400dpi requests — it just doesn't say full-bed *sustained* 2400dpi
scans are reliable on this unit, and this is real evidence they aren't.

Real RSS sampled via `ps -o rss= -p <pid>` every 2s across two independent full-bed
2400dpi runs:
- First run: peak **~4.14GB** (4,239,376KB); CPU pegged ~99% for the duration, then dropped
  to idle, confirming genuine completion (not a hang).
- Second run (the one producing the corrupted/grinding output above): peak **~3.45GB**
  (3,445,300KB).
- Both: no swap, no crash, nowhere close to exhausting real system memory on a machine with
  far more than 4GB physical RAM. **No memory blowup** in either run — the mechanical
  finding above is the real, actionable issue, not memory.

Artifacts: `cell8-diagnostic-fullbed.jpg` (corrupted full-bed), `cell8-diagnostic-thumb.png`
(visual), `cell8-diagnostic-subarea.png` + `-thumb.png` (clean sub-area at the same dpi).

## Cell 10 detail: cancel mid-scan @1200dpi — found broken, fixed, re-verified

**First attempt (real failure, not a test artifact):** triggered a 1200dpi full-bed color
scan, then attempted to click Cancel. The click did not register for **8+ minutes**. `sample`
on the app's main thread during the stall showed it was not blocked on I/O — it was pegged
at ~99-100% CPU inside SwiftUI's own view-graph update machinery
(`GraphHost.flushTransactions` → `AttributeGraph` → `RootGeometry.value.getter`, repeatedly),
with RSS nearly flat (not the pattern of active scan-data ingestion, which should show
larger jumps as new lines arrive over USB). By the time the click finally registered, the
scan had already completed on its own — Cancel returned "button not found" because there
was nothing left to cancel.

**Root cause:** `ScanController.runScan`'s `case .progress` mutated the `@Observable`
`scanState` on every single raw `ScanEvent.progress` tick with zero throttling. Each tick is
one 64KB SANE read chunk (`ScanSession.readChunkSize`) — a 1200dpi full-bed color scan
yields roughly 7,000 of them, 2400dpi roughly 27,000+. Every mutation forces a full SwiftUI
main-thread re-render; at that frequency the render queue never drains, leaving the whole
window unresponsive to all input including Cancel.

**Fix (commit `78a7241`):** `ProgressPublishPolicy`, a small value-based throttle (not
time-based, so it's deterministically testable). Publishes the first tick, anything at/above
100%, and otherwise only once the fraction has advanced ≥1% since the last published value —
bounding renders to ~100/scan regardless of raw chunk count. Six new regression tests in
`ScanControllerTests.swift`: the throttle policy's logic in isolation (deterministic, no
timing dependency) and an integration test running a real scan through a large,
many-chunk `MockSane` frame. All 112 tests pass; `swift build` zero warnings;
`swiftlint --strict`/`swift-format --strict` clean.

**Re-verified on the real hardware/resolution that broke it** (rebuilt + reinstalled app,
rescanned at 1200dpi):
- CPU during the scan: ~20-23% (was pegged at 100%).
- RSS grew steadily and proportionally to elapsed time (146MB→316MB over ~40s) — real data
  ingestion, not a stuck render loop.
- UI responsiveness checks throughout: consistently ~0.85s round-trip (was 8+ minutes to
  get any response at all).
- Clicked Cancel mid-scan for real: registered immediately, `scanState` returned to idle
  instantly, no banner (correct — cancellation isn't an error), no partial page added.
- A normal scan run immediately afterward completed correctly — "next scan works" confirmed.

## Post-fix re-verification: DocumentCropper rotation/skew correction (commit `ae51418`)

A separate agent root-caused and fixed the `DocumentCropper` bug John found mid-phase
(unconditional perspective correction warping real skewed documents — see Deviations below
for how that was originally discovered and handed off). Once that commit landed on `main`
this agent independently re-verified it against real hardware, not just by trusting the
other agent's own test run:

- Pulled `ae51418`, confirmed locally: `swift build` clean (0 warnings), `swift test` →
  **125 tests pass** (106 baseline + 6 Cell-10-fix + 13 new crop-skew tests), `swiftlint
  --strict`/`swift-format --strict` both clean.
- Rebuilt and reinstalled the app, then re-scanned **the exact real physical item** behind
  the original bug report — still sitting on the bed from John's own repro: a card-terms
  insert (plain rotated text) with a high-contrast "MORE SALT, NOT LESS" sticker at a
  visibly different angle in one corner — via the real GUI, Text/300dpi/Color (the same
  mode/dpi as the original failure).
- Result: `cell9-crop-fix-repro.pdf`, page size 215.9×297.77mm — essentially the full bed,
  confirming the fix's fallback path fired (ambiguous/conflicting skew signals between the
  sticker and the page → falls back to the untouched full bed, per the fix's documented
  behavior) rather than forcing a correction. Rendered the page
  (`cell9-crop-fix-repro-render.png`) and visually compared it against the raw pre-crop bed
  scan (`bed-check2.png`, same session): **identical framing, no warping, no shearing, no
  garbled/wedge-shaped content** — the previous bug's exact failure signature is gone. This
  is the correct, safe outcome for genuinely conflicting skew evidence, not a missed crop.
- Did not additionally re-verify the "clean single dominant peak gets corrected" path
  (e.g. a card at a real 3° skew) against real hardware in this pass — that path is covered
  by the other agent's own new real-hardware-and-synthetic tests
  (`DocumentCropperSkewTests.swift`: a real 15° skew and a 28° skew, both perspective-
  corrected correctly) and re-running it would need placing a new item at a controlled angle,
  which this agent cannot do without hands; the fallback path above is the one directly tied
  to John's original real bug report, and is the one re-verified here on real hardware.

## v1.0.0 release: fresh-install spot-check

Downloaded the actual published release asset (not a local build) and spot-checked matrix
cells 1 and 5 against it:

- `curl`-downloaded `Scanners-1.0.0-arm64.zip` from the GitHub Release; SHA-256 matched the
  release asset's own recorded digest exactly (`4a942fb5...12d2593c`). Unzipped, installed to
  `/Applications`, applied a real quarantine flag (`com.apple.quarantine`, since a CLI
  download doesn't get one the way Finder/Safari would) then cleared it via the README's
  documented `xattr -dr com.apple.quarantine` step, and launched — reproducing the actual
  documented first-run path, not just running an already-trusted binary.
  `codesign`/`Info.plist` confirm `CFBundleShortVersionString=1.0.0`, ad-hoc signature, valid.
- **Cell 1** (Text/300dpi/Black & White): scanned, saved via *Save PDF…*, verified via
  PDFKit — 1 page, 215.9×297.77mm, 382 chars of extractable OCR text. **PASS.**
- **Cell 5** (Image/600dpi/Color, JPEG): scanned, saved via *Save Image…* (accessory popup
  read back "JPEG" before saving, confirming format), verified via `sips` — dpiWidth/Height
  = 600.000 exact, 5030×6979px. **PASS.**

**Anomaly caught and root-caused, not just noted:** both artifacts came out with page content
rotated ~180° from the orientation seen in this same session's crop-fix re-verification scan
(above), with the corner sticker no longer anywhere in frame. Investigated before accepting
the spot-check, rather than assuming it was fine: ran a raw CLI scan
(`scannerkit-cli`, bypassing the app and all of `OutputKit` entirely) — it reproduced the
identical rotated, sticker-less framing. That rules out a software regression (the app and
`DocumentCropper` weren't even in the code path); a pixel-diff of the two raw bed captures
after compensating for a 180° rotation shows they're *not* the same content just flipped
(mean abs grayscale diff ~24.7/255, not ~0) — consistent with the loose, unclipped
card-stock insert having physically shifted position on the glass sometime during this
session's many consecutive scans (lid-close cycles), not a rotation artifact of any kind.
Cells 1/5 pass criteria (mode/dpi/color/format correctness) don't depend on bed content
orientation, so this doesn't affect the PASS verdicts above — flagged here so the rotated
scans in `/tmp/scanners-v1/fresh-install/` aren't mistaken later for a recurrence of the
crop bug.

## Deviations / limitations

- **Multi-page cells (1, 3, 9) reused identical physical content per page.** The agent
  driving this validation has no way to physically turn pages of the sticker album or swap
  documents on the flatbed between scans — that requires human hands. Each "page" in a
  multi-page cell is therefore an independent real scan of the same physical object, not
  visually distinct content. This still genuinely exercises the real multi-scan pipeline
  end-to-end (N separate hardware scan operations, N separate OCR passes, correct page
  count/order/PDF assembly, correct per-scan auto-crop) — what it does *not* prove is
  content-level page distinctness, since there was nothing to distinguish. Flagged
  explicitly rather than silently degraded or glossed over.
- **Cell 11's physical unplug/replug was performed by John**, not the agent, consistent
  with Phase 5's precedent for this same class of action (an agent has no hands). Both
  halves of the check were still genuinely exercised against real hardware state — the
  agent verified the resulting app behavior (banner / recovery), John performed the
  physical action. The literal "click Retry immediately after replug" moment specifically
  wasn't re-captured as one continuous sequence (see Cell 11's row above for the equivalent
  evidence used instead).
- **Cell 12's Archive→TIFF format check relies on unit-test coverage, not a live scan** —
  a deliberate call to avoid another full-bed 2400dpi scan while Cell 8's mechanical finding
  was still under investigation/after John waived that sub-case. The JPEG case (Photo
  preset, 600dpi, no mechanical concern) was verified live.
- **A real anomaly during Cell 8's first attempt, unrelated to the mechanical finding
  above (not a code defect):** during an unrelated long real-world gap in this session, the
  app process that had been running Cell 8's scan disappeared and was replaced by a
  different process instance running an identical binary from a different path. John later
  confirmed this was him closing the app intentionally after that scan had actually
  completed, to free the machine for other work overnight — not a crash. That run's output
  was never saved and was discarded; Cell 8 was independently re-run from scratch (twice —
  see "Cell 8 detail" above) once hardware access resumed.
- **A separate, real correctness bug was found during this phase and fixed by another
  agent, not this report** (this agent did not investigate or modify
  `Sources/OutputKit/DocumentCropper.swift` at any point, per explicit instruction —
  confirmed via `git status`/`git diff` throughout every commit this agent made): John
  reported a scanned document coming out visibly rotated/distorted in `DocumentCropper`'s
  perspective-correction path for a non-axis-aligned real item. Fixed in commit `ae51418`
  and independently re-verified against real hardware by this agent — see "Post-fix
  re-verification" above.
