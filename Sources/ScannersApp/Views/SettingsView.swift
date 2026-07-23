import ScannerKit
import SwiftUI

/// DESIGN.md's Settings pane (⌘,): "preset management (rename/delete/reorder), default save
/// folder, filename template, source (Flatbed/ADF), lamp-timeout toggle[, OCR language
/// (default English)]. One compact pane; no tabs unless it genuinely won't fit." It fits.
struct SettingsView: View {
  let settings: AppSettings
  @State private var renamingPresetID: ScanPreset.ID?
  @State private var renameText = ""

  var body: some View {
    Form {
      Section("Presets") {
        List {
          ForEach(settings.presets) { preset in
            presetRow(preset)
          }
          .onMove { offsets, destination in
            settings.movePresets(fromOffsets: offsets, toOffset: destination)
          }
        }
        .frame(minHeight: 120, maxHeight: 200)
      }

      Section("Scanning") {
        Picker(
          "Source", selection: Binding(get: { settings.source }, set: { settings.source = $0 })
        ) {
          Text("Flatbed").tag(ScanSource.flatbed)
          Text("ADF").tag(ScanSource.adf)
        }
        Toggle(
          "Extend lamp timeout (15 min → 1 hour)",
          isOn: Binding(
            get: { settings.extendLampTimeout }, set: { settings.extendLampTimeout = $0 }))
        TextField(
          "OCR language (BCP-47)",
          text: Binding(get: { settings.ocrLanguage }, set: { settings.ocrLanguage = $0 }))
      }

      Section("Files") {
        HStack {
          Text(settings.saveFolder.path)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Choose…") { chooseSaveFolder() }
        }
        HStack {
          Text("Filename prefix")
          TextField(
            "scan",
            text: Binding(get: { settings.filenamePrefix }, set: { settings.filenamePrefix = $0 })
          )
          .frame(width: 140)
        }
        Text("Example: \(DocumentExporter.suggestedFilename(ext: "pdf", settings: settings))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    // .grouped: the soft inset-grey look System Settings.app itself uses, rather than
    // Form's plain/flat default — matches the rest of the window's grey-on-cream
    // hierarchy instead of reading as a stray white sheet. `ChromeColor`, not the bare
    // semantic `.windowBackgroundColor` — see its doc comment.
    .formStyle(.grouped)
    .padding(20)
    .frame(width: 420)
    .background(ChromeColor.background)
  }

  @ViewBuilder
  private func presetRow(_ preset: ScanPreset) -> some View {
    HStack {
      if renamingPresetID == preset.id {
        TextField(
          "Name", text: $renameText,
          onCommit: {
            settings.renamePreset(id: preset.id, to: renameText)
            renamingPresetID = nil
          }
        )
      } else {
        Text(preset.name)
        Spacer()
        Text("\(preset.documentMode.displayName) · \(preset.dpi)dpi")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Rename") {
          renameText = preset.name
          renamingPresetID = preset.id
        }
        .buttonStyle(.plain)
        .font(.caption)
        Button(role: .destructive) {
          settings.deletePreset(id: preset.id)
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func chooseSaveFolder() {
    let panel = NSOpenPanelBridge()
    if let url = panel.chooseFolder(startingAt: settings.saveFolder) {
      settings.saveFolder = url
    }
  }
}
