import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import OutputKit
@testable import ScannerKit

@Suite("ImageExporter")
struct ImageExporterTests {
  private static func embeddedDPI(_ data: Data) -> (width: Double, height: Double)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      return nil
    }
    guard let width = properties[kCGImagePropertyDPIWidth] as? Double,
      let height = properties[kCGImagePropertyDPIHeight] as? Double
    else {
      return nil
    }
    return (width, height)
  }

  private static func page() -> ScannedPage {
    let size = Fixtures.PageSize(
      widthPixels: 850, heightPixels: 1169, widthMM: 215.9, heightMM: 297.0)
    return Fixtures.solidPage(size: size, requestedDPI: 100, hardwareDPI: 100)
  }

  @Test("JPEG export embeds dpi metadata matching the effective (post-normalize) dpi")
  func jpegDPIMetadata() throws {
    let data = try ImageExporter.jpegData(for: Self.page())
    #expect(!data.isEmpty)
    let dpi = try #require(Self.embeddedDPI(data))
    #expect(abs(dpi.width - 100) < 1)
    #expect(abs(dpi.height - 100) < 1)
  }

  @Test("PNG export embeds dpi metadata")
  func pngDPIMetadata() throws {
    let data = try ImageExporter.pngData(for: Self.page())
    #expect(!data.isEmpty)
    let dpi = try #require(Self.embeddedDPI(data))
    #expect(abs(dpi.width - 100) < 1)
  }

  @Test("TIFF export embeds dpi metadata")
  func tiffDPIMetadata() throws {
    let data = try ImageExporter.tiffData(for: Self.page())
    #expect(!data.isEmpty)
    let dpi = try #require(Self.embeddedDPI(data))
    #expect(abs(dpi.width - 100) < 1)
  }

  @Test("HEIC export produces non-empty data where the platform supports HEIC encoding")
  func heicExport() throws {
    do {
      let data = try ImageExporter.heicData(for: Self.page())
      #expect(!data.isEmpty)
    } catch {
      // Some CI/VM environments lack a hardware HEVC encoder, which HEIC encoding needs.
      // The code path itself is exercised regardless — a clean throw, not a crash — so
      // this is recorded rather than failed. See the phase report for what this
      // environment actually did.
      Issue.record(
        "HEIC export unavailable in this environment (likely no HW HEVC encoder): \(error)")
    }
  }

  @Test("downscaled export reflects the requested dpi, not the hardware dpi")
  func exportUsesNormalizedDPI() throws {
    let widthMM = 215.889
    let size = Fixtures.PageSize(
      widthPixels: 850, heightPixels: 1169, widthMM: widthMM, heightMM: 297.699)
    let page = Fixtures.solidPage(size: size, requestedDPI: 75, hardwareDPI: 100)
    let data = try ImageExporter.pngData(for: page)
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      Issue.record("failed to re-read exported PNG")
      return
    }
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    #expect(image?.width == 637)
    let dpi = try #require(Self.embeddedDPI(data))
    #expect(abs(dpi.width - 75) < 1)
  }

  @Test("default JPEG quality is 0.85")
  func defaultJPEGQuality() {
    #expect(ImageExporter.defaultJPEGQuality == 0.85)
  }
}
