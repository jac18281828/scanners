import Testing

@testable import OutputKit

@Suite("OCREngine")
struct OCREngineTests {
  private static let knownText = "The quick brown fox jumps over the lazy dog 2026"

  /// Word-level match fraction: how many words of `expected` appear (case-insensitively,
  /// order-independent) somewhere in the recognized lines. A coarse but flake-resistant
  /// metric for a rendered-text fixture, matching the phase prompt's "recovered text >= 95%
  /// match" bar without demanding exact whitespace/line-break fidelity from Vision.
  private static func wordMatchFraction(recognized: [OCRTextLine], expected: String) -> Double {
    let recognizedWords = Set(
      recognized.flatMap { $0.text.lowercased().split(separator: " ") }.map(String.init))
    let expectedWords = expected.lowercased().split(separator: " ").map(String.init)
    guard !expectedWords.isEmpty else { return 1 }
    let matched = expectedWords.filter { recognizedWords.contains($0) }.count
    return Double(matched) / Double(expectedWords.count)
  }

  @Test("gray text-page fixture recognizes >= 95% of known words")
  func grayRecognitionMeetsBar() throws {
    let page = Fixtures.textPage(Self.knownText, dpi: 300, bilevel: false)
    let lines = try OCREngine.recognizeLines(in: page.image)
    let score = Self.wordMatchFraction(recognized: lines, expected: Self.knownText)
    #expect(score >= 0.95, "gray OCR word match was \(score), expected >= 0.95")
  }

  @Test("bounding boxes are within the normalized 0...1 image space")
  func boundingBoxesAreNormalized() throws {
    let page = Fixtures.textPage(Self.knownText, dpi: 300, bilevel: false)
    let lines = try OCREngine.recognizeLines(in: page.image)
    #expect(!lines.isEmpty)
    for line in lines {
      #expect(line.boundingBox.minX >= 0 && line.boundingBox.maxX <= 1)
      #expect(line.boundingBox.minY >= 0 && line.boundingBox.maxY <= 1)
    }
  }

  /// DESIGN.md flag #4 / Phase 4 task 3: validate OCR quality on Lineart input. This runs
  /// the comparison on a synthetic bilevel (antialiasing disabled) fixture as a CI-safe
  /// proxy for real Lineart scanner output — see the phase report for the authoritative
  /// finding from an actual hp5590 Lineart scan, run once during the hardware smoke test
  /// (Scripts/smoke-output.sh) rather than as a second hardware dependency here.
  @Test("bilevel (lineart-proxy) recognition is not drastically worse than gray")
  func lineartProxyRecognitionIsReasonable() throws {
    let grayPage = Fixtures.textPage(Self.knownText, dpi: 300, bilevel: false)
    let bilevelPage = Fixtures.textPage(Self.knownText, dpi: 300, bilevel: true)

    let grayLines = try OCREngine.recognizeLines(in: grayPage.image)
    let bilevelLines = try OCREngine.recognizeLines(in: bilevelPage.image)

    let grayScore = Self.wordMatchFraction(recognized: grayLines, expected: Self.knownText)
    let bilevelScore = Self.wordMatchFraction(recognized: bilevelLines, expected: Self.knownText)

    // Not a strict pass/fail bar (a synthetic bilevel render isn't real scanner artifacts) —
    // just a regression guard: catches OCREngine breaking entirely on 1bpp-shaped input.
    #expect(bilevelScore >= grayScore - 0.34)
  }
}
