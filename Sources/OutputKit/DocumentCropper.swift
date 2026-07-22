import CoreGraphics
import CoreImage
import ScannerKit
import Vision

/// Detects the scanned document's boundary within a full-bed scan and crops (with
/// perspective correction to a clean rectangle) to it — DESIGN.md decision #9. A full-bed
/// scan includes the platen/lid background around the actual page; this trims that away so
/// the UI and every exported output shows just the document.
///
/// Pure `ScannedPage`-in/`ScannedPage`-out, no hardware dependency — built on
/// `VNDetectDocumentSegmentationRequest`, the same Vision framework `OCREngine` already
/// uses elsewhere in OutputKit, just a different (purpose-built, lighter) request type.
public enum DocumentCropper {
  /// Minimum confidence `VNDetectDocumentSegmentationRequest` must report before its
  /// detected quadrilateral is trusted. Below this — or on outright detection failure, or
  /// no observation at all (blank bed, low contrast) — `crop` returns the page unchanged.
  /// DESIGN.md is explicit that this must never fail or guess a crop: a low/no-confidence
  /// result always means "keep the full uncropped bed scan," not "try anyway."
  public static let minimumConfidence: Float = 0.6

  /// Detects the document boundary in `page.image` and, if found with at least
  /// `minimumConfidence`, crops and perspective-corrects to it. `widthMM`/`heightMM` are
  /// recomputed from the *corrected output image's own pixel dimensions* against
  /// `page.hardwareDPI` — the same `pixels / dpi * 25.4mm-per-inch` relationship
  /// `PageNormalizer` already relies on elsewhere in OutputKit — rather than from Vision's
  /// normalized corner coordinates directly. That matters: the four corners aren't
  /// necessarily an axis-aligned rectangle (a document can sit skewed on the platen), so a
  /// naive `(maxX - minX) * page.widthMM` mixes each axis's own physical scale incorrectly
  /// once there's any rotation. Deriving physical size from the *already axis-aligned,
  /// already-corrected* output image's pixel count sidesteps that entirely and is exact.
  ///
  /// Never throws — a failure to detect or correct a crop is not a failure to scan.
  /// `requestedDPI`/`hardwareDPI`/`mode` are carried over unchanged (crop changes total
  /// physical size, not pixel density), so every downstream consumer (`PageNormalizer`,
  /// `PDFBuilder`, `ImageExporter`) keeps working from `widthMM`/`heightMM` exactly like it
  /// already does today, with no changes needed on their end.
  public static func crop(_ page: ScannedPage) -> ScannedPage {
    guard let observation = detectDocument(in: page.image),
      observation.confidence >= minimumConfidence
    else {
      return page
    }

    guard let corrected = perspectiveCorrect(page.image, observation: observation),
      corrected.width > 0, corrected.height > 0
    else {
      return page
    }

    let croppedWidthMM = Double(corrected.width) / Double(page.hardwareDPI) * 25.4
    let croppedHeightMM = Double(corrected.height) / Double(page.hardwareDPI) * 25.4
    guard croppedWidthMM > 0, croppedHeightMM > 0 else { return page }

    return ScannedPage(
      image: corrected,
      widthMM: croppedWidthMM,
      heightMM: croppedHeightMM,
      requestedDPI: page.requestedDPI,
      hardwareDPI: page.hardwareDPI,
      mode: page.mode
    )
  }

  // MARK: - Detection

  private static func detectDocument(in image: CGImage) -> VNRectangleObservation? {
    let request = VNDetectDocumentSegmentationRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return nil
    }
    return request.results?.first
  }

  // MARK: - Perspective correction

  /// `CIPerspectiveCorrection` extracts and rectifies the quadrilateral `observation`
  /// describes into a clean axis-aligned image. Vision's normalized corner coordinates
  /// (origin bottom-left, 0...1) map directly onto Core Image's own coordinate space —
  /// also bottom-left-origin — so this is a plain per-axis scale by the image's pixel
  /// extent, no y-flip (same convention `OCRTextLine`'s doc comment already notes for
  /// Vision-into-CoreGraphics/CoreImage mappings elsewhere in OutputKit).
  private static func perspectiveCorrect(
    _ image: CGImage, observation: VNRectangleObservation
  ) -> CGImage? {
    let ciImage = CIImage(cgImage: image)
    let extent = ciImage.extent

    func pixelPoint(_ normalized: CGPoint) -> CGPoint {
      CGPoint(x: normalized.x * extent.width, y: normalized.y * extent.height)
    }

    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: pixelPoint(observation.topLeft)), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: pixelPoint(observation.topRight)), forKey: "inputTopRight")
    filter.setValue(
      CIVector(cgPoint: pixelPoint(observation.bottomLeft)), forKey: "inputBottomLeft")
    filter.setValue(
      CIVector(cgPoint: pixelPoint(observation.bottomRight)), forKey: "inputBottomRight")

    guard let outputImage = filter.outputImage else { return nil }
    let context = CIContext()
    return context.createCGImage(outputImage, from: outputImage.extent)
  }
}
