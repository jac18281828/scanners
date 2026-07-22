import AppKit
import Foundation

/// Thin `NSOpenPanel` wrapper for choosing the default save folder in Settings. Same
/// "dumb AppKit, no logic worth testing" split as `SavePanel`.
@MainActor
struct NSOpenPanelBridge {
  func chooseFolder(startingAt url: URL) -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Choose Save Folder"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = url
    return panel.runModal() == .OK ? panel.url : nil
  }
}
