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
  /// The date is formatted in `calendar`'s own time zone, not forced to UTC — a scan taken
  /// near local midnight gets the day it was actually taken on.
  /// `existingFilenames` should be exactly what's in the target directory (full names with
  /// extensions) — compared case-insensitively to match the default APFS volume, so pass the
  /// real directory listing.
  ///
  /// `prefix` replaces the leading `scan` (default, unchanged from prior behavior) — Phase
  /// 5's Settings pane exposes this as the "filename template" DESIGN.md's product-behavior
  /// section calls for. The `{date}-{seq}` shape itself isn't user-customizable, only the
  /// prefix in front of it.
  public static func nextFilename(
    date: Date = Date(),
    ext: String,
    existingFilenames: Set<String>,
    calendar: Calendar = .current,
    prefix: String = "scan"
  ) throws -> String {
    let dateString = formattedDate(date, calendar: calendar)
    let safePrefix = sanitizedPrefix(prefix)
    // Compare case-insensitively: the default macOS (APFS) volume is case-insensitive, so an
    // existing `scan-...-001.PDF` collides on disk with a candidate `scan-...-001.pdf` even
    // though the strings differ. A verbatim `contains` would miss it and hand back a name that
    // silently overwrites the existing file.
    let existingLowercased = Set(existingFilenames.map { $0.lowercased() })
    for sequence in 1...maxSequence {
      let candidate = filename(date: dateString, sequence: sequence, ext: ext, prefix: safePrefix)
      if !existingLowercased.contains(candidate.lowercased()) {
        return candidate
      }
    }
    throw TemplateError.sequenceExhausted(date: dateString)
  }

  private static func filename(date: String, sequence: Int, ext: String, prefix: String) -> String {
    let paddedSequence = String(format: "%0\(sequenceDigits)d", sequence)
    return "\(prefix)-\(date)-\(paddedSequence).\(ext)"
  }

  /// Reduces `prefix` to a single safe path component before it's interpolated into a
  /// filename: strips directory separators (`/`, `\`, `:`) and leading/trailing dots and
  /// spaces. Without this a user-entered "filename template" like `../../foo` would produce a
  /// suggested name that escapes the target directory, and a leading `.` would name a hidden
  /// file. Empty after sanitizing falls back to the default `scan`. This module documents its
  /// output as one safe path component; enforcing it here keeps that true for a future caller
  /// that writes the name directly rather than through an `NSSavePanel` the user confirms.
  private static func sanitizedPrefix(_ prefix: String) -> String {
    let separators = CharacterSet(charactersIn: "/\\:")
    let withoutSeparators = prefix.components(separatedBy: separators).joined()
    let trimmed = withoutSeparators.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return trimmed.isEmpty ? "scan" : trimmed
  }

  private static func formattedDate(_ date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    let year = components.year ?? 0
    let month = components.month ?? 0
    let day = components.day ?? 0
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
}
