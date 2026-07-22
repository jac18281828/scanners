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
  ///
  /// 0.6 is a reasonable starting guess, not a measured threshold — it hasn't been tuned
  /// against a corpus of real `VNDetectDocumentSegmentationRequest` confidence scores
  /// across varied real documents/lighting/platen conditions (this phase validated the
  /// crop-and-recompute path and the no-detection fallback path each work correctly, on
  /// synthetic fixtures and one real hardware document, but that's one data point, not a
  /// calibration study). Revisit if real-world use shows it's too eager (crops when it
  /// shouldn't) or too conservative (skips crops a human would call obvious).
  public static let minimumConfidence: Float = 0.6

  /// Above this estimated rotation (degrees), `crop` treats the detected quad as a real,
  /// meaningfully skewed document and runs full `CIPerspectiveCorrection`. At or below it,
  /// the quad is snapped to its axis-aligned bounding box instead — see
  /// `estimatedRotationDegrees` for why "small angle" is measured as the *average* of all
  /// four edges' implied rotation rather than any single edge, and DESIGN.md decision #9's
  /// addendum for the real-hardware measurement this was calibrated against: a confidently
  /// detected (0.99), physically axis-aligned real document came back from
  /// `VNDetectDocumentSegmentationRequest` with a top edge reading 2.82° and a bottom edge
  /// reading -0.31° (corners quantized to a coarse internal grid, not a truly rotated
  /// rectangle) — averaged across all four edges that's 0.63°. 2.0° leaves that a comfortable
  /// >3x margin while still well under the tens-of-degrees range a genuinely, visibly skewed
  /// document produces.
  public static let maximumNoiseRotationDegrees: Double = 2.0

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

    let extent = CGRect(x: 0, y: 0, width: page.image.width, height: page.image.height)
    let corners = pixelCorners(observation, imageExtent: extent)
    let rotationDegrees = abs(estimatedRotationDegrees(corners))

    // A meaningfully skewed document (someone placed the page at a real angle) gets full
    // perspective correction, same as before. A near-axis-aligned quad — the common real-
    // hardware case, see `maximumNoiseRotationDegrees` — is snapped to a plain bounding-box
    // crop instead: there's no real rotation to correct, so don't introduce one.
    let corrected: CGImage? =
      rotationDegrees <= maximumNoiseRotationDegrees
      ? boundingBoxCrop(page.image, corners: corners, imageExtent: extent)
      : perspectiveCorrect(page.image, corners: corners)

    guard let corrected, corrected.width > 0, corrected.height > 0 else {
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

  // MARK: - Quad geometry

  /// The observation's four corners, converted once from Vision's normalized (0...1,
  /// origin bottom-left) coordinates into pixel coordinates in `imageExtent`'s space.
  /// Vision's normalized corner coordinates map directly onto Core Image's own coordinate
  /// space — also bottom-left-origin — so this is a plain per-axis scale, no y-flip (same
  /// convention `OCRTextLine`'s doc comment already notes for Vision-into-
  /// CoreGraphics/CoreImage mappings elsewhere in OutputKit). Shared by the rotation
  /// estimate, the bounding-box crop, and the perspective-correction path so all three
  /// agree on exactly the same four points.
  ///
  /// Not `private`: `estimatedRotationDegrees`/`boundingBoxCrop` below take this directly
  /// (rather than a `VNRectangleObservation` + extent) specifically so
  /// `DocumentCropperTests` can drive them with exact, pinned corner coordinates —
  /// including the real-hardware-measured noise case from DESIGN.md decision #9's addendum
  /// — without depending on live `VNDetectDocumentSegmentationRequest` output, which is
  /// real-hardware/model-version dependent and not a source of deterministic test input.
  /// Still module-internal, not part of `DocumentCropper`'s public API.
  struct PixelCorners {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
  }

  private static func pixelCorners(
    _ observation: VNRectangleObservation, imageExtent: CGRect
  ) -> PixelCorners {
    func pixelPoint(_ normalized: CGPoint) -> CGPoint {
      CGPoint(x: normalized.x * imageExtent.width, y: normalized.y * imageExtent.height)
    }
    return PixelCorners(
      topLeft: pixelPoint(observation.topLeft),
      topRight: pixelPoint(observation.topRight),
      bottomLeft: pixelPoint(observation.bottomLeft),
      bottomRight: pixelPoint(observation.bottomRight)
    )
  }

  /// Estimates the quad's rotation in degrees from horizontal/vertical, averaged across
  /// all four edges rather than read off any single edge.
  ///
  /// That averaging is the load-bearing part. A *real* rotated rectangle has parallel top
  /// and bottom edges (and parallel left/right edges) — all four edges agree on the same
  /// rotation angle. Detection noise doesn't respect that: real-hardware measurement (see
  /// `maximumNoiseRotationDegrees`) found a confidently-detected quad on a physically
  /// axis-aligned document with a top edge at +2.82° and a bottom edge at -0.31° — two
  /// corners landed a few pixels off, on what turned out to be Vision's own coarse internal
  /// quantization grid, and that alone reads as "2.8° of rotation" if you only look at the
  /// top edge. Averaging all four edges cancels exactly that kind of per-corner noise while
  /// still converging on the true angle for a genuinely rotated document, where every edge
  /// already agrees.
  static func estimatedRotationDegrees(_ corners: PixelCorners) -> Double {
    func angle(_ from: CGPoint, _ to: CGPoint) -> Double {
      Double(atan2(to.y - from.y, to.x - from.x)) * 180 / .pi
    }
    let top = angle(corners.topLeft, corners.topRight)
    let bottom = angle(corners.bottomLeft, corners.bottomRight)
    let left = angle(corners.bottomLeft, corners.topLeft) - 90
    let right = angle(corners.bottomRight, corners.topRight) - 90
    return (top + bottom + left + right) / 4
  }

  // MARK: - Bounding-box crop

  /// Crops to the quad's axis-aligned bounding box — no rotation, no perspective warp.
  /// Used instead of `perspectiveCorrect` when `estimatedRotationDegrees` says the quad is
  /// within noise of axis-aligned: there's no real skew to correct, so cropping tighter
  /// than the bounding box would risk clipping the document, and perspective-correcting
  /// would bake detection noise in as a fake rotation (the bug this fallback exists for).
  static func boundingBoxCrop(
    _ image: CGImage, corners: PixelCorners, imageExtent: CGRect
  ) -> CGImage? {
    let xs = [corners.topLeft.x, corners.topRight.x, corners.bottomLeft.x, corners.bottomRight.x]
    let ys = [corners.topLeft.y, corners.topRight.y, corners.bottomLeft.y, corners.bottomRight.y]
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
    else {
      return nil
    }
    let cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
      .intersection(imageExtent)
    guard !cropRect.isEmpty else { return nil }

    let ciImage = CIImage(cgImage: image)
    let context = CIContext()
    return context.createCGImage(ciImage, from: cropRect)
  }

  // MARK: - Perspective correction

  /// `CIPerspectiveCorrection` extracts and rectifies the quadrilateral `corners`
  /// describes into a clean axis-aligned image. Only used for quads
  /// `estimatedRotationDegrees` judges as a real, meaningfully skewed document — see
  /// `boundingBoxCrop` for the near-axis-aligned case.
  private static func perspectiveCorrect(_ image: CGImage, corners: PixelCorners) -> CGImage? {
    let ciImage = CIImage(cgImage: image)

    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: corners.topLeft), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: corners.topRight), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: corners.bottomLeft), forKey: "inputBottomLeft")
    filter.setValue(CIVector(cgPoint: corners.bottomRight), forKey: "inputBottomRight")

    guard let outputImage = filter.outputImage else { return nil }
    let context = CIContext()
    return context.createCGImage(outputImage, from: outputImage.extent)
  }
}
