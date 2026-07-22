import Foundation
import Observation
import OutputKit
import ScannerKit

/// The in-progress document: scanned pages plus the live mode/dpi/color settings the
/// control strip shows and edits in place (DESIGN.md: "the main window always shows
/// current mode/dpi/color inline, editable in place"). Views stay dumb — everything here is
/// state and state transitions, no SANE/Vision/AppKit calls.
@MainActor
@Observable
public final class DocumentSession {
  public private(set) var pages: [PageEntry] = []

  /// Private(set): changing modes can discard unsaved pages, so every mode change must go
  /// through `requestModeChange`/`requestApplyPreset`'s confirm-or-block gate rather than a
  /// plain property set. (Found by adversarial review: a bare `didSet` here only reset
  /// dpi/color and silently left stale pages from the old mode in `pages`, so a mode switch
  /// mid-session could silently discard/mix scanned work with no warning — the same
  /// "confirm if unsaved pages exist" contract DESIGN.md already specifies for ⌘N.)
  public private(set) var documentMode: DocumentMode
  public var dpi: Int
  public var colorMode: ScanMode
  /// The format `saveImage`'s save panel opens pre-selected to. DESIGN.md: preset chips are
  /// "One click = mode+dpi+color+format applied" — set by `requestApplyPreset`, left
  /// otherwise unchanged by a plain mode toggle (editable in place like everything else).
  public var currentImageFormat: ImageFormat = .jpeg

  /// True once a page has been added/removed/reordered since the last successful save.
  /// `hasUnsavedChanges` is what ⌘N's confirmation gate actually reads (DESIGN.md: "New
  /// Document (⌘N) confirm if unsaved pages exist, then reset session") — and now also what
  /// `requestModeChange`/`requestApplyPreset` read, for the same reason.
  public private(set) var isDirty = false

  public var hasUnsavedChanges: Bool { !pages.isEmpty && isDirty }

  public init(documentMode: DocumentMode = .text) {
    self.documentMode = documentMode
    self.dpi = documentMode.defaultDPI
    self.colorMode = documentMode.defaultColorMode
  }

  private func applyModeDefaults() {
    dpi = documentMode.defaultDPI
    colorMode = documentMode.defaultColorMode
  }

  /// Restores mode/dpi/color from persisted "last used" settings at launch. Unlike
  /// `requestModeChange`, this never confirms or clears pages — it's meant to run exactly
  /// once, on a freshly-constructed session before any scan has happened, so there is
  /// nothing to discard yet.
  public func restoreLastUsed(documentMode: DocumentMode, dpi: Int, colorMode: ScanMode) {
    self.documentMode = documentMode
    self.dpi = dpi
    self.colorMode = colorMode
  }

  /// Changes `documentMode`, confirming first if it would discard unsaved pages — the same
  /// gate ⌘N's New Document already uses. No-op (returns `true`, nothing asked) if
  /// `newMode` is already the current mode. Returns `false` (nothing changed) if the user
  /// declines the confirmation; the caller (a SwiftUI `Binding`'s setter) doesn't need to do
  /// anything special either way — `documentMode` simply reads back whatever it actually is.
  @discardableResult
  public func requestModeChange(
    to newMode: DocumentMode,
    confirmDiscard: () -> Bool = { ConfirmationAlert.confirmDiscardUnsavedChanges() }
  ) -> Bool {
    guard newMode != documentMode else { return true }
    if hasUnsavedChanges {
      guard confirmDiscard() else { return false }
    }
    clearForModeChange()
    documentMode = newMode
    applyModeDefaults()
    return true
  }

  /// One click applies mode+dpi+color+format — DESIGN.md's preset-chip behavior. Confirms
  /// first (same gate as `requestModeChange`) only when the preset actually changes
  /// `documentMode` and doing so would discard unsaved pages; a preset that keeps the
  /// current mode (e.g. switching between two Image presets) never needs to ask, since nothing
  /// mode-incompatible is being discarded.
  @discardableResult
  public func requestApplyPreset(
    _ preset: ScanPreset,
    confirmDiscard: () -> Bool = { ConfirmationAlert.confirmDiscardUnsavedChanges() }
  ) -> Bool {
    let modeChanging = preset.documentMode != documentMode
    if modeChanging, hasUnsavedChanges {
      guard confirmDiscard() else { return false }
    }
    if modeChanging {
      clearForModeChange()
    }
    documentMode = preset.documentMode
    dpi = preset.dpi
    colorMode = preset.colorMode
    currentImageFormat = preset.imageFormat
    return true
  }

  private func clearForModeChange() {
    pages = []
    isDirty = false
  }

  public func currentConfiguration(source: ScanSource, extendLampTimeout: Bool) -> ScanConfiguration
  {
    ScanConfiguration(
      mode: colorMode, requestedDPI: dpi, source: source, extendLampTimeout: extendLampTimeout)
  }

  /// In Text mode, appends (the multipage PDF flow). In Image mode, *replaces* whatever
  /// page is already there instead of appending — DESIGN.md's Image flow is explicitly
  /// single-page ("One scan -> Save Image…"), so there is never more than one Image-mode
  /// page to begin with, and nothing can be silently discarded from a growing list a user
  /// never intended to build (found by adversarial review as the same root cause behind
  /// `requestModeChange`'s fix: without this, repeatedly rescanning in Image mode without
  /// saving silently kept only the most recent scan with no warning, same as a stale mode
  /// switch could). Not gated by `confirmDiscard` the way mode changes are: replacing an
  /// unsaved Image-mode preview by scanning again is the expected "rescan to retry" flow
  /// for a mode that was never meant to accumulate pages, not a mode-mixing surprise.
  @discardableResult
  public func addPage(_ page: ScannedPage) -> PageEntry {
    let entry = PageEntry(page: page, ocrStatus: documentMode == .text ? .pending : .notNeeded)
    if documentMode == .image {
      pages = [entry]
    } else {
      pages.append(entry)
    }
    isDirty = true
    return entry
  }

  public func removePage(id: UUID) {
    pages.removeAll { $0.id == id }
    isDirty = true
  }

  public func movePages(fromOffsets offsets: IndexSet, toOffset destination: Int) {
    pages.move(fromOffsets: offsets, toOffset: destination)
    isDirty = true
  }

  public func setOCRResult(_ lines: [OCRTextLine], for id: UUID) {
    guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
    pages[index].ocrLines = lines
    pages[index].ocrStatus = .done
  }

  public func setOCRFailed(for id: UUID) {
    guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
    pages[index].ocrStatus = .failed
  }

  public func markSaved() {
    isDirty = false
  }

  public func reset() {
    pages = []
    isDirty = false
    applyModeDefaults()
  }
}
