import AppKit

/// A blocking confirmation for the one place DESIGN.md explicitly wants a modal: ⌘N with
/// unsaved pages ("confirm if unsaved pages exist, then reset session"). Distinct from the
/// non-modal inline banner used for scanner-unplugged/busy.
@MainActor
enum ConfirmationAlert {
  /// Returns `true` if the user chose to discard the unsaved pages and proceed.
  static func confirmDiscardUnsavedChanges() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Discard unsaved pages?"
    alert.informativeText =
      "Starting a new document discards the pages you haven't saved yet."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "New Document")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}
