import AppKit
import Foundation

/// Thin `NSSavePanel` wrappers for the two save flows. Kept dumb and untested (no display in
/// CI) on purpose — `DocumentExporter` holds every piece of save-flow logic worth testing
/// (PDF assembly, filename suggestion) independent of these panels ever appearing.
@MainActor
enum SavePanel {
  static func presentPDFPanel(suggestedName: String, directory: URL) -> URL? {
    let panel = NSSavePanel()
    panel.title = "Save PDF"
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = suggestedName
    panel.directoryURL = directory
    panel.canCreateDirectories = true
    return panel.runModal() == .OK ? panel.url : nil
  }

  /// DESIGN.md: "format picker in the save panel (JPEG default, PNG/TIFF/HEIC)." Returns
  /// the chosen URL and whichever format the accessory popup landed on.
  static func presentImagePanel(
    suggestedBaseName: String, directory: URL, defaultFormat: ImageFormat
  ) -> (url: URL, format: ImageFormat)? {
    let panel = NSSavePanel()
    let accessory = ImageFormatAccessory(
      panel: panel, baseName: suggestedBaseName, initial: defaultFormat)
    panel.title = "Save Image"
    panel.accessoryView = accessory.view
    panel.allowedContentTypes = [defaultFormat.utType]
    panel.nameFieldStringValue = "\(suggestedBaseName).\(defaultFormat.fileExtension)"
    panel.directoryURL = directory
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return (url, accessory.selectedFormat)
  }
}

/// Owns the format `NSPopUpButton` in the image save panel's accessory view and updates the
/// panel's allowed type/filename extension live as the selection changes. Plain AppKit
/// target/action — one popup doesn't need a SwiftUI-hosted accessory.
@MainActor
private final class ImageFormatAccessory: NSObject {
  private weak var panel: NSSavePanel?
  private let baseName: String
  private(set) var selectedFormat: ImageFormat
  let view: NSView

  init(panel: NSSavePanel, baseName: String, initial: ImageFormat) {
    self.panel = panel
    self.baseName = baseName
    self.selectedFormat = initial

    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 140, height: 24), pullsDown: false)
    popup.addItems(withTitles: ImageFormat.allCases.map(\.displayName))
    popup.selectItem(withTitle: initial.displayName)

    let label = NSTextField(labelWithString: "Format:")
    let stack = NSStackView(views: [label, popup])
    stack.orientation = .horizontal
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
    self.view = stack

    super.init()
    popup.target = self
    popup.action = #selector(formatChanged(_:))
  }

  @objc private func formatChanged(_ sender: NSPopUpButton) {
    guard let title = sender.titleOfSelectedItem,
      let format = ImageFormat.allCases.first(where: { $0.displayName == title })
    else { return }
    selectedFormat = format
    panel?.allowedContentTypes = [format.utType]
    panel?.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
  }
}
