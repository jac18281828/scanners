import Foundation
import SwiftUI

/// The SwiftUI app root. Not `@main` — `main.swift` calls `ScannersAppRoot.main()` directly
/// (SwiftPM executable targets can't mix a `main.swift` top-level-code file with an `@main`
/// type in the same target) so `Scripts/run-dev.sh`/`swift run ScannersApp` keep working
/// unchanged.
///
/// `SCANNERS_MOCK=1` selects `ScannerBackendMode.mock` — DESIGN.md's Phase 5 architecture
/// note: "the app runs against MockSane via a `SCANNERS_MOCK=1` env var — used for UI
/// development and UI tests without hardware." Real hardware (`.real`) is the default so a
/// plain `swift run ScannersApp` with no env var talks to the actual HP 4570c.
struct ScannersAppRoot: App {
  @State private var session = DocumentSession()
  @State private var settings = AppSettings()
  @State private var controller: ScanController
  @State private var errorState = AppErrorState()

  init() {
    let mock = ProcessInfo.processInfo.environment["SCANNERS_MOCK"] == "1"
    _controller = State(initialValue: ScanController(backendMode: mock ? .mock : .real))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(
        session: session, settings: settings, controller: controller, errorState: errorState
      )
      .onAppear(perform: restoreLastUsedSettings)
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Document") { newDocument() }
          .keyboardShortcut("n", modifiers: .command)
      }
      CommandGroup(replacing: .saveItem) {
        Button(session.documentMode == .text ? "Save PDF…" : "Save Image…") { saveCurrent() }
          .keyboardShortcut("s", modifiers: .command)
          .disabled(session.pages.isEmpty)
      }
      CommandMenu("Scan") {
        Button("Scan") { controller.scan(into: session, settings: settings) }
          .keyboardShortcut("r", modifiers: .command)
          .disabled(controller.isScanning)
      }
    }

    Settings {
      SettingsView(settings: settings)
    }
  }

  private func restoreLastUsedSettings() {
    session.documentMode = settings.lastUsedDocumentMode
    session.dpi = settings.lastUsedDPI
    session.colorMode = settings.lastUsedColorMode
  }

  private func newDocument() {
    if session.hasUnsavedChanges {
      guard ConfirmationAlert.confirmDiscardUnsavedChanges() else { return }
    }
    session.reset()
  }

  private func saveCurrent() {
    do {
      switch session.documentMode {
      case .text:
        _ = try DocumentExporter.savePDF(session: session, settings: settings)
      case .image:
        _ = try DocumentExporter.saveImage(session: session, settings: settings)
      }
    } catch {
      errorState.message = String(describing: error)
    }
  }
}
