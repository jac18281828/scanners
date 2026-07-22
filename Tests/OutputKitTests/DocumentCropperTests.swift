import CoreGraphics
import CoreImage
import Testing

@testable import OutputKit
@testable import ScannerKit

@Suite("DocumentCropper")
struct DocumentCropperTests {
  /// A synthetic "document on a scanner bed" fixture: a full-bed-sized dark background
  /// (standing in for the platen/lid) with a lighter, high-contrast axis-aligned rectangle
  /// inset within it (standing in for the document) -- the same "rendered fixture instead
  /// of a golden file" approach `OCREngineTests`/`Fixtures.textPage` already use for Vision
  /// tests elsewhere in this suite. High contrast and a generous size (not a tiny image)
  /// give `VNDetectDocumentSegmentationRequest` a realistic edge signal to find.
  private static func documentOnBedPage(
    bedWidthPixels: Int = 1200, bedHeightPixels: Int = 1600,
    marginPixels: Int = 150,
    requestedDPI: Int = 300, hardwareDPI: Int = 300
  ) -> ScannedPage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
      data: nil,
      width: bedWidthPixels,
      height: bedHeightPixels,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    // Dark "platen/lid" background.
    context.setFillColor(gray: 0.15, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: bedWidthPixels, height: bedHeightPixels))
    // Bright "document" rect, inset by marginPixels on every side.
    context.setFillColor(gray: 0.95, alpha: 1)
    context.fill(
      CGRect(
        x: marginPixels, y: marginPixels,
        width: bedWidthPixels - marginPixels * 2, height: bedHeightPixels - marginPixels * 2))

    let image = context.makeImage()!
    let widthMM = Double(bedWidthPixels) / Double(hardwareDPI) * 25.4
    let heightMM = Double(bedHeightPixels) / Double(hardwareDPI) * 25.4
    return ScannedPage(
      image: image, widthMM: widthMM, heightMM: heightMM, requestedDPI: requestedDPI,
      hardwareDPI: hardwareDPI, mode: .color)
  }

  /// A perfectly uniform image -- no edges anywhere, nothing for document-segmentation to
  /// find. Stands in for a blank bed / a scan with no real content on it.
  private static func blankBedPage(
    bedWidthPixels: Int = 1200, bedHeightPixels: Int = 1600,
    requestedDPI: Int = 300, hardwareDPI: Int = 300
  ) -> ScannedPage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
      data: nil,
      width: bedWidthPixels,
      height: bedHeightPixels,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0.9, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: bedWidthPixels, height: bedHeightPixels))
    let image = context.makeImage()!
    let widthMM = Double(bedWidthPixels) / Double(hardwareDPI) * 25.4
    let heightMM = Double(bedHeightPixels) / Double(hardwareDPI) * 25.4
    return ScannedPage(
      image: image, widthMM: widthMM, heightMM: heightMM, requestedDPI: requestedDPI,
      hardwareDPI: hardwareDPI, mode: .color)
  }

  /// Same "document on a scanner bed" fixture as `documentOnBedPage`, but the document
  /// rectangle is drawn genuinely rotated (a real skew, like someone placing a page at an
  /// angle) rather than axis-aligned -- for regression-testing that a *real* skew still
  /// gets full perspective correction, not the near-axis-aligned bounding-box snap this
  /// phase added.
  private static func skewedDocumentOnBedPage(
    bedWidthPixels: Int = 1600, bedHeightPixels: Int = 1600,
    documentWidthPixels: Int = 700, documentHeightPixels: Int = 1000,
    rotationDegrees: Double = 20,
    requestedDPI: Int = 300, hardwareDPI: Int = 300
  ) -> ScannedPage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
      data: nil,
      width: bedWidthPixels,
      height: bedHeightPixels,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0.15, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: bedWidthPixels, height: bedHeightPixels))
    context.setFillColor(gray: 0.95, alpha: 1)
    context.saveGState()
    context.translateBy(x: CGFloat(bedWidthPixels) / 2, y: CGFloat(bedHeightPixels) / 2)
    context.rotate(by: rotationDegrees * .pi / 180)
    context.fill(
      CGRect(
        x: -Double(documentWidthPixels) / 2, y: -Double(documentHeightPixels) / 2,
        width: Double(documentWidthPixels), height: Double(documentHeightPixels)))
    context.restoreGState()

    let image = context.makeImage()!
    let widthMM = Double(bedWidthPixels) / Double(hardwareDPI) * 25.4
    let heightMM = Double(bedHeightPixels) / Double(hardwareDPI) * 25.4
    return ScannedPage(
      image: image, widthMM: widthMM, heightMM: heightMM, requestedDPI: requestedDPI,
      hardwareDPI: hardwareDPI, mode: .color)
  }

  @Test(
    "a confidently-detected document is cropped smaller than the full bed, with widthMM/heightMM recomputed proportionally and consistent dpi"
  )
  func detectedDocumentIsCroppedWithCorrectPhysicalSize() throws {
    let page = Self.documentOnBedPage()
    let cropped = DocumentCropper.crop(page)

    // The crop must actually have happened -- not silently fallen back to the full bed.
    #expect(cropped.image.width < page.image.width)
    #expect(cropped.image.height < page.image.height)
    #expect(cropped.widthMM < page.widthMM)
    #expect(cropped.heightMM < page.heightMM)

    // The document rect covers roughly (1200 - 2*150)/1200 = 75% of the bed's width/height
    // -- generous tolerance (detection + perspective correction won't land on the exact
    // pixel), but this is a real regression guard against e.g. cropping to a sliver or
    // barely trimming anything.
    let widthFraction = Double(cropped.image.width) / Double(page.image.width)
    let heightFraction = Double(cropped.image.height) / Double(page.image.height)
    #expect(widthFraction > 0.55 && widthFraction < 0.95, "widthFraction was \(widthFraction)")
    #expect(heightFraction > 0.55 && heightFraction < 0.95, "heightFraction was \(heightFraction)")

    // dpi (pixels-per-mm) must stay the same before and after crop -- widthMM/heightMM are
    // recomputed from the corrected image's own pixel count against hardwareDPI, so this
    // should hold by construction; assert it explicitly since it's the exact property
    // PDFBuilder's true-size-printing depends on post-crop.
    let originalPxPerMM = Double(page.image.width) / page.widthMM
    let croppedPxPerMM = Double(cropped.image.width) / cropped.widthMM
    #expect(abs(originalPxPerMM - croppedPxPerMM) < 0.01)

    // mode/dpi metadata untouched by cropping -- only the image and physical size change.
    #expect(cropped.requestedDPI == page.requestedDPI)
    #expect(cropped.hardwareDPI == page.hardwareDPI)
    #expect(cropped.mode == page.mode)
  }

  @Test("a blank bed with no detectable document boundary falls back to the full, uncropped scan")
  func blankBedFallsBackToFullScan() throws {
    let page = Self.blankBedPage()
    let result = DocumentCropper.crop(page)

    #expect(result.image.width == page.image.width)
    #expect(result.image.height == page.image.height)
    #expect(result.widthMM == page.widthMM)
    #expect(result.heightMM == page.heightMM)
    #expect(result.requestedDPI == page.requestedDPI)
    #expect(result.hardwareDPI == page.hardwareDPI)
    #expect(result.mode == page.mode)
  }

  @Test(
    "a genuinely skewed document (real rotation, not detection noise) still gets full perspective correction"
  )
  func skewedDocumentIsPerspectiveCorrected() throws {
    let page = Self.skewedDocumentOnBedPage()
    let cropped = DocumentCropper.crop(page)

    #expect(cropped.image.width < page.image.width)
    #expect(cropped.image.height < page.image.height)

    // Perspective correction rectifies the rotated quad back to (approximately) the
    // document's own true aspect ratio (700/1000 = 0.7). If the near-axis-aligned
    // bounding-box path had wrongly fired instead of perspective correction, the output
    // would be the (larger, visibly different-ratio) bounding box of a 20-degree-rotated
    // rectangle -- for these dimensions that bbox ratio is close to 0.83, well outside the
    // tolerance below, so this genuinely discriminates between the two code paths.
    let ratio = Double(cropped.image.width) / Double(cropped.image.height)
    #expect(abs(ratio - 0.7) < 0.15, "aspect ratio was \(ratio)")
  }

  @Test(
    "estimatedRotationDegrees averages across all four edges, matching the real-hardware-measured noise case (DESIGN.md decision #9 addendum)"
  )
  func rotationEstimateAveragesRealHardwareNoise() {
    // Pixel corners measured on real HP ScanJet 4570c hardware: a confidently detected
    // (0.99) VNRectangleObservation on a document that is, in fact, physically
    // axis-aligned on the platen. topLeft/bottomLeft (and topRight/bottomRight) share an
    // x-coordinate exactly -- Vision's own internal quantization grid landed both corners
    // on the same column by coincidence -- so left/right edges read exactly vertical
    // (0deg); the asymmetric top (+2.82deg) vs bottom (-0.31deg) readings are the
    // per-corner detection noise this averaging exists to cancel.
    let corners = DocumentCropper.PixelCorners(
      topLeft: CGPoint(x: 11.8056, y: 2253.3984),
      topRight: CGPoint(x: 1688.1945, y: 2335.8398),
      bottomLeft: CGPoint(x: 11.8056, y: 274.8047),
      bottomRight: CGPoint(x: 1688.1945, y: 265.6445)
    )
    let rotation = DocumentCropper.estimatedRotationDegrees(corners)
    #expect(abs(rotation - 0.6256) < 0.01, "rotation was \(rotation)")
    #expect(
      abs(rotation) <= DocumentCropper.maximumNoiseRotationDegrees,
      "real-hardware noise case (\(rotation) deg) must land under the snap-to-bbox threshold"
    )
  }

  @Test("estimatedRotationDegrees reads a genuinely rotated quad well above the noise threshold")
  func rotationEstimateCatchesRealSkew() {
    // All four edges of a truly rotated rectangle agree on the same angle -- unlike the
    // noisy real-hardware case above, there's nothing here for the averaging to cancel.
    let thetaRadians = 15.0 * Double.pi / 180
    let width = 700.0
    let height = 1000.0
    func rotate(_ point: CGPoint) -> CGPoint {
      CGPoint(
        x: point.x * cos(thetaRadians) - point.y * sin(thetaRadians),
        y: point.x * sin(thetaRadians) + point.y * cos(thetaRadians))
    }
    let corners = DocumentCropper.PixelCorners(
      topLeft: rotate(CGPoint(x: 0, y: height)),
      topRight: rotate(CGPoint(x: width, y: height)),
      bottomLeft: rotate(CGPoint(x: 0, y: 0)),
      bottomRight: rotate(CGPoint(x: width, y: 0))
    )
    let rotation = DocumentCropper.estimatedRotationDegrees(corners)
    #expect(abs(rotation - 15.0) < 0.01, "rotation was \(rotation)")
    #expect(abs(rotation) > DocumentCropper.maximumNoiseRotationDegrees)
  }

  @Test(
    "boundingBoxCrop performs an exact, distortion-free crop for a near-axis-aligned jittered quad -- no visible rotation introduced"
  )
  func boundingBoxCropIntroducesNoVisibleRotation() throws {
    // Dark "platen" background with a bright "document" square, same rendering approach
    // as documentOnBedPage above.
    let size = 200
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(gray: 0.95, alpha: 1)
    context.fill(CGRect(x: 40, y: 40, width: 120, height: 120))
    let image = context.makeImage()!

    // A quad with the same asymmetric-edge "noise" signature measured on real hardware
    // (top edge tilted one way, bottom edge tilted the other, left/right exactly
    // vertical) -- not a perfect match to the true 40..<160 square boundary (real
    // detection never is), but close, and within the noise threshold.
    let corners = DocumentCropper.PixelCorners(
      topLeft: CGPoint(x: 40, y: 158),
      topRight: CGPoint(x: 160, y: 161),
      bottomLeft: CGPoint(x: 40, y: 42),
      bottomRight: CGPoint(x: 160, y: 40)
    )
    let rotation = abs(DocumentCropper.estimatedRotationDegrees(corners))
    #expect(
      rotation <= DocumentCropper.maximumNoiseRotationDegrees,
      "test fixture's jitter (\(rotation) deg) must stay under the noise threshold, or this isn't exercising the bbox path"
    )

    let extent = CGRect(x: 0, y: 0, width: size, height: size)
    let cropped = try #require(
      DocumentCropper.boundingBoxCrop(image, corners: corners, imageExtent: extent))

    // Bounding box of those corners: x in [40,160], y in [40,161].
    #expect(cropped.width == 120)
    #expect(cropped.height == 121)

    // A rotation/warp bug would show up as dark wedges cut into the cropped output
    // (CIPerspectiveCorrection remapping background into the frame at the corners where
    // the noisy quad diverges from a true rectangle). A plain bounding-box crop instead
    // stays almost entirely the bright document color -- the only non-document pixels are
    // the sliver of background the 1px-oversized bbox includes past the true square edge.
    let data = cropped.dataProvider!.data! as Data
    let bytesPerRow = cropped.bytesPerRow
    let pixelStride = cropped.bitsPerPixel / 8
    var brightCount = 0
    for row in 0..<cropped.height {
      for col in 0..<cropped.width {
        let value = data[row * bytesPerRow + col * pixelStride]
        if value > 128 { brightCount += 1 }
      }
    }
    let brightFraction = Double(brightCount) / Double(cropped.width * cropped.height)
    #expect(brightFraction > 0.95, "bright fraction was \(brightFraction)")
  }
}
