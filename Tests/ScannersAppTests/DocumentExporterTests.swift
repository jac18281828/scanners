import CoreGraphics
import Foundation
import OutputKit
import PDFKit
import ScannerKit
import Testing

@testable import ScannersApp

@Suite("DocumentExporter")
@MainActor
struct DocumentExporterTests {
  @Test("buildPDFData throws on an empty session rather than producing a 0-page PDF")
  func buildPDFDataThrowsWhenEmpty() {
    let session = DocumentSession(documentMode: .text)
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    #expect(throws: DocumentExporter.ExportError.emptyDocument) {
      try DocumentExporter.buildPDFData(session: session, settings: settings)
    }
  }

  @Test("buildPDFData produces one PDF page per scanned page, in session order")
  func buildPDFDataProducesOnePagePerScannedPage() throws {
    let session = DocumentSession(documentMode: .image)  // no OCR layer -- keeps this fast
    session.addPage(TestFixtures.solidPage())
    session.addPage(TestFixtures.solidPage())
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())

    let data = try DocumentExporter.buildPDFData(session: session, settings: settings)

    let document = try #require(PDFDocument(data: data))
    #expect(document.pageCount == 2)
  }

  @Test(
    "buildPDFData draws a Text-mode page's precomputed OCR lines instead of running Vision itself"
  )
  func buildPDFDataUsesPrecomputedOCRLines() throws {
    let session = DocumentSession(documentMode: .text)
    let entry = session.addPage(TestFixtures.solidPage(widthPixels: 850, heightPixels: 1100))
    session.setOCRResult(
      [
        OCRTextLine(
          text: "EXPORTERSENTINEL", boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.35, height: 0.03))
      ], for: entry.id)
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())

    let data = try DocumentExporter.buildPDFData(session: session, settings: settings)

    let document = try #require(PDFDocument(data: data))
    let extracted = (try #require(document.page(at: 0)).string ?? "").filter { !$0.isWhitespace }
    #expect(extracted.contains("EXPORTERSENTINEL"))
  }

  @Test("Image-mode buildPDFData never includes an OCR text layer, precomputed or not")
  func buildPDFDataSkipsOCRLayerInImageMode() throws {
    let session = DocumentSession(documentMode: .image)
    session.addPage(TestFixtures.solidPage())
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())

    let data = try DocumentExporter.buildPDFData(session: session, settings: settings)

    let document = try #require(PDFDocument(data: data))
    let extracted = try #require(document.page(at: 0)).string ?? ""
    #expect(extracted.isEmpty)
  }

  @Test("suggestedFilename honors the configured prefix and the target folder's real contents")
  func suggestedFilenameHonorsPrefixAndExistingFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "scanners-exporter-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    settings.saveFolder = folder
    settings.filenamePrefix = "invoice"

    let first = DocumentExporter.suggestedFilename(ext: "pdf", settings: settings)
    #expect(first.hasPrefix("invoice-"))
    #expect(first.hasSuffix(".pdf"))

    try Data().write(to: folder.appendingPathComponent(first))
    let second = DocumentExporter.suggestedFilename(ext: "pdf", settings: settings)
    #expect(second != first)  // collision avoidance actually looked at the real directory
  }

  @Test(
    "imagePageToExport is the most recently scanned page, not the session's first page (regression: found via manual UI testing that switching Text -> Image mid-session left Save Image exporting a stale page)"
  )
  func imagePageToExportUsesMostRecentPage() {
    let session = DocumentSession(documentMode: .text)
    let textPage = session.addPage(TestFixtures.solidPage(mode: .blackAndWhite))

    // Simulate the exact scenario the manual checklist hit: switch to Image mode without a
    // ⌘N reset, then scan -- the earlier Text-mode page is still sitting in session.pages.
    session.documentMode = .image
    let imagePage = session.addPage(TestFixtures.solidPage(mode: .color))

    let exported = DocumentExporter.imagePageToExport(session: session)

    #expect(exported?.id == imagePage.id)
    #expect(exported?.id != textPage.id)
  }

  @Test("suggestedBaseName strips the extension so the image format picker can swap it live")
  func suggestedBaseNameHasNoExtension() {
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let base = DocumentExporter.suggestedBaseName(settings: settings)
    #expect(!base.contains("."))
  }
}
