import Testing

@testable import OutputKit
@testable import ScannerKit

@Suite("PageNormalizer")
struct PageNormalizerTests {
  @Test("100dpi hardware scan downscaled to a 75dpi request: 850px -> 637px width")
  func downscale100to75() {
    // 215.889mm at 100dpi (the real hp5590 max scan width, DESIGN.md) -> 850x1169px
    // hardware image; requested 75dpi. Physical-mm basis: 215.889/25.4*75 = 637.47 -> 637.
    let widthMM = 215.889
    let heightMM = 297.699
    let hardwareWidth = Int((widthMM / 25.4 * 100).rounded())
    let hardwareHeight = Int((heightMM / 25.4 * 100).rounded())
    #expect(hardwareWidth == 850)

    let size = Fixtures.PageSize(
      widthPixels: hardwareWidth,
      heightPixels: hardwareHeight,
      widthMM: widthMM,
      heightMM: heightMM
    )
    let page = Fixtures.solidPage(size: size, requestedDPI: 75, hardwareDPI: 100)

    let normalized = PageNormalizer.normalize(page)
    #expect(normalized.image.width == 637)
    // Phase-0 hardware observation was 638±1 on the real device; 637 is within that band.
    #expect(abs(normalized.image.height - Int((heightMM / 25.4 * 75).rounded())) <= 1)
  }

  @Test("requestedDPI == hardwareDPI is a no-op (same CGImage instance)")
  func noOpWhenEqual() {
    let size = Fixtures.PageSize(
      widthPixels: 300, heightPixels: 300, widthMM: 76.2, heightMM: 76.2)
    let page = Fixtures.solidPage(size: size, requestedDPI: 100, hardwareDPI: 100)
    let normalized = PageNormalizer.normalize(page)
    #expect(normalized.image === page.image)
  }

  @Test("requestedDPI above the clamped max hardwareDPI is left alone, not upscaled")
  func noOpWhenRequestedAboveHardware() {
    // Mirrors ResolutionPolicy's clamp: a request above the largest native dpi leaves
    // hardwareDPI < requestedDPI. Nothing to downscale to — normalize must not try to
    // invent detail that was never scanned.
    let size = Fixtures.PageSize(
      widthPixels: 300, heightPixels: 300, widthMM: 76.2, heightMM: 76.2)
    let page = Fixtures.solidPage(size: size, requestedDPI: 5000, hardwareDPI: 2400)
    let normalized = PageNormalizer.normalize(page)
    #expect(normalized.image === page.image)
  }

  @Test("effectiveDPI reflects actual pixel density, not the stored dpi fields")
  func effectiveDPIFromPixels() {
    let widthMM = 215.889
    let size = Fixtures.PageSize(
      widthPixels: 850, heightPixels: 1169, widthMM: widthMM, heightMM: 297.699)
    let page = Fixtures.solidPage(size: size, requestedDPI: 75, hardwareDPI: 100)
    let normalized = PageNormalizer.normalize(page)
    #expect(PageNormalizer.effectiveDPI(normalized) == 75)
  }

  @Test("downscaled color image keeps its shape (RGB, no crash) at the new size")
  func downscaleColorImage() {
    let size = Fixtures.PageSize(
      widthPixels: 1200, heightPixels: 1200, widthMM: 101.6, heightMM: 101.6)
    let page = Fixtures.solidPage(size: size, requestedDPI: 150, hardwareDPI: 300, mode: .color)
    let normalized = PageNormalizer.normalize(page)
    #expect(normalized.image.width == 600)
    #expect(normalized.image.height == 600)
  }
}
