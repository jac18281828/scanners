import CoreGraphics
import Testing

@testable import OutputKit
@testable import ScannerKit

/// `contentExtentCrop` -- the Vision-independent fallback for when `VNDetectDocumentSegmentationRequest`
/// can't find enough page-vs-platen contrast to report any confidence (measured 0.0, not just
/// low, against every real scan tested on this app's actual hardware). Fixtures stay at or
/// under `contentExtentAnalysisMaxDimension` so there's no downsampling to account for,
/// matching the deterministic-pixel-math approach the rest of this suite already uses for
/// `decide`/`boundingBoxCrop`.
@Suite("DocumentCropper content-extent fallback")
struct DocumentCropperContentExtentTests {
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

  @Test("a real content block, no border artifacts, is found tightly and correctly")
  func plainContentBlockIsFoundTightly() throws {
    let width = 300
    let height = 400
    let image = Self.grayscaleImage(width: width, height: height, background: 0.95) { context in
      context.setFillColor(gray: 0.1, alpha: 1)
      context.fill(CGRect(x: 50, y: 60, width: 150, height: 200))
    }
    let box = try #require(DocumentCropper.contentExtentBox(image))
    #expect(abs(box.minX - 50) < 2)
    #expect(abs(box.maxX - 200) < 2)
    // CGImage/CoreImage's bottom-left-origin space: content drawn at CG y in [60, 260).
    #expect(abs(box.minY - 60) < 2)
    #expect(abs(box.maxY - 260) < 2)
  }

  @Test("a thin sliver hugging the border (shadow/scan-edge artifact) does not inflate the box")
  func borderSliverIsExcluded() throws {
    let width = 300
    let height = 400
    let image = Self.grayscaleImage(width: width, height: height, background: 0.95) { context in
      // Real content well inside the frame.
      context.setFillColor(gray: 0.1, alpha: 1)
      context.fill(CGRect(x: 100, y: 100, width: 100, height: 150))
      // A 1px-tall line running the full width at the very top edge -- the measured signature
      // of a platen-edge shadow fragment (1-4px thick against real scans).
      context.fill(CGRect(x: 0, y: height - 1, width: width, height: 1))
    }
    let box = try #require(DocumentCropper.contentExtentBox(image))
    // If the sliver had been counted, maxY would sit at height-1 (399); it must not.
    #expect(box.maxY < 350, "sliver leaked into the box: maxY was \(box.maxY)")
  }

  @Test("chunky content touching the border (e.g. a graphic printed near the page edge) is kept")
  func chunkyBorderContentIsKept() throws {
    let width = 300
    let height = 400
    let image = Self.grayscaleImage(width: width, height: height, background: 0.95) { context in
      // A substantial square in the corner, touching two borders -- not a sliver in either
      // dimension (80x80, far above contentExtentSliverMaxThickness).
      context.setFillColor(gray: 0.1, alpha: 1)
      context.fill(CGRect(x: 0, y: height - 80, width: 80, height: 80))
      // Separate content elsewhere on the page.
      context.fill(CGRect(x: 150, y: 100, width: 100, height: 150))
    }
    let box = try #require(DocumentCropper.contentExtentBox(image))
    #expect(box.minX < 5, "chunky border content was dropped: minX was \(box.minX)")
    #expect(
      box.maxY > Double(height) - 5, "chunky border content was dropped: maxY was \(box.maxY)")
  }

  @Test("an isolated noise speck far from the real content does not drag the box outward")
  func isolatedSpeckDoesNotExpandBox() throws {
    let width = 300
    let height = 400
    let image = Self.grayscaleImage(width: width, height: height, background: 0.95) { context in
      context.setFillColor(gray: 0.1, alpha: 1)
      context.fill(CGRect(x: 100, y: 100, width: 100, height: 150))
      // A 2x2 speck (4px, under contentDenoiseMinComponentPixels) in the far corner.
      context.fill(CGRect(x: width - 2, y: height - 2, width: 2, height: 2))
    }
    let box = try #require(DocumentCropper.contentExtentBox(image))
    #expect(box.maxX < 250, "isolated speck expanded the box: maxX was \(box.maxX)")
    #expect(box.maxY < 300, "isolated speck expanded the box: maxY was \(box.maxY)")
  }

  @Test("a blank page with no content registers as nil, not a guessed box")
  func blankPageReturnsNil() {
    let image = Self.grayscaleImage(width: 300, height: 400, background: 0.95) { _ in }
    #expect(DocumentCropper.contentExtentBox(image) == nil)
  }

  @Test("contentExtentCrop pads outward past the tight content box, never inward")
  func cropAddsInclusionPadding() throws {
    let width = 300
    let height = 400
    let image = Self.grayscaleImage(width: width, height: height, background: 0.95) { context in
      context.setFillColor(gray: 0.1, alpha: 1)
      context.fill(CGRect(x: 100, y: 100, width: 100, height: 150))
    }
    let hardwareDPI = 300
    let page = ScannedPage(
      image: image, widthMM: Double(width) / Double(hardwareDPI) * 25.4,
      heightMM: Double(height) / Double(hardwareDPI) * 25.4, requestedDPI: hardwareDPI,
      hardwareDPI: hardwareDPI, mode: .color)

    let tightBox = try #require(DocumentCropper.contentExtentBox(image))
    let result = DocumentCropper.contentExtentCrop(page)

    #expect(result.image.width < width, "should still be cropped smaller than the full canvas")
    #expect(
      Double(result.image.width) >= tightBox.width,
      "padding must not shrink below the tight content box")
  }

  @Test(
    "crop() falls back to contentExtentCrop -- not the untouched full bed -- when there is no page-vs-background contrast for Vision at all"
  )
  func cropUsesContentFallbackWhenVisionHasNoBoundary() throws {
    // Platen and page are the *same* shade -- no boundary exists anywhere in the image, so
    // VNDetectDocumentSegmentationRequest has literally nothing to key on (the same condition
    // measured on real hardware: 0.0 confidence, not just low). Real dark content is drawn on
    // top so there's still something for the content-mask fallback to find.
    let width = 600
    let height = 800
    let image = Self.grayscaleImage(width: width, height: height, background: 0.97) { context in
      context.setFillColor(gray: 0.15, alpha: 1)
      context.fill(CGRect(x: 100, y: 500, width: 350, height: 200))
    }
    let hardwareDPI = 300
    let page = ScannedPage(
      image: image, widthMM: Double(width) / Double(hardwareDPI) * 25.4,
      heightMM: Double(height) / Double(hardwareDPI) * 25.4, requestedDPI: hardwareDPI,
      hardwareDPI: hardwareDPI, mode: .color)

    let result = DocumentCropper.crop(page)
    #expect(result.image.width < width, "expected a content-based crop, got the untouched full bed")
    #expect(
      result.image.height < height, "expected a content-based crop, got the untouched full bed")
  }
}
