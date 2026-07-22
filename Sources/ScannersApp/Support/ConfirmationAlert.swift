import AppKit

/// A blocking confirmation for the places DESIGN.md explicitly wants one: ⌘N with unsaved
/// pages ("confirm if unsaved pages exist, then reset session"), and — same contract,
/// reusing this exact mechanism — `DocumentSession.requestModeChange`/`requestApplyPreset`
/// switching modes with unsaved pages. Distinct from the non-modal inline banner used for
/// scanner-unplugged/busy.
///
/// `public`, not `internal`: `DocumentSession`'s `public` `requestModeChange`/
/// `requestApplyPreset` reference `confirmDiscardUnsavedChanges` as a default argument
/// value, and a default argument expression must be at least as visible as the function
/// it defaults for.
@MainActor
public enum ConfirmationAlert {
  /// Returns `true` if the user chose to discard the unsaved pages and proceed.
  public static func confirmDiscardUnsavedChanges() -> Bool {
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
