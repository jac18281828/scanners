import SwiftUI

/// Mode toggle, inline dpi/color pickers (option sets swap per mode), preset chips, and the
/// big Scan button — DESIGN.md: "Current settings always visible, editable in place, no
/// drill-down to change dpi."
struct ControlStripView: View {
  let session: DocumentSession
  let settings: AppSettings
  let controller: ScanController
  let onScan: () -> Void
  let onSavePreset: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 16) {
        Picker(
          "",
          selection: Binding(
            get: { session.documentMode },
            // requestModeChange, not a plain assignment: switching modes with unsaved
            // pages needs the same confirm-or-block ⌘N already uses (DESIGN.md). If the
            // user declines, nothing changes and this binding's `get:` reads back the
            // still-current mode on the next render, so the Picker snaps back on its own.
            set: { session.requestModeChange(to: $0) })
        ) {
          ForEach(DocumentMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .labelsHidden()

        Picker("DPI", selection: Binding(get: { session.dpi }, set: { session.dpi = $0 })) {
          ForEach(session.documentMode.dpiOptions, id: \.self) { dpi in
            Text("\(dpi) dpi").tag(dpi)
          }
        }
        .frame(width: 140)

        Picker(
          "Color", selection: Binding(get: { session.colorMode }, set: { session.colorMode = $0 })
        ) {
          ForEach(DocumentMode.colorOptions, id: \.self) { mode in
            Text(mode == .color ? "Color" : "Black & White").tag(mode)
          }
        }
        .frame(width: 170)

        Spacer()

        Button {
          onScan()
        } label: {
          Label(controller.isScanning ? "Scanning…" : "Scan", systemImage: "scanner")
            .font(.headline)
            .padding(.horizontal, 4)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(controller.isScanning)
      }

      HStack(spacing: 8) {
        ForEach(settings.presets) { preset in
          Button(preset.name) {
            session.requestApplyPreset(preset)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        Button {
          onSavePreset()
        } label: {
          Label("Save as preset…", systemImage: "plus.circle")
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .foregroundStyle(.secondary)
      }
    }
  }
}
