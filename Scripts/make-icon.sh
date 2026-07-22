#!/usr/bin/env bash
# Generates build/Scanners.iconset/*.png and build/Scanners.icns from an SF Symbol
# ("scanner") rendered flat-white on a solid rounded-square background — no clip-art,
# no external assets. Regenerated on every make-app.sh run; nothing here is tracked in
# git (build/ is gitignored-equivalent output).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
ICONSET_DIR="$BUILD_DIR/Scanners.iconset"
ICNS_OUT="$BUILD_DIR/Scanners.icns"

mkdir -p "$ICONSET_DIR"
rm -f "$ICONSET_DIR"/*.png

RENDER_SWIFT="$BUILD_DIR/.render-icon.swift"
mkdir -p "$BUILD_DIR"
cat >"$RENDER_SWIFT" <<'SWIFT'
import AppKit
import Foundation

// Flat, single-glyph app icon: solid rounded-square background (Apple's ~22.37%
// continuous-corner proportion), SF Symbol "scanner" centered in white. No photographic
// or clip-art elements, matches DESIGN.md's "simple, flat" instruction.
func makeIcon(size: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: size, height: size)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  let rect = NSRect(x: 0, y: 0, width: size, height: size)
  let radius = size * 0.2237
  let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
  let top = NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.83, alpha: 1.0)
  let bottom = NSColor(calibratedRed: 0.11, green: 0.30, blue: 0.62, alpha: 1.0)
  let gradient = NSGradient(starting: top, ending: bottom)!
  gradient.draw(in: bgPath, angle: -90)

  let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .medium)
  guard
    let symbol = NSImage(systemSymbolName: "scanner", accessibilityDescription: nil)?
      .withSymbolConfiguration(symbolConfig)
  else {
    fatalError("SF Symbol 'scanner' unavailable")
  }
  let tinted = symbol.copy() as! NSImage
  tinted.isTemplate = false
  tinted.lockFocus()
  NSColor.white.set()
  NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
  tinted.unlockFocus()

  let symSize = tinted.size
  let scale = min(size * 0.62 / symSize.width, size * 0.62 / symSize.height)
  let drawSize = NSSize(width: symSize.width * scale, height: symSize.height * scale)
  let origin = NSPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)
  tinted.draw(
    in: NSRect(origin: origin, size: drawSize), from: .zero, operation: .sourceOver,
    fraction: 1.0)

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let sizes: [(name: String, px: CGFloat)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32),
  ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let outDir = CommandLine.arguments[1]
for (name, px) in sizes {
  let rep = makeIcon(size: px)
  guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed for \(name)")
  }
  let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
  try data.write(to: url)
}
print("wrote \(sizes.count) icon images to \(outDir)")
SWIFT

swift "$RENDER_SWIFT" "$ICONSET_DIR"
rm -f "$RENDER_SWIFT"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUT"
echo "Scripts/make-icon.sh: wrote $ICNS_OUT"
