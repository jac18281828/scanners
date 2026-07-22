import CoreGraphics
import Foundation

/// Turns a fully-read SANE frame's raw bytes into a `CGImage`. Handles the frame shapes
/// the hp5590 backend emits for the three `ScanMode`s: 8-bit RGB (`color`), 8-bit gray
/// (`gray`), and 1-bit gray (`blackAndWhite`/Lineart). A `SANE_FRAME_RED`/`GREEN`/`BLUE`
/// three-pass frame is explicitly rejected rather than guessed at — see the Phase 3
/// escalation clause in the phase prompt.
enum FrameDecoder {
  struct ShortFrameInfo: Sendable, Equatable {
    let expected: Int
    let got: Int
  }

  enum DecodeError: Error, Sendable, Equatable {
    case unsupportedFrameFormat(SaneFrameFormat)
    case shortFrame(ShortFrameInfo)
    case imageCreationFailed
  }

  /// Bundles every CGImage-construction knob, so `makeImage` stays under swiftlint's
  /// parameter-count limit and every call site fits on one line.
  private struct PixelLayout {
    let width: Int
    let height: Int
    let bitsPerPixel: Int
    let bytesPerRow: Int
    let colorSpace: CGColorSpace
  }

  static func decode(bytes: [UInt8], params: SaneParametersRecord) throws -> CGImage {
    switch params.format {
    case .rgb:
      return try decodeRGB8(bytes: bytes, params: params)
    case .gray:
      return params.depth == 1
        ? try decodeLineart1(bytes: bytes, params: params)
        : try decodeGray8(bytes: bytes, params: params)
    case .red, .green, .blue:
      throw DecodeError.unsupportedFrameFormat(params.format)
    }
  }

  // MARK: - 8-bit RGB (color)

  private static func decodeRGB8(bytes: [UInt8], params: SaneParametersRecord) throws -> CGImage {
    let width = Int(params.pixelsPerLine)
    let height = Int(params.lines)
    let bytesPerRow = Int(params.bytesPerLine)
    try requireLength(bytes, bytesPerRow * height)
    let layout = PixelLayout(
      width: width,
      height: height,
      bitsPerPixel: 24,
      bytesPerRow: bytesPerRow,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    return try makeImage(pixels: bytes, layout: layout)
  }

  // MARK: - 8-bit gray

  private static func decodeGray8(bytes: [UInt8], params: SaneParametersRecord) throws -> CGImage {
    let width = Int(params.pixelsPerLine)
    let height = Int(params.lines)
    let bytesPerRow = Int(params.bytesPerLine)
    try requireLength(bytes, bytesPerRow * height)
    let layout = PixelLayout(
      width: width,
      height: height,
      bitsPerPixel: 8,
      bytesPerRow: bytesPerRow,
      colorSpace: CGColorSpaceCreateDeviceGray()
    )
    return try makeImage(pixels: bytes, layout: layout)
  }

  // MARK: - 1-bit lineart

  /// SANE Lineart frames pack 8 pixels per byte, MSB first, one bit per pixel, following
  /// the same convention as raw PBM (P4): bit **1 = black**, bit **0 = white**. Each row is
  /// padded to a whole number of bytes (`bytesPerLine == ceil(pixelsPerLine / 8)`), so the
  /// last byte of a row may have unused low-order bits beyond `pixelsPerLine`.
  ///
  /// Unpacked here to 8-bit gray (0 = black, 255 = white) rather than kept packed, so
  /// downstream code (OutputKit, the CLI's PNG writer) only ever deals with one CGImage
  /// pixel format for gray-family frames.
  static func decodeLineart1(bytes: [UInt8], params: SaneParametersRecord) throws -> CGImage {
    let width = Int(params.pixelsPerLine)
    let height = Int(params.lines)
    let srcBytesPerRow = Int(params.bytesPerLine)
    try requireLength(bytes, srcBytesPerRow * height)

    var gray = [UInt8](repeating: 0, count: width * height)
    bytes.withUnsafeBufferPointer { source in
      for row in 0..<height {
        let rowStart = row * srcBytesPerRow
        let outRowStart = row * width
        for col in 0..<width {
          let byte = source[rowStart + col / 8]
          let bitIndex = 7 - (col % 8)
          let bit = (byte >> bitIndex) & 1
          gray[outRowStart + col] = bit == 1 ? 0 : 255
        }
      }
    }

    let layout = PixelLayout(
      width: width,
      height: height,
      bitsPerPixel: 8,
      bytesPerRow: width,
      colorSpace: CGColorSpaceCreateDeviceGray()
    )
    return try makeImage(pixels: gray, layout: layout)
  }

  // MARK: - Shared CGImage construction

  private static func makeImage(pixels: [UInt8], layout: PixelLayout) throws -> CGImage {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
      throw DecodeError.imageCreationFailed
    }
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    guard
      let image = CGImage(
        width: layout.width,
        height: layout.height,
        bitsPerComponent: 8,
        bitsPerPixel: layout.bitsPerPixel,
        bytesPerRow: layout.bytesPerRow,
        space: layout.colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else {
      throw DecodeError.imageCreationFailed
    }
    return image
  }

  private static func requireLength(_ bytes: [UInt8], _ expected: Int) throws {
    guard bytes.count >= expected else {
      throw DecodeError.shortFrame(ShortFrameInfo(expected: expected, got: bytes.count))
    }
  }
}

extension FrameDecoder.DecodeError: CustomStringConvertible {
  var description: String {
    switch self {
    case .unsupportedFrameFormat(let format):
      return "unsupported frame format \(format) (three-pass RGB not implemented — escalate)"
    case .shortFrame(let info):
      return "short frame: expected at least \(info.expected) bytes, got \(info.got)"
    case .imageCreationFailed:
      return "CGImage creation failed"
    }
  }
}
