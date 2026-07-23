import CoreGraphics
import CoreImage
import Testing

@testable import OutputKit
@testable import ScannerKit

/// Bounded, confidence-gated skew correction — DESIGN.md decision #9's ±30° addendum. Split
/// into its own file from `DocumentCropperTests` to stay under the per-file/per-type length
/// caps; self-contained fixtures so it depends on nothing in the other file.
@Suite("DocumentCropper skew correction")
struct DocumentCropperSkewTests {
  /// A clean bright "document" rectangle on a dark "platen", rendered genuinely rotated by
  /// `rotationDegrees` — a real skew, not detection noise.
  private static func cleanSkewedPage(
    rotationDegrees: Double,
    bedPixels: Int = 1600, documentWidthPixels: Int = 700, documentHeightPixels: Int = 1000,
    hardwareDPI: Int = 300
  ) -> ScannedPage {
    let context = CGContext(
      data: nil, width: bedPixels, height: bedPixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0.15, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: bedPixels, height: bedPixels))
    context.setFillColor(gray: 0.95, alpha: 1)
    context.saveGState()
    context.translateBy(x: CGFloat(bedPixels) / 2, y: CGFloat(bedPixels) / 2)
    context.rotate(by: rotationDegrees * .pi / 180)
    context.fill(
      CGRect(
        x: -Double(documentWidthPixels) / 2, y: -Double(documentHeightPixels) / 2,
        width: Double(documentWidthPixels), height: Double(documentHeightPixels)))
    context.restoreGState()
    let image = context.makeImage()!
    let dim = Double(bedPixels) / Double(hardwareDPI) * 25.4
    return ScannedPage(
      image: image, widthMM: dim, heightMM: dim, requestedDPI: hardwareDPI,
      hardwareDPI: hardwareDPI, mode: .color)
  }

  /// A benefits-page analog: a page rotated `pageDegrees` with faint horizontal "text"
  /// stripes, PLUS a bold high-contrast striped "sticker" block at a *different* angle
  /// (`stickerDegrees`) in one corner — the geometry of John's American Express insert, where
  /// the "MORE SALT, NOT LESS" sticker's strong edges run at a different angle than the page.
  /// The two competing orientations give the projection sweep two comparable peaks (no single
  /// confident skew), the ambiguity that must fall back to upright rather than force a wrong
  /// rotation.
  private static func conflictingContentPage(
    pageDegrees: Double, stickerDegrees: Double, bedPixels: Int = 1600, hardwareDPI: Int = 300
  ) -> ScannedPage {
    let context = CGContext(
      data: nil, width: bedPixels, height: bedPixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0.82, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: bedPixels, height: bedPixels))
    let docW = 900
    let docH = 1200
    context.saveGState()
    context.translateBy(x: CGFloat(bedPixels) / 2, y: CGFloat(bedPixels) / 2)
    context.rotate(by: pageDegrees * .pi / 180)
    context.setFillColor(gray: 0.97, alpha: 1)
    context.fill(CGRect(x: -docW / 2, y: -docH / 2, width: docW, height: docH))
    context.setFillColor(gray: 0.45, alpha: 1)  // faint page text
    var ty = -docH / 2 + 120
    while ty < docH / 2 - 120 {
      context.fill(CGRect(x: -docW / 2 + 80, y: ty, width: docW - 160, height: 14))
      ty += 60
    }
    context.restoreGState()
    context.saveGState()  // bold high-contrast striped "sticker" at its own angle
    context.translateBy(x: CGFloat(bedPixels) / 2 - 480, y: CGFloat(bedPixels) / 2 + 380)
    context.rotate(by: stickerDegrees * .pi / 180)
    context.setFillColor(gray: 0.02, alpha: 1)
    context.fill(CGRect(x: -220, y: -220, width: 440, height: 440))
    context.setFillColor(gray: 0.98, alpha: 1)
    var sy = -180
    while sy < 180 {
      context.fill(CGRect(x: -180, y: sy, width: 360, height: 34))
      sy += 70
    }
    context.restoreGState()
    let image = context.makeImage()!
    let dim = Double(bedPixels) / Double(hardwareDPI) * 25.4
    return ScannedPage(
      image: image, widthMM: dim, heightMM: dim, requestedDPI: hardwareDPI,
      hardwareDPI: hardwareDPI, mode: .color)
  }

  // MARK: - estimateSkew (deterministic, no Vision)

  @Test("estimateSkew: confident, in-bounds peak for a clean 15° skew")
  func confidentWithinRange() {
    let skew = DocumentCropper.estimateSkew(Self.cleanSkewedPage(rotationDegrees: 15).image)
    #expect(skew.confident, "contrast \(skew.contrast), 2nd \(skew.secondPeakRatio)")
    #expect(abs(abs(skew.angleDegrees) - 15) < 2.5, "angle \(skew.angleDegrees)")
    #expect(abs(skew.angleDegrees) <= DocumentCropper.maximumCorrectionDegrees)
  }

  @Test("estimateSkew: confident peak for a clean 28° skew (just under the cap)")
  func confidentJustUnderCap() {
    let skew = DocumentCropper.estimateSkew(Self.cleanSkewedPage(rotationDegrees: 28).image)
    #expect(skew.confident, "contrast \(skew.contrast), 2nd \(skew.secondPeakRatio)")
    #expect(abs(abs(skew.angleDegrees) - 28) < 2.5, "angle \(skew.angleDegrees)")
    #expect(abs(skew.angleDegrees) <= DocumentCropper.maximumCorrectionDegrees)
  }

  @Test("estimateSkew: NOT confident for conflicting content (sticker fights the page angle)")
  func ambiguousOnConflictingContent() {
    let skew = DocumentCropper.estimateSkew(
      Self.conflictingContentPage(pageDegrees: 22, stickerDegrees: 0).image)
    #expect(!skew.confident, "should be ambiguous: 2nd \(skew.secondPeakRatio)")
    #expect(
      skew.secondPeakRatio > DocumentCropper.maximumSecondPeakRatio,
      "second-peak ratio \(skew.secondPeakRatio) should exceed the ambiguity threshold")
  }

  @Test("estimateSkew: NOT confident for a document skewed well beyond the ±30° cap")
  func notConfidentBeyondCap() {
    // A 45° rectangle's true edge orientations (±45°) both sit outside the ±35° sweep, so no
    // in-window angle aligns cleanly — a flat, multi-peak landscape, which is not-confident.
    let skew = DocumentCropper.estimateSkew(Self.cleanSkewedPage(rotationDegrees: 45).image)
    #expect(!skew.confident, "contrast \(skew.contrast), 2nd \(skew.secondPeakRatio)")
  }

  // MARK: - decide (pure logic, no Vision)

  @Test("decide: within-noise rotation snaps to the bounding box regardless of skew")
  func decideBoundingBoxWithinNoise() {
    let any = DocumentCropper.SkewEstimate(angleDegrees: 0, contrast: 0, secondPeakRatio: 1)
    #expect(DocumentCropper.decide(visionRotationDegrees: 1.0, skew: any) == .boundingBox)
    #expect(DocumentCropper.decide(visionRotationDegrees: -1.5, skew: any) == .boundingBox)
  }

  @Test("decide: confident, in-bounds skew that agrees with Vision is perspective-corrected")
  func decidePerspectiveInBounds() {
    let s15 = DocumentCropper.SkewEstimate(angleDegrees: -15, contrast: 180, secondPeakRatio: 0.02)
    #expect(DocumentCropper.decide(visionRotationDegrees: 15, skew: s15) == .perspective)
    let s28 = DocumentCropper.SkewEstimate(angleDegrees: -28, contrast: 250, secondPeakRatio: 0.01)
    #expect(DocumentCropper.decide(visionRotationDegrees: 28, skew: s28) == .perspective)
  }

  @Test("decide: beyond the ±30° cap always falls back, even when the skew looks confident")
  func decideFallbackBeyondCap() {
    let est = DocumentCropper.SkewEstimate(angleDegrees: -35, contrast: 260, secondPeakRatio: 0.01)
    #expect(DocumentCropper.decide(visionRotationDegrees: 35, skew: est) == .fallback)
    #expect(DocumentCropper.decide(visionRotationDegrees: 42, skew: est) == .fallback)
  }

  @Test("decide: an ambiguous (not-confident) in-bounds skew falls back")
  func decideFallbackWhenAmbiguous() {
    let est = DocumentCropper.SkewEstimate(angleDegrees: -22, contrast: 120, secondPeakRatio: 0.53)
    #expect(DocumentCropper.decide(visionRotationDegrees: 18, skew: est) == .fallback)
  }

  @Test("decide: falls back when content skew and Vision's quad rotation grossly disagree")
  func decideFallbackWhenSkewDisagreesWithVision() {
    // Content confidently at 25°, Vision's quad reads 5° — the quad has been dragged off the
    // true boundary; perspective-correcting to it would warp. Fall back.
    let est = DocumentCropper.SkewEstimate(angleDegrees: -25, contrast: 200, secondPeakRatio: 0.02)
    #expect(DocumentCropper.decide(visionRotationDegrees: 5, skew: est) == .fallback)
  }

  // MARK: - crop end-to-end (integration, uses Vision)

  @Test("crop: a clean document at a real 15° skew is perspective-corrected")
  func cleanSkewWithinRangeIsCorrected() throws {
    let page = Self.cleanSkewedPage(rotationDegrees: 15)
    let cropped = DocumentCropper.crop(page)
    #expect(cropped.image.width < page.image.width)
    #expect(cropped.image.height < page.image.height)
    // Perspective correction rectifies the rotated quad toward the document's true aspect
    // ratio (700/1000 = 0.7); a 15°-rotated bounding box would be materially squarer, so this
    // discriminates the correction path from a bounding-box snap.
    let ratio = Double(cropped.image.width) / Double(cropped.image.height)
    #expect(abs(ratio - 0.7) < 0.15, "aspect ratio \(ratio)")
  }

  @Test("crop: a clean document at 28° (just under the cap) is still perspective-corrected")
  func cleanSkewJustUnderCapIsCorrected() throws {
    let page = Self.cleanSkewedPage(rotationDegrees: 28)
    let cropped = DocumentCropper.crop(page)
    #expect(cropped.image.width < page.image.width)
    #expect(cropped.image.height < page.image.height)
    let ratio = Double(cropped.image.width) / Double(cropped.image.height)
    #expect(abs(ratio - 0.7) < 0.2, "aspect ratio \(ratio)")
  }

  @Test("crop: a document skewed beyond the ±30° cap falls back to the full untouched bed")
  func skewBeyondCapFallsBackToFullBed() throws {
    // 35° is past the cap but still confidently *detected* by Vision (~0.95 on this hardware),
    // so this exercises the cap rule, not merely a low-confidence skip: detection succeeds,
    // correction is declined.
    let page = Self.cleanSkewedPage(rotationDegrees: 35)
    let result = DocumentCropper.crop(page)
    #expect(result.image.width == page.image.width, "expected full-bed fallback")
    #expect(result.image.height == page.image.height, "expected full-bed fallback")
    #expect(result.widthMM == page.widthMM)
    #expect(result.heightMM == page.heightMM)
  }

  @Test("crop: conflicting content falls back to upright, not a forced (warped) rotation")
  func conflictingContentFallsBackToUpright() throws {
    // The correct behaviour for John's benefits page: leave the full bed untouched rather than
    // bake in the wrong warped rotation the pre-fix code produced.
    let page = Self.conflictingContentPage(pageDegrees: 22, stickerDegrees: 0)
    let result = DocumentCropper.crop(page)
    #expect(result.image.width == page.image.width, "expected full-bed fallback, got a crop")
    #expect(result.image.height == page.image.height, "expected full-bed fallback, got a crop")
    #expect(result.widthMM == page.widthMM)
    #expect(result.heightMM == page.heightMM)
  }
}
