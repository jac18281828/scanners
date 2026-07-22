import Foundation
import Testing

@testable import OutputKit

@Suite("FilenameTemplate")
struct FilenameTemplateTests {
  private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: components)!
  }

  @Test("empty directory yields sequence 001")
  func emptyDirectoryStartsAtOne() throws {
    let name = try FilenameTemplate.nextFilename(
      date: Self.date(2026, 7, 22), ext: "pdf", existingFilenames: [])
    #expect(name == "scan-2026-07-22-001.pdf")
  }

  @Test("collisions are skipped in order")
  func collisionsSkipped() throws {
    let existing: Set<String> = [
      "scan-2026-07-22-001.pdf",
      "scan-2026-07-22-002.pdf",
    ]
    let name = try FilenameTemplate.nextFilename(
      date: Self.date(2026, 7, 22), ext: "pdf", existingFilenames: existing)
    #expect(name == "scan-2026-07-22-003.pdf")
  }

  @Test("a gap in the sequence is not filled — collision avoidance only, not compaction")
  func gapIsNotFilled() throws {
    let existing: Set<String> = [
      "scan-2026-07-22-001.pdf",
      "scan-2026-07-22-003.pdf",
    ]
    let name = try FilenameTemplate.nextFilename(
      date: Self.date(2026, 7, 22), ext: "pdf", existingFilenames: existing)
    #expect(name == "scan-2026-07-22-002.pdf")
  }

  @Test("different dates get independent sequences")
  func differentDatesIndependent() throws {
    let existing: Set<String> = ["scan-2026-07-21-001.pdf"]
    let name = try FilenameTemplate.nextFilename(
      date: Self.date(2026, 7, 22), ext: "pdf", existingFilenames: existing)
    #expect(name == "scan-2026-07-22-001.pdf")
  }

  @Test("extension is honored verbatim")
  func extensionHonored() throws {
    let name = try FilenameTemplate.nextFilename(
      date: Self.date(2026, 7, 22), ext: "jpg", existingFilenames: [])
    #expect(name == "scan-2026-07-22-001.jpg")
  }

  @Test("a custom prefix replaces the default 'scan', date/sequence shape unchanged")
  func customPrefixHonored() throws {
    let name = try FilenameTemplate.nextFilename(
      date: Self.date(2026, 7, 22), ext: "pdf", existingFilenames: [], prefix: "invoice")
    #expect(name == "invoice-2026-07-22-001.pdf")
  }

  @Test("exhausted sequence throws rather than silently colliding")
  func exhaustedSequenceThrows() {
    var existing = Set<String>()
    for sequence in 1...999 {
      existing.insert(String(format: "scan-2026-07-22-%03d.pdf", sequence))
    }
    #expect(throws: FilenameTemplate.TemplateError.self) {
      try FilenameTemplate.nextFilename(
        date: Self.date(2026, 7, 22), ext: "pdf", existingFilenames: existing)
    }
  }
}
