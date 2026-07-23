import SwiftUI

/// The single window's three regions (DESIGN.md): control strip, canvas, page strip — plus
/// the non-modal scanner banner and the "Save as preset…" sheet.
struct ContentView: View {
  let session: DocumentSession
  let settings: AppSettings
  let controller: ScanController
  let errorState: AppErrorState

  @State private var selectedPageID: PageEntry.ID?
  @State private var showSavePresetSheet = false
  @State private var newPresetName = ""

  var body: some View {
    VStack(spacing: 0) {
      ControlStripView(
        session: session, settings: settings, controller: controller,
        onScan: { controller.scan(into: session, settings: settings) },
        onSavePreset: {
          newPresetName = "\(session.documentMode.displayName) \(session.dpi)dpi"
          showSavePresetSheet = true
        }
      )
      .padding()
      // Soft grey-on-cream, not white — distinguishes the control strip from the canvas
      // below it the way a real toolbar region reads in Preview/Notes/Photos. `ChromeColor`,
      // not the bare semantic `.windowBackgroundColor` this used before: see its doc comment
      // for why the semantic color alone wasn't actually reading as grey on real hardware.
      .background(ChromeColor.background)

      Divider()

      HSplitView {
        CanvasView(controller: controller, displayedImage: displayedImage)
          .frame(minWidth: 420, minHeight: 420)
        if showsPageStrip {
          PageStripView(session: session, selectedPageID: $selectedPageID)
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 260)
            // Same chrome tone as the control strip (including the empty "No pages yet"
            // state) — the page strip is chrome around the document, not part of the page
            // content itself, so it shouldn't compete visually with the near-white canvas.
            .background(ChromeColor.background)
        }
      }

      if let banner = controller.banner {
        BannerView(
          banner: banner,
          retry: {
            controller.retry()
            controller.scan(into: session, settings: settings)
          },
          dismiss: { controller.retry() }
        )
      }
    }
    .frame(minWidth: 760, minHeight: 560)
    .sheet(isPresented: $showSavePresetSheet) {
      savePresetSheet
    }
    .alert(
      "Couldn't save",
      isPresented: Binding(
        get: { errorState.message != nil }, set: { if !$0 { errorState.message = nil } })
    ) {
      Button("OK") { errorState.message = nil }
    } message: {
      Text(errorState.message ?? "")
    }
    .onChange(of: session.documentMode) { _, _ in recordLastUsed() }
    .onChange(of: session.dpi) { _, _ in recordLastUsed() }
    .onChange(of: session.colorMode) { _, _ in recordLastUsed() }
  }

  private var showsPageStrip: Bool {
    session.pages.count > 1 || session.documentMode == .text
  }

  private var displayedImage: CGImage? {
    if let selectedPageID, let entry = session.pages.first(where: { $0.id == selectedPageID }) {
      return entry.page.image
    }
    return session.pages.last?.page.image
  }

  private var savePresetSheet: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Save as preset").font(.headline)
      TextField("Preset name", text: $newPresetName)
        .frame(width: 260)
      HStack {
        Spacer()
        Button("Cancel") { showSavePresetSheet = false }
        Button("Save") {
          // `session.currentImageFormat`, not a hardcoded `.jpeg` — DESIGN.md's preset
          // contract is "mode+dpi+color+format," so "Save as preset…" must capture
          // whatever format is actually active right now, not silently normalize every
          // user preset to JPEG regardless of what the user had selected.
          settings.savePreset(
            named: newPresetName, documentMode: session.documentMode, dpi: session.dpi,
            colorMode: session.colorMode, imageFormat: session.currentImageFormat)
          showSavePresetSheet = false
        }
        .keyboardShortcut(.defaultAction)
        .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(20)
  }

  private func recordLastUsed() {
    settings.recordLastUsed(
      documentMode: session.documentMode, dpi: session.dpi, colorMode: session.colorMode)
  }
}
