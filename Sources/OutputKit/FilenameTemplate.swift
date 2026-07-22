import Foundation

/// Builds `scan-{date}-{seq}` filenames (DESIGN.md's settings-pane example:
/// `scan-2026-07-22-001`), avoiding collisions within a target directory.
///
/// Deliberately pure — it takes the directory's existing filenames as a `Set<String>`
/// rather than touching `FileManager` itself, so it's trivially testable and the caller
/// (the app, Phase 5) controls exactly when/how the directory gets listed.
public enum FilenameTemplate {
  private static let sequenceDigits = 3
  private static let maxSequence = 999

  public enum TemplateError: Error, CustomStringConvertible, Sendable, Equatable {
    /// Every sequence number up to `maxSequence` for this date is already taken.
    case sequenceExhausted(date: String)

    public var description: String {
      switch self {
      case .sequenceExhausted(let date):
        return "no free scan-\(date)-NNN sequence number left (all \(maxSequence) taken)"
      }
    }
  }

  /// Returns the next non-colliding filename for `date`, e.g. `scan-2026-07-22-001.pdf`.
  /// `existingFilenames` should be exactly what's in the target directory (any casing,
  /// full names with extensions) — compared verbatim, so pass the real directory listing.
  public static func nextFilename(
    date: Date = Date(),
    ext: String,
    existingFilenames: Set<String>,
    calendar: Calendar = .current,
    timeZone: TimeZone = TimeZone(identifier: "UTC")!
  ) throws -> String {
    let dateString = formattedDate(date, calendar: calendar, timeZone: timeZone)
    for sequence in 1...maxSequence {
      let candidate = filename(date: dateString, sequence: sequence, ext: ext)
      if !existingFilenames.contains(candidate) {
        return candidate
      }
    }
    throw TemplateError.sequenceExhausted(date: dateString)
  }

  private static func filename(date: String, sequence: Int, ext: String) -> String {
    let paddedSequence = String(format: "%0\(sequenceDigits)d", sequence)
    return "scan-\(date)-\(paddedSequence).\(ext)"
  }

  private static func formattedDate(
    _ date: Date, calendar: Calendar, timeZone: TimeZone
  ) -> String {
    var utcCalendar = calendar
    utcCalendar.timeZone = timeZone
    let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
    let year = components.year ?? 0
    let month = components.month ?? 0
    let day = components.day ?? 0
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
}
