import CoreGraphics
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
}
