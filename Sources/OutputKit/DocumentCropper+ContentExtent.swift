import CoreGraphics
import CoreImage
import ScannerKit

// MARK: - Content extent (Vision-independent fallback)

extension DocumentCropper {
  /// Vision-independent fallback for when `detectDocument`'s confidence gate fails -- which, on
  /// this app's actual hardware (white paper against a similarly pale platen lid), is every real
  /// scan tested during development, not an occasional miss. `VNDetectDocumentSegmentationRequest`
  /// needs page-vs-background contrast to report anything; this instead works from the page's
  /// own printed content (text, graphics -- anything dark enough to register), which stays
  /// reliably high-contrast against white paper regardless of platen lighting.
  ///
  /// Straightens via `estimateSkew` before finding the content box (see `straightened` below) --
  /// the same projection-profile analysis the confident-Vision path already trusts, gated the
  /// same way (`SkewEstimate.confident`). An earlier version of this fallback used a bespoke
  /// border-line estimator (sample the page's physical edge shadow in a thin band near the
  /// image's top/bottom border, on the theory that a physical-edge signal can't be fooled by a
  /// crooked sticker the way whole-page content orientation can). That measured well in
  /// isolation but turned out to be reading a scanner bed-frame artifact, not the page: on this
  /// hardware the artifact is a 1-2px sliver confined to the image's absolute bottom-left corner
  /// (verified against a real scan: matched points spanned only the leftmost ~17% of the width,
  /// in the buffer's literal last two rows), always near 0°, so the estimator confidently
  /// reported "no rotation" on every scan regardless of the page's true tilt -- the exact
  /// "thin sliver hugging the border" signature `dropBorderSlivers` already exists to exclude
  /// elsewhere in this file, which the border-line path never applied. `estimateSkew` doesn't
  /// have this failure mode (verified against the same real scan: it recovers the page's actual
  /// ~4° tilt with high confidence) and its sticker-page caveat is exactly the case this
  /// fallback needs to stay conservative about -- `maximumSecondPeakRatio` rejects a page with a
  /// competing high-contrast sub-region the same way it already does on the confident-Vision
  /// path.
  static func contentExtentCrop(_ page: ScannedPage) -> ScannedPage {
    let workingImage = straightened(page.image) ?? page.image
    guard let box = contentExtentBox(workingImage) else { return page }
    let extent = CGRect(x: 0, y: 0, width: workingImage.width, height: workingImage.height)
    let paddingPixels = contentExtentPaddingMM / 25.4 * Double(page.hardwareDPI)
    let padded = box.insetBy(dx: -paddingPixels, dy: -paddingPixels).intersection(extent)
    guard !padded.isEmpty else { return page }

    // The box's own corners are the crop -- reuses `boundingBoxCrop` exactly as the
    // confident-Vision path does, just fed an axis-aligned box instead of a Vision quad. Any
    // rotation was already applied by `straightened` above, so this stays axis-aligned.
    let corners = PixelCorners(
      topLeft: CGPoint(x: padded.minX, y: padded.maxY),
      topRight: CGPoint(x: padded.maxX, y: padded.maxY),
      bottomLeft: CGPoint(x: padded.minX, y: padded.minY),
      bottomRight: CGPoint(x: padded.maxX, y: padded.minY))
    guard let corrected = boundingBoxCrop(workingImage, corners: corners, imageExtent: extent)
    else {
      return page
    }
    return repackaged(page, corrected: corrected) ?? page
  }

  /// Straightens `image` via `estimateSkew` before extent analysis -- nil (no rotation applied,
  /// `contentExtentCrop` falls back to the original image) if the profile search isn't confident
  /// (see `SkewEstimate.confident`), the angle is a no-op, or the rotation transform itself
  /// degenerates. `contentExtentBox` and the padding/crop then run against the corrected image,
  /// so the final crop is both tight and upright, not just tight.
  private static func straightened(_ image: CGImage) -> CGImage? {
    let skew = estimateSkew(image)
    guard skew.confident, skew.angleDegrees != 0 else { return nil }
    return rotated(image, byDegrees: skew.angleDegrees)
  }

  /// Rotates `image` about its own center by `degrees` (standard CCW-positive convention),
  /// compositing over white so the corners a rotation exposes read as blank platen rather than
  /// transparent/undefined pixels -- important because the result feeds straight into
  /// `contentExtentBox`'s darkness analysis, where an undefined corner pixel could register as
  /// false content. `degrees` is applied directly, not negated: `estimateSkew`'s angle already
  /// *is* the correction, verified empirically against a synthetic known-tilt image rather than
  /// assumed -- its search runs in image-buffer row-down coordinates, the opposite sense from
  /// Core Image's own y-up space, and the two negations cancel. (`SkewEstimate.angleDegrees`'s
  /// own doc comment warns its sign is "the search's own projection convention" and until now
  /// was only ever consumed via `abs()` on the confident-Vision path -- this is the first caller
  /// to apply it as a real rotation, so the sign needed checking, not assuming.)
  static func rotated(_ image: CGImage, byDegrees degrees: Double) -> CGImage? {
    let radians = degrees * .pi / 180
    let source = CIImage(cgImage: image)
    let centerX = source.extent.midX
    let centerY = source.extent.midY
    let transform =
      CGAffineTransform(translationX: centerX, y: centerY)
      .rotated(by: CGFloat(radians))
      .translatedBy(x: -centerX, y: -centerY)
    let turned = source.transformed(by: transform)
    guard let filter = CIFilter(name: "CISourceOverCompositing") else { return nil }
    let background = CIImage(color: .white).cropped(to: turned.extent)
    filter.setValue(turned, forKey: kCIInputImageKey)
    filter.setValue(background, forKey: kCIInputBackgroundImageKey)
    guard let composited = filter.outputImage else { return nil }
    return CIContext().createCGImage(composited, from: composited.extent)
  }

  /// The tight axis-aligned box, in `image`'s own full-resolution pixel coordinates, around
  /// whatever registers as content. Analyzed on a downsampled copy for speed (extent is a
  /// coarse, global property, same reasoning as `estimateSkew`'s own downsampling) and scaled
  /// back up. `nil` on a blank scan -- nothing to crop to, `contentExtentCrop` keeps the page
  /// unchanged rather than guess, the same "never fails or guesses" rule as `minimumConfidence`.
  static func contentExtentBox(_ image: CGImage) -> CGRect? {
    guard let gray = grayscaleBuffer(image, maxDimension: contentExtentAnalysisMaxDimension)
    else {
      return nil
    }
    let rawMask = gray.pixels.map { $0 < contentDarknessThreshold }
    let denoised = denoiseContentMask(
      rawMask, width: gray.width, height: gray.height,
      minComponentPixels: contentDenoiseMinComponentPixels)

    // Component size alone doesn't separate real content from an isolated artifact -- a
    // platen-edge shadow fragment or a printed color bar can be as large as a real word (both
    // measured in the same tens-to-hundreds-of-pixels range against real scans). What actually
    // distinguishes a shadow/stripe artifact, empirically (measured against real scans): it's a
    // *thin sliver* hugging the exact capture-frame border -- 1-4px in its short dimension,
    // because it's tracing a physical edge -- whereas real content that happens to sit near the
    // border (a photo or graphic printed close to the page edge, since the page nearly fills the
    // bed) is substantial in both dimensions. `dropBorderSlivers` removes only components that
    // are both: touching the border, AND thin. It does not require content to form one
    // contiguous mass -- a header block and a body block separated by normal paragraph spacing
    // both survive, unlike a single-largest-cluster approach (tried and rejected: it discarded
    // a real header section separated from the body by a gap wider than reasonable word/line
    // spacing).
    let mask = dropBorderSlivers(denoised, width: gray.width, height: gray.height)

    var minX = Int.max
    var maxX = Int.min
    var minRow = Int.max
    var maxRow = Int.min
    for y in 0..<gray.height {
      for x in 0..<gray.width where mask[y * gray.width + x] {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minRow = min(minRow, y)
        maxRow = max(maxRow, y)
      }
    }
    guard minX <= maxX else { return nil }

    // `grayscaleBuffer` draws top-down (row 0 = the image's CG-coordinate top -- verified
    // empirically, not assumed), but this file's pixel space is CG's bottom-left-origin, y-up
    // (see `pixelCorners`'s doc comment). Flip row indices to CG y before scaling back up.
    let flippedMinY = gray.height - 1 - maxRow
    let flippedMaxY = gray.height - 1 - minRow

    let scaleX = Double(image.width) / Double(gray.width)
    let scaleY = Double(image.height) / Double(gray.height)
    return CGRect(
      x: Double(minX) * scaleX, y: Double(flippedMinY) * scaleY,
      width: Double(maxX - minX) * scaleX, height: Double(flippedMaxY - flippedMinY) * scaleY)
  }

  /// Connected-component denoise (4-connectivity flood fill), not a local neighbor count: a
  /// content pixel only survives if its whole connected region has at least
  /// `contentDenoiseMinComponentPixels` pixels. A local 3x3-neighborhood filter was tried first
  /// and rejected -- it's systematically *weaker* right at the frame border (a border pixel has
  /// fewer neighbors to begin with, so the same absolute "N dark neighbors" threshold is easier
  /// to satisfy proportionally), which is exactly where scan-edge shadow remnants and JPEG
  /// artifacts concentrate; confirmed against a real scan where it let border noise survive and
  /// blew the box back out to the full frame. Component size doesn't have that bias: a genuine
  /// character survives regardless of where it sits (real components measured 13-180px at this
  /// analysis resolution against real scans, several times the cutoff), while an isolated speck
  /// -- wherever it is -- does not.
  private static func denoiseContentMask(
    _ mask: [Bool], width: Int, height: Int, minComponentPixels: Int
  ) -> [Bool] {
    let (labels, sizes) = connectedComponents(mask, width: width, height: height)
    var out = [Bool](repeating: false, count: width * height)
    for index in labels.indices {
      let label = labels[index]
      guard label != -1, sizes[label] >= minComponentPixels else { continue }
      out[index] = true
    }
    return out
  }

  /// Drops components that are both touching the analysis frame's border AND a thin sliver in
  /// their short dimension (`contentExtentSliverMaxThickness` or less) -- the empirical
  /// signature of a platen-edge shadow fragment or scan-frame artifact, which traces a physical
  /// edge and so is long in one direction but only a few pixels in the other. Real content that
  /// happens to sit near the border (a photo or graphic printed close to the page edge) is
  /// substantial in both dimensions and survives untouched.
  private static func dropBorderSlivers(
    _ mask: [Bool], width: Int, height: Int
  ) -> [Bool] {
    let (labels, sizes) = connectedComponents(mask, width: width, height: height)
    var bounds = [(minX: Int, maxX: Int, minY: Int, maxY: Int)](
      repeating: (width, -1, height, -1), count: sizes.count)
    for index in labels.indices {
      let label = labels[index]
      guard label != -1 else { continue }
      let x = index % width
      let y = index / width
      bounds[label].minX = min(bounds[label].minX, x)
      bounds[label].maxX = max(bounds[label].maxX, x)
      bounds[label].minY = min(bounds[label].minY, y)
      bounds[label].maxY = max(bounds[label].maxY, y)
    }
    var isSliver = [Bool](repeating: false, count: sizes.count)
    for label in bounds.indices {
      let box = bounds[label]
      let touchesBorder =
        box.minX == 0 || box.maxX == width - 1 || box.minY == 0 || box.maxY == height - 1
      let thickness = min(box.maxX - box.minX, box.maxY - box.minY) + 1
      isSliver[label] = touchesBorder && thickness <= contentExtentSliverMaxThickness
    }
    var out = [Bool](repeating: false, count: width * height)
    for index in labels.indices {
      let label = labels[index]
      guard label != -1, !isSliver[label] else { continue }
      out[index] = true
    }
    return out
  }

  /// Plain 4-connectivity component labeling, shared by `denoiseContentMask` (size filter) and
  /// `dropBorderSlivers` (shape filter).
  private static func connectedComponents(
    _ mask: [Bool], width: Int, height: Int
  ) -> (labels: [Int], sizes: [Int]) {
    var labels = [Int](repeating: -1, count: width * height)
    var sizes: [Int] = []
    var stack: [Int] = []
    for start in mask.indices {
      guard mask[start], labels[start] == -1 else { continue }
      let label = sizes.count
      var size = 0
      stack.append(start)
      labels[start] = label
      while let index = stack.popLast() {
        size += 1
        let x = index % width
        let y = index / width
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
          let nx = x + dx
          let ny = y + dy
          guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
          let neighborIndex = ny * width + nx
          if mask[neighborIndex] && labels[neighborIndex] == -1 {
            labels[neighborIndex] = label
            stack.append(neighborIndex)
          }
        }
      }
      sizes.append(size)
    }
    return (labels, sizes)
  }
}
