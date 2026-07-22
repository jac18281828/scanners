import Foundation
import ScannerKit
import Testing

@testable import ScannersApp

@Suite("AppSettings")
@MainActor
struct AppSettingsTests {
  @Test("first launch (empty defaults) seeds the three DESIGN.md built-in presets")
  func firstLaunchSeedsBuiltInPresets() {
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    #expect(settings.presets.map(\.name) == ["Text Doc", "Photo", "Archive"])
  }

  @Test("scalar settings round-trip through UserDefaults across a fresh AppSettings instance")
  func scalarSettingsPersistenceRoundTrip() {
    let defaults = TestFixtures.isolatedDefaults()
    let first = AppSettings(defaults: defaults)
    first.source = .adf
    first.extendLampTimeout = true
    first.ocrLanguage = "fr-FR"
    first.filenamePrefix = "invoice"
    first.saveFolder = URL(fileURLWithPath: "/tmp/scanners-settings-test")

    let second = AppSettings(defaults: defaults)

    #expect(second.source == .adf)
    #expect(second.extendLampTimeout)
    #expect(second.ocrLanguage == "fr-FR")
    #expect(second.filenamePrefix == "invoice")
    #expect(second.saveFolder.path == "/tmp/scanners-settings-test")
  }

  @Test("presets round-trip through UserDefaults across a fresh AppSettings instance")
  func presetsPersistenceRoundTrip() {
    let defaults = TestFixtures.isolatedDefaults()
    let first = AppSettings(defaults: defaults)
    let custom = first.savePreset(
      named: "My Custom", documentMode: .text, dpi: 600, colorMode: .color, imageFormat: .png)

    let second = AppSettings(defaults: defaults)

    #expect(second.presets.count == 4)
    #expect(second.presets.last?.id == custom.id)
    #expect(second.presets.last?.name == "My Custom")
    #expect(second.presets.last?.dpi == 600)
    #expect(second.presets.last?.colorMode == .color)
    #expect(second.presets.last?.imageFormat == .png)
  }

  @Test("last-used mode/dpi/color round-trip through UserDefaults")
  func lastUsedPersistenceRoundTrip() {
    let defaults = TestFixtures.isolatedDefaults()
    let first = AppSettings(defaults: defaults)
    first.recordLastUsed(documentMode: .image, dpi: 2400, colorMode: .color)

    let second = AppSettings(defaults: defaults)

    #expect(second.lastUsedDocumentMode == .image)
    #expect(second.lastUsedDPI == 2400)
    #expect(second.lastUsedColorMode == .color)
  }

  @Test("renamePreset renames only the targeted preset")
  func renamePresetRenamesTarget() {
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let target = settings.presets[0]

    settings.renamePreset(id: target.id, to: "Renamed")

    #expect(settings.presets[0].name == "Renamed")
    #expect(settings.presets[1].name == "Photo")
  }

  @Test("deletePreset removes exactly the targeted preset")
  func deletePresetRemovesTarget() {
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let target = settings.presets[1]

    settings.deletePreset(id: target.id)

    #expect(settings.presets.count == 2)
    #expect(settings.presets.contains { $0.id == target.id } == false)
  }

  @Test("movePresets reorders the preset list")
  func movePresetsReorders() {
    let settings = AppSettings(defaults: TestFixtures.isolatedDefaults())
    let ids = settings.presets.map(\.id)

    settings.movePresets(fromOffsets: [0], toOffset: 3)

    #expect(settings.presets.map(\.id) == [ids[1], ids[2], ids[0]])
  }
}
