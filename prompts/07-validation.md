# Phase 7 — Hardware validation matrix and v1.0.0

You are implementing Phase 7 of the Scanners project. Read `DESIGN.md` first. Repo:
`/Users/john/src/scanners`. v0.1.0 is released and installed. This phase is validation
and polish — find and fix papercuts, then ship v1.0.0.

## Validation matrix (run in the installed app, real hardware)

Execute and record every cell in `Docs/validation-v1.md` (pass/fail + artifact path under
`/tmp/scanners-v1/`):

| # | Mode | DPI | Color | Output | Checks |
|---|------|-----|-------|--------|--------|
| 1 | Text | 300 | B&W | 3-page PDF | page order, searchable text, <600KB, true A4 print size |
| 2 | Text | 75 | B&W | 1-page PDF | downscale correct (~637px wide), still searchable |
| 3 | Text | 150 | Color | 2-page PDF | color pages, OCR present |
| 4 | Text | 600 | B&W | 1-page PDF | crisp, size sane |
| 5 | Image | 600 | Color | JPEG | dpi metadata 600, quality good |
| 6 | Image | 300 | B&W | PNG | 1-bit content correct |
| 7 | Image | 1200 | Color | TIFF | dimensions match dpi |
| 8 | Image | 2400 | Color | JPEG | completes (slow is OK), no memory blowup — watch RSS |
| 9 | — | — | — | — | New Document mid-session: scan doc A (2pp PDF), ⌘N, doc B (JPEG), both saved correctly |
| 10 | — | — | — | — | cancel mid-scan at 1200dpi → clean recovery, next scan works |
| 11 | — | — | — | — | launch with scanner unplugged → banner; plug in → Retry finds it |
| 12 | — | — | — | — | preset chips: each built-in applies correct settings; user preset round-trip |
| 13 | — | — | — | — | app relaunch: last-used settings restored |

## Tasks

1. Run the matrix. Fix every failure at its root (ScannerKit/OutputKit/App — with a
   regression test where the bug was logic, not hardware). Re-run affected cells.
2. Sweep TODOs/warnings; `swift build` must be warning-free.
3. README final pass: verify every command and step by executing it.
4. Update version, tag `v1.0.0`, confirm release workflow green, fresh-install the
   released artifact, spot-check matrix cells 1 and 5 on it.

## Acceptance gates

- All 13 cells pass, recorded in `Docs/validation-v1.md` (committed).
- CI green, zero build warnings, v1.0.0 release public with artifact.
- Fresh-install spot-check passes.

## Escalation

A failure whose fix requires a design change (e.g. 2400dpi memory forces streaming/tiled
decode): implement if contained; if it ripples across module APIs, stop and report with
the measured evidence.
