import SwiftUI

/// Thumbnails of scanned pages — drag to reorder, delete on hover/backspace. DESIGN.md:
/// "Visible only when the session has >1 page or mode is Text."
struct PageStripView: View {
  let session: DocumentSession
  @Binding var selectedPageID: PageEntry.ID?

  var body: some View {
    List(selection: $selectedPageID) {
      ForEach(session.pages) { entry in
        PageThumbnailRow(entry: entry) {
          session.removePage(id: entry.id)
        }
        .tag(entry.id)
      }
      .onMove { offsets, destination in
        session.movePages(fromOffsets: offsets, toOffset: destination)
      }
    }
    .listStyle(.sidebar)
    // `.sidebar` style's vibrant grey backing normally comes from being hosted inside a
    // NavigationSplitView; standing alone in an HSplitView it renders flat/white instead.
    // Hide the List's own background and let `ChromeColor.background` (ContentView puts it
    // behind this view) show through instead, so it still reads as a sidebar — including in
    // the empty "No pages yet" state, which is exactly what was flat white before that color
    // existed.
    .scrollContentBackground(.hidden)
    .onDeleteCommand {
      guard let selectedPageID else { return }
      session.removePage(id: selectedPageID)
      self.selectedPageID = nil
    }
  }
}

private struct PageThumbnailRow: View {
  let entry: PageEntry
  let onDelete: () -> Void
  @State private var isHovering = false

  var body: some View {
    HStack {
      Image(decorative: entry.page.image, scale: 1, orientation: .up)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 60, height: 78)
        .background(.white)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.separator))

      VStack(alignment: .leading, spacing: 2) {
        Text("\(entry.page.image.width)×\(entry.page.image.height)px")
          .font(.caption)
        ocrStatusLabel
      }

      Spacer()

      if isHovering {
        Button(action: onDelete) {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
    .onHover { isHovering = $0 }
  }

  @ViewBuilder
  private var ocrStatusLabel: some View {
    switch entry.ocrStatus {
    case .notNeeded:
      EmptyView()
    case .pending:
      Label("OCR…", systemImage: "text.viewfinder")
        .font(.caption2)
        .foregroundStyle(.secondary)
    case .done:
      Label("OCR ready", systemImage: "checkmark.circle")
        .font(.caption2)
        .foregroundStyle(.secondary)
    case .failed:
      Label("OCR failed", systemImage: "exclamationmark.circle")
        .font(.caption2)
        .foregroundStyle(.orange)
    }
  }
}
