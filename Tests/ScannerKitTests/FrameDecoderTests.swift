import CoreGraphics
import Testing

@testable import ScannerKit

@Suite("FrameDecoder")
struct FrameDecoderTests {
  /// Short, positional constructor for test fixtures — keeps call sites on one line
  /// (`SaneParametersRecord`'s full named-argument form doesn't fit swift-format's 100-col
  /// limit without wrapping into a shape swiftlint's `multiline_arguments` then rejects).
  /// Every fixture in this suite is a single, final frame, hence the fixed `lastFrame: true`.
  private func params(
    _ format: SaneFrameFormat,
    _ bytesPerLine: Int32,
    _ pixelsPerLine: Int32,
    _ lines: Int32,
    _ depth: Int32
  ) -> SaneParametersRecord {
    SaneParametersRecord(
      format: format,
      lastFrame: true,
      bytesPerLine: bytesPerLine,
      pixelsPerLine: pixelsPerLine,
      lines: lines,
      depth: depth
    )
  }

  /// Reads back a decoded CGImage's raw 8-bit gray samples, row by row, for assertion.
  private func grayPixels(_ image: CGImage) throws -> [[UInt8]] {
    let data = try #require(image.dataProvider?.data)
    let pointer = CFDataGetBytePtr(data)
    let length = CFDataGetLength(data)
    let bytesPerRow = image.bytesPerRow
    let width = image.width
    let height = image.height
    #expect(length >= bytesPerRow * height)

    var rows: [[UInt8]] = []
    for row in 0..<height {
      var pixels: [UInt8] = []
      for col in 0..<width {
        pixels.append(pointer![row * bytesPerRow + col])
      }
      rows.append(pixels)
    }
    return rows
  }

  @Test("1-bit lineart unpacks MSB-first, bit 1 = black (0), bit 0 = white (255)")
  func unpacksLineart1Bit() throws {
    // width = 8 (exactly one byte per row, no padding). Row 0: 0b1011_0010 -> bits
    // 1,0,1,1,0,0,1,0 (MSB first) -> black,white,black,black,white,white,black,white.
    // Row 1: 0b0000_1111 -> white*4, black*4.
    let packed: [UInt8] = [0b1011_0010, 0b0000_1111]
    let parameters = params(.gray, 1, 8, 2, 1)

    let image = try FrameDecoder.decodeLineart1(bytes: packed, params: parameters)

    #expect(image.width == 8)
    #expect(image.height == 2)

    let rows = try grayPixels(image)
    #expect(rows[0] == [0, 255, 0, 0, 255, 255, 0, 255])
    #expect(rows[1] == [255, 255, 255, 255, 0, 0, 0, 0])
  }

  @Test("1-bit lineart handles row padding when width isn't a multiple of 8")
  func handlesRowPadding() throws {
    // width = 10 -> bytesPerLine = ceil(10/8) = 2, with 6 unused low bits in the 2nd byte.
    // Row: byte0 = 0b1111_0000 (bits: 1,1,1,1,0,0,0,0), byte1 = 0b1100_0000 (bits 8,9: 1,1;
    // remaining 6 bits unused/ignored).
    let packed: [UInt8] = [0b1111_0000, 0b1100_0000]
    let parameters = params(.gray, 2, 10, 1, 1)

    let image = try FrameDecoder.decodeLineart1(bytes: packed, params: parameters)
    let rows = try grayPixels(image)

    #expect(rows[0] == [0, 0, 0, 0, 255, 255, 255, 255, 0, 0])
  }

  @Test("short frame throws rather than reading out of bounds")
  func shortFrameThrows() {
    let parameters = params(.gray, 4, 32, 10, 1)
    #expect(throws: FrameDecoder.DecodeError.self) {
      try FrameDecoder.decodeLineart1(bytes: [0x00, 0x00], params: parameters)
    }
  }

  @Test("8-bit RGB frame decodes to the right dimensions and format")
  func decodesRGB8() throws {
    let width = 4
    let height = 2
    var bytes = [UInt8]()
    for row in 0..<height {
      for col in 0..<width {
        bytes.append(contentsOf: [UInt8(col), UInt8(row), UInt8(col + row)])
      }
    }
    let parameters = params(.rgb, Int32(width * 3), Int32(width), Int32(height), 8)

    let image = try FrameDecoder.decode(bytes: bytes, params: parameters)

    #expect(image.width == width)
    #expect(image.height == height)
    #expect(image.bitsPerPixel == 24)
  }

  @Test("8-bit gray frame decodes to the right dimensions and format")
  func decodesGray8() throws {
    let width = 4
    let height = 3
    let bytes = [UInt8](repeating: 128, count: width * height)
    let parameters = params(.gray, Int32(width), Int32(width), Int32(height), 8)

    let image = try FrameDecoder.decode(bytes: bytes, params: parameters)

    #expect(image.width == width)
    #expect(image.height == height)
    #expect(image.bitsPerPixel == 8)
  }

  @Test("a three-pass RGB/RED/GREEN/BLUE frame is rejected, not guessed at")
  func rejectsThreePassFrames() {
    let parameters = params(.red, 4, 4, 1, 8)
    #expect(throws: FrameDecoder.DecodeError.self) {
      try FrameDecoder.decode(bytes: [0, 0, 0, 0], params: parameters)
    }
  }
}
