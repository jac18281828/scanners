import CoreGraphics
import CoreImage
import ScannerKit
import Vision

/// Detects the scanned document's boundary within a full-bed scan and crops to it — DESIGN.md
/// decision #9. A modestly skewed placement is straightened with perspective correction; a
/// near-axis-aligned one is snapped to its bounding box; anything ambiguous or beyond a sane
/// rotation bound is left as the untouched full bed. Pure `ScannedPage`-in/`ScannedPage`-out,
/// no hardware dependency, built on `VNDetectDocumentSegmentationRequest` -- with a
/// Vision-independent fallback (`contentExtentCrop`) for hardware where that model can't find
/// enough page-vs-background contrast to report any confidence at all.
public enum DocumentCropper {
  /// Minimum confidence `VNDetectDocumentSegmentationRequest` must report before its quad is
  /// trusted; below it (or on detection failure / no observation) `crop` falls back to
  /// `contentExtentCrop` rather than the Vision-driven path below. In practice this fallback
  /// fires on every real scan tested on this app's actual hardware (white paper against a
  /// similarly pale platen lid) -- Vision measures 0.0, not just low, since its segmentation
  /// model needs page-vs-background contrast this hardware doesn't reliably provide. 0.6 is a
  /// starting guess, not a tuned threshold; it exists for hardware where Vision *does* work.
  public static let minimumConfidence: Float = 0.6

  /// At or below this estimated rotation (degrees), `crop` snaps the quad to its axis-aligned
  /// bounding box instead of perspective-correcting — DESIGN.md decision #9's rotation-noise
  /// addendum. A physically straight real document came back from Vision with edges at +2.82°
  /// and -0.31° (corner-quantization noise, not skew), averaging 0.63°; 2.0° leaves that a >3x
  /// margin while staying well under a genuine skew. Rejecting jitter (this lower bound) is a
  /// separate concern from capping correction (the upper bound below); both are needed.
  public static let maximumNoiseRotationDegrees: Double = 2.0

  /// Upper bound of the rotation-correction search, degrees from upright — DESIGN.md decision
  /// #9's ±30° addendum. Above this `crop` always falls back to the untouched upright bed,
  /// unconditionally, no matter how confident a fit looks. A scope bound, not a quality
  /// judgement: it rescues *accidental* skew (a few degrees up to ~20–30°), not arbitrary
  /// rotation. Beyond ±30° a careless page is better re-placed and a deliberately steep scan is
  /// left undistorted at its true angle — one rule, no guessing intent. OCR/text-orientation
  /// signals were considered for the ambiguous cases and rejected: they only help Text mode and
  /// duplicate the later Text-mode OCR pass. Stays purely geometric.
  public static let maximumCorrectionDegrees: Double = 30.0

  /// Half-width of `estimateSkew`'s angle sweep, degrees — a few degrees past
  /// `maximumCorrectionDegrees` on purpose so a skew just past the cap lands its profile peak
  /// past 30° where `decide`'s cap check rejects it, rather than piling up at the boundary and
  /// reading as an in-bounds 30° skew.
  static let skewSearchLimitDegrees: Double = 35.0

  /// Angular step of the `estimateSkew` sweep, degrees. 1° keeps the sweep to ~71 passes.
  static let skewSearchStepDegrees: Double = 1.0

  /// Longest edge (pixels) `estimateSkew` downsamples to. Skew is a global, low-frequency
  /// property; 400px preserves it while keeping each per-angle pass cheap.
  static let skewAnalysisMaxDimension: Int = 400

  /// Minimum peak-to-median profile-sharpness ratio for a confident skew — rejects a flat,
  /// structureless landscape. Clean documents measure 170–260; an edgeless region single digits.
  static let minimumSkewContrast: Double = 30.0

  /// Maximum ratio of the strongest *competing* peak (>`peakSeparationDegrees` from the best
  /// angle) to the best peak, for a confident skew. The load-bearing ambiguity gate: a clean
  /// document has one dominant orientation (competitor ≈ 0.01–0.02); a page with a high-contrast
  /// sub-region at a different angle — John's benefits-page sticker — yields two comparable peaks
  /// (competitor ≈ 0.4–0.5) and must fall back to upright.
  static let maximumSecondPeakRatio: Double = 0.25

  /// Angles within this many degrees of the best angle count as its shoulder, not a competitor,
  /// when computing the second-peak ratio.
  static let peakSeparationDegrees: Double = 5.0

  /// How far the profile skew angle may disagree with Vision's quad rotation (degrees) and still
  /// perspective-correct. Defence-in-depth against a quad dragged off the true boundary by a
  /// contrasting sub-region; generous, since genuine documents agree to well under a degree.
  static let skewAgreementToleranceDegrees: Double = 15.0

  /// Downsample ceiling for `contentExtentCrop`'s analysis -- same reasoning as
  /// `skewAnalysisMaxDimension`: extent is a coarse, global property of the content, doesn't
  /// need full resolution, and the result is scaled back up to the source image's own pixels
  /// before cropping.
  static let contentExtentAnalysisMaxDimension: Int = 900

  /// Grayscale cutoff (0...1) below which a downsampled pixel counts as "content" for
  /// `contentExtentCrop` -- deliberately lenient (anything not essentially white), since this
  /// only needs to catch ink/graphics against white paper, not classify exact darkness.
  static let contentDarknessThreshold: Float = 0.7

  /// Minimum connected-component size (pixels, at `contentExtentAnalysisMaxDimension` scale) for
  /// `contentExtentCrop`'s denoise pass to keep it -- rejects isolated JPEG/dust-speck/scan-edge
  /// noise (a `.`) while keeping any real stroke or line (a `—`, which has correlated neighbors)
  /// regardless of how short. Well below the smallest real character component measured against
  /// real scans (13px).
  static let contentDenoiseMinComponentPixels: Int = 5

  /// Maximum short-dimension thickness (pixels, at `contentExtentAnalysisMaxDimension` scale)
  /// for a border-touching component to be dropped as a sliver artifact in `contentExtentCrop`.
  /// Measured against real scans: shadow/artifact fragments came in at 1-4px thick; kept well
  /// under real content's smallest measured dimension so a real photo or graphic near the page
  /// edge is never mistaken for one.
  static let contentExtentSliverMaxThickness: Int = 6

  /// Outward safety margin (mm) added to `contentExtentCrop`'s detected box before cropping --
  /// this fallback has no per-edge confidence signal the way `decide` does, so it errs toward
  /// keeping a visible sliver of background over risking a clipped character at the margin.
  static let contentExtentPaddingMM: Double = 3.0

  /// Detects the document boundary and, if found with at least `minimumConfidence`, crops to
  /// it: within `maximumNoiseRotationDegrees` a bounding-box snap; in the noise..cap band a
  /// confident, unambiguous skew is perspective-corrected (an ambiguous one falls back); beyond
  /// `maximumCorrectionDegrees` always the full upright bed. `widthMM`/`heightMM` are recomputed
  /// from the corrected image's *own* pixels against `page.hardwareDPI` (the `pixels / dpi *
  /// 25.4` relationship used across OutputKit), not from Vision's corners — a skewed quad's
  /// `(maxX - minX) * page.widthMM` would mix each axis's scale incorrectly. Never throws;
  /// `requestedDPI`/`hardwareDPI`/`mode` carry over unchanged.
  public static func crop(_ page: ScannedPage) -> ScannedPage {
    guard let observation = detectDocument(in: page.image),
      observation.confidence >= minimumConfidence
    else {
      return contentExtentCrop(page)
    }

    let extent = CGRect(x: 0, y: 0, width: page.image.width, height: page.image.height)
    let corners = pixelCorners(observation, imageExtent: extent)
    let rotationDegrees = abs(estimatedRotationDegrees(corners))

    // Only the (noise..cap] band needs the projection-profile analysis; the bounding-box and
    // beyond-cap cases resolve from Vision's rotation alone (`decide` ignores the skew estimate
    // there), so a not-confident placeholder is safe.
    let needsSkewAnalysis =
      rotationDegrees > maximumNoiseRotationDegrees
      && rotationDegrees <= maximumCorrectionDegrees
    let skew =
      needsSkewAnalysis
      ? estimateSkew(page.image)
      : SkewEstimate(angleDegrees: rotationDegrees, contrast: 0, secondPeakRatio: 1)

    switch decide(visionRotationDegrees: rotationDegrees, skew: skew) {
    case .fallback:
      return page
    case .boundingBox:
      guard let corrected = boundingBoxCrop(page.image, corners: corners, imageExtent: extent)
      else {
        return page
      }
      return repackaged(page, corrected: corrected) ?? page
    case .perspective:
      guard let corrected = perspectiveCorrect(page.image, corners: corners) else {
        return page
      }
      return repackaged(page, corrected: corrected) ?? page
    }
  }

  /// Rebuilds a `ScannedPage` around a corrected image, recomputing physical size from its own
  /// pixels against `page.hardwareDPI`. Returns `nil` (so `crop` falls back) if degenerate.
  static func repackaged(_ page: ScannedPage, corrected: CGImage) -> ScannedPage? {
    guard corrected.width > 0, corrected.height > 0 else { return nil }
    let croppedWidthMM = Double(corrected.width) / Double(page.hardwareDPI) * 25.4
    let croppedHeightMM = Double(corrected.height) / Double(page.hardwareDPI) * 25.4
    guard croppedWidthMM > 0, croppedHeightMM > 0 else { return nil }
    return ScannedPage(
      image: corrected, widthMM: croppedWidthMM, heightMM: croppedHeightMM,
      requestedDPI: page.requestedDPI, hardwareDPI: page.hardwareDPI, mode: page.mode)
  }

  // MARK: - Decision

  /// What `crop` should do with a detected quad.
  enum CropDecision: Equatable {
    /// Near-axis-aligned: snap to the bounding box, no rotation introduced.
    case boundingBox
    /// A confident, in-bounds, unambiguous skew: perspective-correct to the quad.
    case perspective
    /// Ambiguous, beyond the ±30° cap, or otherwise not safely correctable: full upright bed.
    case fallback
  }

  /// The bounded, confidence-gated decision — the heart of DESIGN.md decision #9's ±30°
  /// addendum, factored out of `crop` so it is unit-testable against exact inputs without live
  /// Vision. Gates in order: within noise → bounding box; beyond the cap → fallback
  /// (unconditional); otherwise correct only on a confident skew within the cap that agrees
  /// with Vision's quad, else fallback. Where John's two examples split: a clean card at 3°
  /// shows one confident peak → perspective; the benefits page's sticker fights its true angle
  /// → no confident peak → fallback to upright.
  static func decide(visionRotationDegrees: Double, skew: SkewEstimate) -> CropDecision {
    let rotation = abs(visionRotationDegrees)
    if rotation <= maximumNoiseRotationDegrees {
      return .boundingBox
    }
    guard rotation <= maximumCorrectionDegrees else {
      return .fallback
    }
    guard skew.confident,
      abs(skew.angleDegrees) <= maximumCorrectionDegrees,
      abs(abs(skew.angleDegrees) - rotation) <= skewAgreementToleranceDegrees
    else {
      return .fallback
    }
    return .perspective
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

  /// The observation's four corners in pixel coordinates. Vision's normalized (0...1,
  /// bottom-left origin) coordinates map directly onto Core Image's own bottom-left-origin
  /// space, so this is a plain per-axis scale, no y-flip. Shared by the rotation estimate,
  /// bounding-box crop, and perspective correction so all three agree on the same points. Not
  /// `private` so tests can drive the geometry with exact pinned corners — including decision
  /// #9's real-hardware noise case — without live Vision output. Still module-internal.
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

  /// Estimates the quad's rotation (degrees), averaged across all four edges rather than any
  /// single one. A real rotated rectangle's edges all agree; detection noise does not. The
  /// real-hardware case (see `maximumNoiseRotationDegrees`) had a top edge at +2.82° and a
  /// bottom at -0.31° from per-corner quantization; averaging cancels that while still
  /// converging on the true angle for a genuine skew, where every edge already agrees.
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

  /// Crops to the quad's axis-aligned bounding box — no rotation, no warp. Used when `decide`
  /// returns `.boundingBox`: no real skew to correct, so perspective-correcting would bake
  /// detection noise in as a fake rotation (the bug this path exists for).
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
    return CIContext().createCGImage(CIImage(cgImage: image), from: cropRect)
  }

  // MARK: - Perspective correction

  /// `CIPerspectiveCorrection` rectifies the quad into a clean axis-aligned image. Only used
  /// for quads `decide` judges as a real, in-bounds, unambiguous skew.
  private static func perspectiveCorrect(_ image: CGImage, corners: PixelCorners) -> CGImage? {
    let ciImage = CIImage(cgImage: image)
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: corners.topLeft), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: corners.topRight), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: corners.bottomLeft), forKey: "inputBottomLeft")
    filter.setValue(CIVector(cgPoint: corners.bottomRight), forKey: "inputBottomRight")
    guard let outputImage = filter.outputImage else { return nil }
    return CIContext().createCGImage(outputImage, from: outputImage.extent)
  }
}
