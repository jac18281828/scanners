import Foundation
import OutputKit
import ScannerKit

/// Save-flow orchestration: builds output bytes via OutputKit, writes them, marks the
/// session saved. Panel presentation lives in `SavePanel` (AppKit, untestable without a
/// display) so the parts worth testing — PDF assembly honoring precomputed OCR, filename
/// suggestion — don't need one.
@MainActor
public enum DocumentExporter {
  public enum ExportError: Error, CustomStringConvertible, Equatable {
    case emptyDocument

    public var description: String {
      switch self {
      case .emptyDocument: return "no pages to save"
      }
    }
  }

  /// Builds the PDF bytes for `session`'s pages in order, using each page's precomputed
  /// background-OCR result when available and falling back to inline OCR for any page whose
  /// background pass hasn't finished or failed (`PDFBuilder.append`'s own `nil` behavior) —
  /// DESIGN.md's Text/PDF flow: "OCR runs per-page in the background between scans so Save
  /// is instant."
  public static func buildPDFData(session: DocumentSession, settings: AppSettings) throws -> Data {
    guard !session.pages.isEmpty else { throw ExportError.emptyDocument }
    let builder = try PDFBuilder()
    let includeOCR = session.documentMode == .text
    for entry in session.pages {
      try builder.append(
        page: entry.page,
        includeOCRTextLayer: includeOCR,
        ocrLanguage: settings.ocrLanguage,
        precomputedOCRLines: entry.ocrLines
      )
    }
    return builder.finish()
  }

  /// The full pre-filled filename (with extension) the save panel opens with —
  /// `FilenameTemplate` against the *real* current contents of `settings.saveFolder`, per
  /// its own documented contract.
  public static func suggestedFilename(ext: String, settings: AppSettings, date: Date = Date())
    -> String
  {
    let existing = existingFilenames(in: settings.saveFolder)
    return
      (try? FilenameTemplate.nextFilename(
        date: date, ext: ext, existingFilenames: existing, prefix: settings.filenamePrefix))
      ?? "\(settings.filenamePrefix)-untitled.\(ext)"
  }

  /// Same as `suggestedFilename`, without the extension — the image save panel updates the
  /// extension live as the user changes the format picker, so it needs a bare base name.
  public static func suggestedBaseName(settings: AppSettings, date: Date = Date()) -> String {
    URL(fileURLWithPath: suggestedFilename(ext: "tmp", settings: settings, date: date))
      .deletingPathExtension()
      .lastPathComponent
  }

  public static func existingFilenames(in folder: URL) -> Set<String> {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    return Set(names)
  }

  /// Presents the PDF save panel, writes the file, marks `session` saved. `nil` means the
  /// user cancelled the panel — not an error.
  @discardableResult
  public static func savePDF(session: DocumentSession, settings: AppSettings) throws -> URL? {
    let suggested = suggestedFilename(ext: "pdf", settings: settings)
    guard
      let url = SavePanel.presentPDFPanel(suggestedName: suggested, directory: settings.saveFolder)
    else { return nil }
    let data = try buildPDFData(session: session, settings: settings)
    try data.write(to: url)
    session.markSaved()
    return url
  }

  /// The page Image-mode Save exports — the most recently scanned page, i.e.
  /// `session.pages.last`, matching `CanvasView`'s own preview fallback
  /// (`session.pages.last?.page.image`) so Save always exports whatever's actually on
  /// screen.
  ///
  /// `.last`, not `.first`: found via manual UI testing (see the phase report's Concerns
  /// section). Switching Text -> Image mid-session, without a ⌘N reset, leaves earlier
  /// Text-mode pages in `session.pages` ahead of the new Image-mode scan — `.first` was
  /// silently exporting that stale first page instead of the one the user just scanned.
  public static func imagePageToExport(session: DocumentSession) -> PageEntry? {
    session.pages.last
  }

  /// Presents the image save panel (format picker included), writes the file, marks
  /// `session` saved. DESIGN.md's Image flow is single-page: "One scan -> Save Image…".
  @discardableResult
  public static func saveImage(session: DocumentSession, settings: AppSettings) throws -> URL? {
    guard let entry = imagePageToExport(session: session) else { throw ExportError.emptyDocument }
    let baseName = suggestedBaseName(settings: settings)
    guard
      let (url, format) = SavePanel.presentImagePanel(
        suggestedBaseName: baseName, directory: settings.saveFolder, defaultFormat: .jpeg)
    else { return nil }
    let data = try format.encode(entry.page)
    try data.write(to: url)
    session.markSaved()
    return url
  }
}
