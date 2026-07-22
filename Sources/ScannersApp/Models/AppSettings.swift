import Foundation
import Observation
import ScannerKit

/// Everything DESIGN.md's Settings pane (⌘,) manages, plus the "last-used settings persist
/// across launches" state — all backed by `UserDefaults` (DESIGN.md: "Stored via
/// UserDefaults/@AppStorage"). A plain `@Observable` class rather than `@AppStorage`
/// property wrappers directly in views: several of these values are `Codable` structs/
/// arrays (`[ScanPreset]`), which `@AppStorage` doesn't support natively, and tests need to
/// point a fresh instance at an isolated `UserDefaults` suite rather than the real one.
@MainActor
@Observable
public final class AppSettings {
  private enum Key {
    static let saveFolder = "dev.scanners.saveFolder"
    static let source = "dev.scanners.source"
    static let extendLampTimeout = "dev.scanners.extendLampTimeout"
    static let ocrLanguage = "dev.scanners.ocrLanguage"
    static let filenamePrefix = "dev.scanners.filenamePrefix"
    static let presets = "dev.scanners.presets"
    static let lastUsedDocumentMode = "dev.scanners.lastUsed.documentMode"
    static let lastUsedDPI = "dev.scanners.lastUsed.dpi"
    static let lastUsedColorMode = "dev.scanners.lastUsed.colorMode"
  }

  private let defaults: UserDefaults

  public var saveFolder: URL {
    didSet { defaults.set(saveFolder.path, forKey: Key.saveFolder) }
  }
  public var source: ScanSource {
    didSet { defaults.set(source.rawValue, forKey: Key.source) }
  }
  /// DESIGN.md's "lamp-timeout toggle" — flows into `ScanConfiguration.extendLampTimeout`.
  public var extendLampTimeout: Bool {
    didSet { defaults.set(extendLampTimeout, forKey: Key.extendLampTimeout) }
  }
  /// DESIGN.md decision #6 / product behavior: "OCR language (default English)." A BCP-47
  /// tag forwarded verbatim to `OCREngine.recognizeLines`/`PDFBuilder.append`'s `language:`
  /// parameter.
  public var ocrLanguage: String {
    didSet { defaults.set(ocrLanguage, forKey: Key.ocrLanguage) }
  }
  /// DESIGN.md's "filename template" — scoped to the prefix in front of
  /// `FilenameTemplate`'s fixed `{date}-{seq}` shape (see the phase report's deviations for
  /// why the template itself isn't arbitrarily user-definable).
  public var filenamePrefix: String {
    didSet { defaults.set(filenamePrefix, forKey: Key.filenamePrefix) }
  }
  public private(set) var presets: [ScanPreset] {
    didSet { persistPresets() }
  }

  /// "Last-used settings persist across launches" — read by the app at launch to seed a
  /// fresh `DocumentSession`, and written whenever `DocumentSession`'s live values change.
  public var lastUsedDocumentMode: DocumentMode {
    didSet { defaults.set(lastUsedDocumentMode.rawValue, forKey: Key.lastUsedDocumentMode) }
  }
  public var lastUsedDPI: Int {
    didSet { defaults.set(lastUsedDPI, forKey: Key.lastUsedDPI) }
  }
  public var lastUsedColorMode: ScanMode {
    didSet { defaults.set(lastUsedColorMode.rawValue, forKey: Key.lastUsedColorMode) }
  }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    if let path = defaults.string(forKey: Key.saveFolder) {
      self.saveFolder = URL(fileURLWithPath: path)
    } else {
      self.saveFolder =
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
    }

    self.source =
      defaults.string(forKey: Key.source).flatMap(ScanSource.init(rawValue:)) ?? .flatbed
    self.extendLampTimeout =
      defaults.object(forKey: Key.extendLampTimeout) != nil
      ? defaults.bool(forKey: Key.extendLampTimeout) : false
    self.ocrLanguage = defaults.string(forKey: Key.ocrLanguage) ?? "en-US"
    self.filenamePrefix = defaults.string(forKey: Key.filenamePrefix) ?? "scan"

    if let data = defaults.data(forKey: Key.presets),
      let decoded = try? JSONDecoder().decode([ScanPreset].self, from: data)
    {
      self.presets = decoded
    } else {
      self.presets = ScanPreset.builtIns
    }

    self.lastUsedDocumentMode =
      defaults.string(forKey: Key.lastUsedDocumentMode).flatMap(DocumentMode.init(rawValue:))
      ?? .text
    self.lastUsedDPI =
      defaults.object(forKey: Key.lastUsedDPI) != nil
      ? defaults.integer(forKey: Key.lastUsedDPI) : DocumentMode.text.defaultDPI
    self.lastUsedColorMode =
      defaults.string(forKey: Key.lastUsedColorMode).flatMap(ScanMode.init(rawValue:))
      ?? DocumentMode.text.defaultColorMode
  }

  private func persistPresets() {
    guard let data = try? JSONEncoder().encode(presets) else { return }
    defaults.set(data, forKey: Key.presets)
  }

  // MARK: - Preset management (DESIGN.md: "rename/delete/reorder")

  public func addPreset(_ preset: ScanPreset) {
    presets.append(preset)
  }

  public func renamePreset(id: UUID, to newName: String) {
    guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
    presets[index].name = newName
  }

  public func deletePreset(id: UUID) {
    presets.removeAll { $0.id == id }
  }

  public func movePresets(fromOffsets offsets: IndexSet, toOffset destination: Int) {
    presets.move(fromOffsets: offsets, toOffset: destination)
  }

  /// "Save as preset…" — snapshots the document's current mode/dpi/color into a new preset.
  @discardableResult
  public func savePreset(
    named name: String, documentMode: DocumentMode, dpi: Int, colorMode: ScanMode,
    imageFormat: ImageFormat
  ) -> ScanPreset {
    let preset = ScanPreset(
      name: name, documentMode: documentMode, dpi: dpi, colorMode: colorMode,
      imageFormat: imageFormat)
    addPreset(preset)
    return preset
  }

  /// Records the document's current live settings as "last used" — call whenever
  /// `DocumentSession`'s mode/dpi/color change, so a relaunch restores them.
  public func recordLastUsed(documentMode: DocumentMode, dpi: Int, colorMode: ScanMode) {
    lastUsedDocumentMode = documentMode
    lastUsedDPI = dpi
    lastUsedColorMode = colorMode
  }
}
