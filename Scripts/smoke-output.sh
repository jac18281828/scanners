#!/usr/bin/env bash
#
# smoke-output.sh — end-to-end hardware smoke test for OutputKit (Phase 4).
#
# Drives two real scans of whatever's currently on the flatbed (Gray, then Lineart —
# same physical page) through ScannerKit -> OutputKit via outputkit-cli, producing:
#   - a 2-page PDF (page 1 Gray, page 2 Lineart) with an invisible OCR text layer, and
#   - a standalone JPEG export of the Gray page with dpi metadata.
#
# It also prints what Vision recognized on each page, so the Gray-vs-Lineart OCR
# comparison (DESIGN.md flag #4) has a real hardware data point behind it, not just the
# synthetic fixture in OCREngineTests.
#
# Hardware discipline: at most one process may talk to the scanner at a time. This
# script refuses to run if another SANE-ish process already appears to be using it.
#
# Output goes under $TMPDIR (or /tmp), never inside the repo.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${TMPDIR:-/tmp}/scanners-smoke-output"
PDF_PATH="$OUT_DIR/smoke.pdf"
JPEG_PATH="$OUT_DIR/smoke.jpg"
DPI="${SMOKE_OUTPUT_DPI:-300}"

log() { printf '==> %s\n' "$*"; }

log "Checking for other SANE-ish processes (hardware discipline: one at a time)"
other_procs="$(ps aux | grep -iE 'sane-probe|scanimage|saned|sane-find-scanner|scannerkit-cli|outputkit-cli' \
  | grep -v -E 'grep|smoke-output\.sh' || true)"
if [[ -n "$other_procs" ]]; then
  echo "error: another SANE-related process appears to be running; refusing to start a second one:" >&2
  echo "$other_procs" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$PDF_PATH" "$JPEG_PATH"

log "Building outputkit-cli (debug)"
swift build --package-path "$ROOT_DIR" --product outputkit-cli

BIN="$ROOT_DIR/.build/debug/outputkit-cli"

log "Running smoke scan (Gray page 1, Lineart page 2, dpi=$DPI)"
"$BIN" smoke --pdf-out "$PDF_PATH" --jpeg-out "$JPEG_PATH" --dpi "$DPI"

log "Verifying PDF page count via PDFKit (mdls/pdfinfo not required, uses PDFKit through a tiny probe)"
PAGE_COUNT="$(
  /usr/bin/env swift - "$PDF_PATH" <<'EOF'
import Foundation
import PDFKit

let path = CommandLine.arguments[1]
guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
  print("ERROR: could not open PDF")
  exit(1)
}
print(document.pageCount)
for index in 0..<document.pageCount {
  let text = document.page(at: index)?.string ?? ""
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  FileHandle.standardError.write(
    Data("page \(index + 1) extracted text: \(trimmed.prefix(200))\n".utf8))
}
EOF
)"
log "PDF page count: $PAGE_COUNT"
if [[ "$PAGE_COUNT" != "2" ]]; then
  echo "error: expected a 2-page PDF, got $PAGE_COUNT" >&2
  exit 1
fi

log "Checking JPEG dpi metadata with sips"
sips -g dpiWidth -g dpiHeight -g pixelWidth -g pixelHeight "$JPEG_PATH"

log "Smoke test artifacts:"
echo "  PDF:  $PDF_PATH"
echo "  JPEG: $JPEG_PATH"
log "Open the PDF in Preview.app and drag-select over the visible text to confirm it's" \
  "really selectable — this script verifies text is *extractable* (PDFKit .string above)" \
  "but only a human (or a UI-automation pass) can confirm on-screen selection visually."
