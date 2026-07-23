import AppKit
import SwiftUI

/// The chrome background (control strip, page strip, Settings pane) — deliberately distinct
/// from the near-white canvas backdrop (`CanvasView`'s `.underPageBackgroundColor`), per
/// DESIGN.md's "understated grey-on-cream, not flat white" chrome.
///
/// Phase 5 tried to get this via `Color(nsColor: .windowBackgroundColor)` alone, reasoning
/// that any semantic (non-hardcoded) system color would automatically track light/dark and
/// read as "soft grey, not white." That held on the dev Mac's built-in display, but real-
/// hardware feedback on a 32" LG LED monitor in light mode showed it reads as flat, painfully
/// bright white — `windowBackgroundColor`'s actual light-mode value is pale enough that a
/// bright/wide-gamut external display renders it visually indistinguishable from `#FFFFFF`,
/// even though it isn't literally that. Being "semantic" isn't the same as being "visibly
/// grey" — the fix needs an explicit, deliberate light-mode tone, not another system default.
///
/// `background` is a dynamic `NSColor` (not a flat `Color`) so it still tracks appearance
/// correctly: light mode gets an explicit warm cream (`#EDEAE0`) with real contrast against
/// white; dark mode defers to the system's own `.windowBackgroundColor` unchanged, since only
/// light mode was reported as a problem and dark mode already looks intentional.
enum ChromeColor {
  static var background: Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard !isDark else { return .windowBackgroundColor }
        return NSColor(srgbRed: 0xED / 255.0, green: 0xEA / 255.0, blue: 0xE0 / 255.0, alpha: 1.0)
      })
  }
}
