import CoreGraphics
import Testing

@testable import OutputKit
@testable import ScannerKit

/// `estimateSkew`/`rotated`'s own behavior in isolation -- sign convention, confidence gate,
/// and (via `contentSkewIsMisreadAsPageSkew`) the reason `contentExtentCrop` no longer calls
/// them: `estimateSkew` measures dominant content orientation, not the physical page boundary,
/// and those aren't the same thing (see `contentExtentCrop`'s doc comment). This suite checks
/// the machinery empirically -- the same way the deleted border-line estimator's claims were
/// checked before it turned out to be reading a scanner bed-frame artifact rather than the page
/// -- rather than trusting `estimateSkew`'s use on the confident-Vision path (which only ever
/// consumes it via `abs()` as a corroboration check against Vision's own quad, never as a
/// standalone applied rotation) to mean its behavior is already known everywhere it's used.
@Suite("DocumentCropper content-extent fallback: skew-based straightening")
struct DocumentCropperFallbackSkewTests {
  private static func grayscaleImage(
    width: Int, height: Int, background: CGFloat, draw: (CGContext) -> Void
  ) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setFillColor(gray: background, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    draw(context)
    return context.makeImage()!
  }

  /// A high-contrast rectangle ("page") rotated by `knownCCWDegrees` about the image's own
  /// center -- the same pivot `rotated` uses, so ground truth and correction share a pivot with
  /// no confound between them.
  private static func tiltedPageImage(width: Int, height: Int, knownCCWDegrees: Double) -> CGImage {
    Self.grayscaleImage(width: width, height: height, background: 0.95) { context in
      context.saveGState()
      context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
      context.rotate(by: CGFloat(knownCCWDegrees * .pi / 180))
      context.setFillColor(gray: 0.1, alpha: 1)
      let rectW = Double(width) * 0.6
      let rectH = Double(height) * 0.7
      context.fill(CGRect(x: -rectW / 2, y: -rectH / 2, width: rectW, height: rectH))
      context.setFillColor(gray: 0.95, alpha: 1)
      let innerW = rectW - 40
      let innerH = rectH - 40
      context.fill(CGRect(x: -innerW / 2, y: -innerH / 2, width: innerW, height: innerH))
      context.restoreGState()
    }
  }

  @Test("a page tilted by a known angle is recovered with the matching sign")
  func recoversKnownTilt() {
    let image = Self.tiltedPageImage(width: 500, height: 700, knownCCWDegrees: 6)
    let skew = DocumentCropper.estimateSkew(image)
    #expect(skew.confident, "expected a confident skew on a clean high-contrast rectangle")
    #expect(
      abs(skew.angleDegrees - (-6)) < 1.0,
      "expected ~-6deg (buffer-space convention), got \(skew.angleDegrees)deg")
  }

  @Test("applying the estimated correction straightens the image, not doubles the tilt")
  func correctionStraightensNotDoubles() throws {
    let image = Self.tiltedPageImage(width: 500, height: 700, knownCCWDegrees: 6)
    let skew = DocumentCropper.estimateSkew(image)
    let corrected = try #require(DocumentCropper.rotated(image, byDegrees: skew.angleDegrees))
    let residual = DocumentCropper.estimateSkew(corrected)
    #expect(
      abs(residual.angleDegrees) < 2.0,
      "expected near-zero residual tilt, got \(residual.angleDegrees)deg")
  }

  @Test("a blank page with no edges is not confident, so no rotation is guessed")
  func blankPageIsNotConfident() {
    let image = Self.grayscaleImage(width: 500, height: 700, background: 0.95) { _ in }
    let skew = DocumentCropper.estimateSkew(image)
    #expect(!skew.confident)
  }

  @Test("contentExtentCrop crops to content but leaves a tilted page's rotation untouched")
  func contentExtentCropDoesNotRotate() {
    let width = 500
    let height = 700
    let hardwareDPI = 300
    let image = Self.tiltedPageImage(width: width, height: height, knownCCWDegrees: 6)
    let page = ScannedPage(
      image: image, widthMM: Double(width) / Double(hardwareDPI) * 25.4,
      heightMM: Double(height) / Double(hardwareDPI) * 25.4, requestedDPI: hardwareDPI,
      hardwareDPI: hardwareDPI, mode: .color)

    let result = DocumentCropper.contentExtentCrop(page)
    #expect(result.image.width < width, "expected a tighter crop than the full canvas")
    // No physical page-edge measurement exists in this fallback (see contentExtentCrop's doc
    // comment) -- estimateSkew's content-orientation read is not trusted to rotate on its own,
    // so a genuinely tilted page stays tilted; only the crop tightens.
    let residual = DocumentCropper.estimateSkew(result.image)
    #expect(
      abs(abs(residual.angleDegrees) - 6) < 2.0,
      "expected the crop to leave the original ~6deg tilt intact, residual was \(residual.angleDegrees)deg"
    )
  }

  @Test(
    "ruled content printed at an angle on an upright page is misread as page skew (known limitation)"
  )
  func contentSkewIsMisreadAsPageSkew() {
    let width = 500
    let height = 700
    // No outer page boundary is drawn at all -- deliberately, since real scans on this
    // hardware already give estimateSkew essentially no page-vs-platen edge signal (that's
    // why Vision's segmentation model fails here too, see minimumConfidence's doc comment).
    // The only edges in this image are ruled lines at a genuine content angle, on a page that
    // is itself perfectly upright. estimateSkew has no independent signal for where the true
    // page boundary is, so it cannot distinguish "the page is rotated" from "the page is
    // straight but its content isn't" -- both look identical to a whole-frame edge-orientation
    // search. This is a real false-positive risk (rotating an already-straight page), not a
    // hypothetical: asserted here so it's measured, not assumed. It's the reason a page-edge
    // signal (immune to interior content orientation) has to gate estimateSkew before it's
    // trusted to correct on its own -- see contentExtentCrop's doc comment.
    let contentDegrees: Double = 5
    let image = Self.grayscaleImage(width: width, height: height, background: 0.95) { context in
      context.saveGState()
      context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
      context.rotate(by: CGFloat(contentDegrees * .pi / 180))
      context.setStrokeColor(gray: 0.1, alpha: 1)
      context.setLineWidth(4)
      let lineHalfWidth = Double(width) * 0.35
      var y = -Double(height) * 0.3
      while y <= Double(height) * 0.3 {
        context.move(to: CGPoint(x: -lineHalfWidth, y: y))
        context.addLine(to: CGPoint(x: lineHalfWidth, y: y))
        context.strokePath()
        y += 40
      }
      context.restoreGState()
    }

    let skew = DocumentCropper.estimateSkew(image)
    #expect(
      skew.confident,
      "documenting the false positive: ruled content at a clean angle currently reads as a confident skew even though the page itself is upright"
    )
    #expect(
      abs(abs(skew.angleDegrees) - contentDegrees) < 1.0,
      "expected the content's own angle to be recovered as if it were page skew, got \(skew.angleDegrees)deg"
    )
  }

  @Test("contentExtentCrop leaves an unresolvable page unrotated rather than guess")
  func contentExtentCropLeavesAmbiguousPageAlone() {
    let width = 500
    let height = 700
    let hardwareDPI = 300
    // Two comparably-strong rectangles at different angles -- the same "competing sub-region"
    // shape maximumSecondPeakRatio exists to reject on the confident-Vision path, exercised here
    // against the fallback path instead.
    let image = Self.grayscaleImage(width: width, height: height, background: 0.95) { context in
      func drawRect(
        degrees: Double, cx: Double, cy: Double, rectWidth: Double, rectHeight: Double
      ) {
        context.saveGState()
        context.translateBy(x: CGFloat(cx), y: CGFloat(cy))
        context.rotate(by: CGFloat(degrees * .pi / 180))
        context.setFillColor(gray: 0.1, alpha: 1)
        context.fill(
          CGRect(x: -rectWidth / 2, y: -rectHeight / 2, width: rectWidth, height: rectHeight))
        context.setFillColor(gray: 0.95, alpha: 1)
        context.fill(
          CGRect(
            x: -rectWidth / 2 + 15, y: -rectHeight / 2 + 15, width: rectWidth - 30,
            height: rectHeight - 30))
        context.restoreGState()
      }
      drawRect(
        degrees: 8, cx: Double(width) * 0.3, cy: Double(height) * 0.7, rectWidth: 180,
        rectHeight: 240)
      drawRect(
        degrees: -8, cx: Double(width) * 0.7, cy: Double(height) * 0.3, rectWidth: 180,
        rectHeight: 240)
    }
    let page = ScannedPage(
      image: image, widthMM: Double(width) / Double(hardwareDPI) * 25.4,
      heightMM: Double(height) / Double(hardwareDPI) * 25.4, requestedDPI: hardwareDPI,
      hardwareDPI: hardwareDPI, mode: .color)

    let skew = DocumentCropper.estimateSkew(image)
    #expect(!skew.confident, "expected competing sub-regions to defeat confidence")
    let result = DocumentCropper.contentExtentCrop(page)
    // Not straightened -- but still cropped to content, same as any other confident-extent case.
    #expect(result.image.width < width)
  }
}
