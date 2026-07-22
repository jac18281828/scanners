import PDFKit
import Testing

@testable import OutputKit
@testable import ScannerKit

@Suite("PDFBuilder")
struct PDFBuilderTests {
  @Test("a 2-page document reports the right page count and media box per page")
  func pageCountAndMediaBox() throws {
    let builder = try PDFBuilder()
    let sizeA = Fixtures.PageSize(
      widthPixels: 850, heightPixels: 1169, widthMM: 215.9, heightMM: 297.0)
    let pageA = Fixtures.solidPage(size: sizeA, requestedDPI: 100, hardwareDPI: 100)
    let sizeB = Fixtures.PageSize(
      widthPixels: 600, heightPixels: 800, widthMM: 100.0, heightMM: 133.3)
    let pageB = Fixtures.solidPage(size: sizeB, requestedDPI: 150, hardwareDPI: 150)
    try builder.append(page: pageA)
    try builder.append(page: pageB)
    #expect(builder.pageCount == 2)

    let data = builder.finish()
    let document = try #require(PDFDocument(data: data))
    #expect(document.pageCount == 2)

    let mediaBoxA = try #require(document.page(at: 0)).bounds(for: .mediaBox)
    let expectedWidthPt = 215.9 / 25.4 * 72
    let expectedHeightPt = 297.0 / 25.4 * 72
    #expect(abs(mediaBoxA.width - expectedWidthPt) < 0.5)
    #expect(abs(mediaBoxA.height - expectedHeightPt) < 0.5)

    let mediaBoxB = try #require(document.page(at: 1)).bounds(for: .mediaBox)
    let expectedWidthPtB = 100.0 / 25.4 * 72
    #expect(abs(mediaBoxB.width - expectedWidthPtB) < 0.5)
  }

  @Test("a 300dpi lineart A4 page densely packed with text lands well under 200KB")
  func lineartPageSizeCeiling() throws {
    // Fixtures.denseLineartPage is ~53 lines of real text across a full A4 canvas — a
    // realistic worst case, not a trivial all-white page that would pass this gate
    // regardless of codec.
    let builder = try PDFBuilder()
    let page = Fixtures.denseLineartPage()
    try builder.append(page: page)
    let data = builder.finish()
    #expect(data.count < 200 * 1024, "lineart page was \(data.count) bytes, expected < 200KB")
  }

  @Test("OCR text layer: recognized text is extractable via PDFKit's page.string")
  func ocrTextIsExtractable() throws {
    // .fast, not .accurate — see OCREngine.recognizeLines' doc comment (a GH Actions macOS
    // runner hung for >20 minutes on .accurate with zero output; suspected no Neural Engine
    // passthrough in the CI VM). Scripts/smoke-output.sh validates real .accurate behavior
    // against actual hardware.
    let page = Fixtures.textPage("HELLO WORLD 2026", dpi: 300, bilevel: false)
    let builder = try PDFBuilder()
    try builder.append(page: page, includeOCRTextLayer: true, ocrRecognitionLevel: .fast)
    let data = builder.finish()
    let document = try #require(PDFDocument(data: data))
    let extracted = try #require(document.page(at: 0)).string ?? ""
    #expect(extracted.uppercased().contains("HELLO"))
    #expect(extracted.uppercased().contains("WORLD"))
  }

  @Test("OCR text layer is positioned over the visible glyphs, not y-flipped")
  func ocrTextIsCorrectlyPositioned() throws {
    // Text is drawn low on the page (textPosition y = 0.35 * height, see Fixtures.textPage)
    // — near the bottom third. If the invisible layer were y-flipped, a selection rect
    // covering the *bottom* of the page would land on nothing (the flipped copy would sit
    // near the top instead), and one covering the *top* would find the text instead.
    // Position-only check, deliberately accuracy-agnostic: .fast mode (see the comment
    // above) can misread a character here and there ("BOTTOMTEXT" -> "BOTHOMTEXT" was seen
    // during development) without that being a positioning bug. So this asserts *something*
    // substantial was recognized at the bottom and *nothing* at the top, rather than
    // matching the exact string.
    let page = Fixtures.textPage("BOTTOMTEXT", dpi: 300, bilevel: false)
    let builder = try PDFBuilder()
    try builder.append(page: page, includeOCRTextLayer: true, ocrRecognitionLevel: .fast)
    let data = builder.finish()
    let document = try #require(PDFDocument(data: data))
    let pdfPage = try #require(document.page(at: 0))
    let bounds = pdfPage.bounds(for: .mediaBox)

    let bottomThird = CGRect(
      x: 0, y: 0, width: bounds.width, height: bounds.height * 0.5)
    let topThird = CGRect(
      x: 0, y: bounds.height * 0.5, width: bounds.width, height: bounds.height * 0.5)

    let bottomSelection =
      pdfPage.selection(for: bottomThird)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""
    let topSelection =
      pdfPage.selection(for: topThird)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""

    #expect(
      bottomSelection.count >= 8,
      "expected most of BOTTOMTEXT's 10 chars, got \(bottomSelection.debugDescription)")
    #expect(
      topSelection.isEmpty, "expected no text at the top, got \(topSelection.debugDescription)")
  }

  @Test("finish() can only be called once meaningfully; append after finish throws")
  func appendAfterFinishThrows() throws {
    let builder = try PDFBuilder()
    let size = Fixtures.PageSize(widthPixels: 100, heightPixels: 100, widthMM: 25.4, heightMM: 25.4)
    let page = Fixtures.solidPage(size: size, requestedDPI: 100, hardwareDPI: 100)
    try builder.append(page: page)
    _ = builder.finish()
    #expect(throws: (any Error).self) {
      try builder.append(page: page)
    }
  }
}
