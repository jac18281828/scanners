import CoreGraphics
import Foundation

/// Repacks an 8-bit grayscale `CGImage` whose samples are effectively bilevel (0 or 255 —
/// exactly what `ScannerKit.FrameDecoder.decodeLineart1` produces, and what `PageNormalizer`
/// preserves at the extremes for anything but heavy downscaling) into a true 1-bit-per-pixel
/// `CGImage`.
///
/// Why this exists: Quartz's PDF writer only gets a chance to CCITT-Group-4-compress an
/// image it draws when the source `CGImage` itself is `bitsPerComponent == 1`. Feeding it
/// FrameDecoder's 8-bit expansion directly would make every lineart page a full-size Flate
/// (or worse) blob. Packing back down to 1bpp here — bit 1 = white, bit 0 = black, matching
/// PDF's default `DeviceGray` `Decode` array — gives the PDF writer the shape it needs.
enum LineartPacker {
  /// Threshold below which a sample is treated as black. FrameDecoder only ever emits 0 or
  /// 255, but `PageNormalizer`'s `.high`-interpolation downscale can introduce intermediate
  /// gray values at edges — the midpoint keeps that antialiasing from flipping to solid
  /// black/white in a biased direction.
  private static let blackThreshold: UInt8 = 128

  static func pack1Bit(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    guard let gray = grayscaleBytes(of: image) else { return nil }

    let dstBytesPerRow = (width + 7) / 8
    var packed = [UInt8](repeating: 0, count: dstBytesPerRow * height)

    gray.withUnsafeBufferPointer { src in
      packed.withUnsafeMutableBufferPointer { dst in
        for row in 0..<height {
          let srcRowStart = row * width
          let dstRowStart = row * dstBytesPerRow
          for col in 0..<width {
            let sample = src[srcRowStart + col]
            guard sample >= blackThreshold else { continue }  // 0 bit already = black
            dst[dstRowStart + col / 8] |= (0x80 >> (col % 8))  // 1 bit = white
          }
        }
      }
    }

    guard let provider = CGDataProvider(data: Data(bytes: packed, count: packed.count) as CFData)
    else {
      return nil
    }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 1,
      bitsPerPixel: 1,
      bytesPerRow: dstBytesPerRow,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  /// Normalizes any 8-bit grayscale source to a tightly-packed `[UInt8]` (one byte per
  /// pixel), redrawing through a `CGContext` if the source isn't already in that exact
  /// layout — keeps the bit-packing loop above simple and correct regardless of what
  /// upstream (FrameDecoder, PageNormalizer's resize) happened to produce.
  private static func grayscaleBytes(of image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    var buffer = [UInt8](repeating: 0, count: width * height)
    let filled: Bool = buffer.withUnsafeMutableBytes { raw in
      guard
        let context = CGContext(
          data: raw.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      else {
        return false
      }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return filled ? buffer : nil
  }
}
