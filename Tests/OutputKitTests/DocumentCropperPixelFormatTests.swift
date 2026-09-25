import CoreGraphics
import Foundation
import Testing

@testable import OutputKit
@testable import ScannerKit

/// `boundingBoxCrop` keeps the source's color model and bit depth: gray in, gray out; RGB in,
/// RGB out.
@Suite("DocumentCropper pixel format")
struct DocumentCropperPixelFormatTests {
  @Test(
    "boundingBoxCrop preserves exact pixel values for an 8-bit gray source -- an off-by-one crop offset (a geometry regression) fails this the same as a format regression"
  )
  func boundingBoxCropPreservesExactGrayPixels() throws {
    let width = 12
    let height = 10
    var bytes = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
      for col in 0..<width {
        bytes[row * width + col] = UInt8((col * 7 + row * 13) % 251)
      }
    }
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
      space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!

    // `PixelCorners` live in CG's bottom-left, y-up space (see the type's own doc comment) --
    // an axis-aligned box, x in [3,9), y in [2,7).
    let corners = DocumentCropper.PixelCorners(
      topLeft: CGPoint(x: 3, y: 7), topRight: CGPoint(x: 9, y: 7),
      bottomLeft: CGPoint(x: 3, y: 2), bottomRight: CGPoint(x: 9, y: 2))
    let extent = CGRect(x: 0, y: 0, width: width, height: height)
    let cropped = try #require(
      DocumentCropper.boundingBoxCrop(image, corners: corners, imageExtent: extent))

    #expect(cropped.colorSpace?.model == .monochrome)
    #expect(cropped.bitsPerComponent == 8)
    #expect(cropped.bitsPerPixel == 8, "a gray crop must stay 8 bits per pixel, not 32-bit RGBA")
    #expect(cropped.width == 6)
    #expect(cropped.height == 5)

    // CIImage's y-up extent flips row order against the raw buffer's top-down storage (see
    // `contentExtentBox`'s own doc comment on this same flip) -- the crop's top raw row is
    // `height - maxY`. Channel 0 of each pixel, via `bitsPerPixel`, not a hardcoded 1-byte
    // stride, so this reads correctly regardless of the crop's pixel format.
    let croppedData = cropped.dataProvider!.data! as Data
    let croppedBytesPerRow = cropped.bytesPerRow
    let pixelStride = cropped.bitsPerPixel / 8
    for row in 0..<cropped.height {
      for col in 0..<cropped.width {
        let sourceRow = height - 7 + row
        let sourceCol = 3 + col
        let expected = bytes[sourceRow * width + sourceCol]
        let actual = croppedData[row * croppedBytesPerRow + col * pixelStride]
        #expect(
          actual == expected, "mismatch at (\(col), \(row)): expected \(expected), got \(actual)")
      }
    }
  }

  @Test("boundingBoxCrop keeps an RGB source RGB, not converting it to a different color model")
  func boundingBoxCropKeepsRGBAsRGB() throws {
    let image = Fixtures.solidImage(widthPixels: 40, heightPixels: 40, mode: .color)
    let corners = DocumentCropper.PixelCorners(
      topLeft: CGPoint(x: 5, y: 35), topRight: CGPoint(x: 35, y: 35),
      bottomLeft: CGPoint(x: 5, y: 5), bottomRight: CGPoint(x: 35, y: 5))
    let extent = CGRect(x: 0, y: 0, width: 40, height: 40)
    let cropped = try #require(
      DocumentCropper.boundingBoxCrop(image, corners: corners, imageExtent: extent))
    #expect(cropped.colorSpace?.model == .rgb)
    #expect(cropped.bitsPerComponent == 8)
  }
}
