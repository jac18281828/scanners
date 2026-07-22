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

  public var documentMode: DocumentMode {
    didSet {
      guard oldValue != documentMode else { return }
      applyModeDefaults()
    }
  }
  public var dpi: Int
  public var colorMode: ScanMode

  /// True once a page has been added/removed/reordered since the last successful save.
  /// `hasUnsavedChanges` is what ⌘N's confirmation gate actually reads (DESIGN.md: "New
  /// Document (⌘N) confirm if unsaved pages exist, then reset session").
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

  /// One click applies mode+dpi+color — DESIGN.md's preset-chip behavior.
  public func applyPreset(_ preset: ScanPreset) {
    // Order matters: setting documentMode first would otherwise immediately overwrite
    // dpi/colorMode via applyModeDefaults() in the didSet above, discarding the preset's
    // own values.
    documentMode = preset.documentMode
    dpi = preset.dpi
    colorMode = preset.colorMode
  }

  public func currentConfiguration(source: ScanSource, extendLampTimeout: Bool) -> ScanConfiguration
  {
    ScanConfiguration(
      mode: colorMode, requestedDPI: dpi, source: source, extendLampTimeout: extendLampTimeout)
  }

  @discardableResult
  public func addPage(_ page: ScannedPage) -> PageEntry {
    let entry = PageEntry(page: page, ocrStatus: documentMode == .text ? .pending : .notNeeded)
    pages.append(entry)
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
