import Observation

/// Save-flow errors surfaced via `ContentView`'s alert. Separate from `ScanController`'s
/// scan-specific banner: save errors (disk full, permission denied, ...) come from a
/// synchronous NSSavePanel-driven flow triggered by ⌘S, not from the scan state machine.
@MainActor
@Observable
public final class AppErrorState {
  public var message: String?

  public init() {}
}
