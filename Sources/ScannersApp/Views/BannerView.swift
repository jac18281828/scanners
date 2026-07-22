import SwiftUI

/// Non-modal inline banner for scanner unplugged/busy — DESIGN.md: "never a blocking alert
/// loop." Sits at the bottom of the window; a Retry button re-enumerates rather than the
/// app polling on its own.
struct BannerView: View {
  let banner: ScanController.Banner
  let retry: () -> Void
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(banner.message)
        .font(.callout)
      Spacer()
      if banner.isRetryable {
        Button("Retry", action: retry)
      }
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.orange.opacity(0.12))
    .overlay(Divider(), alignment: .top)
  }
}
