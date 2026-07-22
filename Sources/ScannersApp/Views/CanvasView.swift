import SwiftUI

/// The current page preview at fit-to-window, or a determinate progress view driven by
/// `ScanEvent` while a scan is in flight — DESIGN.md's canvas region.
struct CanvasView: View {
  let controller: ScanController
  let displayedImage: CGImage?

  var body: some View {
    ZStack {
      // AppKit's own semantic color for "the backdrop behind a page in a canvas/preview
      // interface" (Preview.app uses the same one) — a soft grey, not white. The scanned
      // page itself gets a distinct white card on top of it below, which is where the
      // near-white contrast John wants actually belongs: on the page, not the canvas.
      Color(nsColor: .underPageBackgroundColor)
      switch controller.scanState {
      case .idle:
        if let displayedImage {
          Image(decorative: displayedImage, scale: 1, orientation: .up)
            .resizable()
            // SwiftUI's default downscale filter looks dithered/blocky on a high-res
            // scan shrunk to fit-to-window — match CoreGraphics' own `.high`
            // interpolation quality (what PageNormalizer already uses for the real
            // pixel data) so the on-screen preview reads as smooth, not pixelated.
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .background(Color.white)
            .shadow(radius: 6, y: 2)
            .padding(24)
        } else {
          ContentUnavailableView(
            "No pages yet", systemImage: "doc.viewfinder",
            description: Text("Press Return or ⌘R to scan."))
        }
      case .discovering:
        ProgressView("Looking for scanner…")
      case .scanning(let progress):
        VStack(spacing: 16) {
          ProgressView(value: progress) {
            Text("Scanning… \(Int((progress * 100).rounded()))%")
          }
          .frame(maxWidth: 280)
          Button("Cancel", role: .cancel) {
            controller.cancelScan()
          }
        }
      }
    }
  }
}
