import Foundation
import OutputKit
import ScannerKit

/// Status of a page's background OCR — kicked off right after the scan completes so Save
/// PDF doesn't block on Vision (DESIGN.md's Text/PDF flow: "OCR runs per-page in the
/// background between scans so Save is instant").
public enum OCRStatus: Sendable, Equatable {
  /// Not applicable — Image-mode pages never get an OCR pass.
  case notNeeded
  case pending
  case done
  /// OCR failed; `PDFBuilder.append` falls back to running OCR itself at Save time (no
  /// `precomputedOCRLines`), so a failure here costs the "instant Save" property for this
  /// one page, not correctness.
  case failed
}

/// One scanned page in the current `DocumentSession`, plus its background-OCR result.
///
/// `ScannedPage` is already `@unchecked Sendable` (ScannerKit's own justification: an
/// immutable value once constructed) — safe to carry here across the same Task boundaries.
public struct PageEntry: Identifiable, Sendable {
  public let id: UUID
  public var page: ScannedPage
  public var ocrStatus: OCRStatus
  public var ocrLines: [OCRTextLine]?

  public init(id: UUID = UUID(), page: ScannedPage, ocrStatus: OCRStatus = .notNeeded) {
    self.id = id
    self.page = page
    self.ocrStatus = ocrStatus
    self.ocrLines = nil
  }
}
