import CoreGraphics

// MARK: - Skew analysis (projection profile)

extension DocumentCropper {
  /// The projection-profile search result: the best angle and the two trust metrics.
  /// `angleDegrees`' sign is the search's own projection convention (opposite Vision's); only
  /// its magnitude is used downstream, so callers compare `abs(angleDegrees)`.
  struct SkewEstimate {
    let angleDegrees: Double
    let contrast: Double
    let secondPeakRatio: Double

    /// A clean, well-defined peak: high above the noise floor with no comparable competitor.
    var confident: Bool {
      contrast >= minimumSkewContrast && secondPeakRatio <= maximumSecondPeakRatio
    }
  }

  /// Finds the document's dominant skew by projection-profile analysis (Radon-transform-style):
  /// at the true rotation, projecting edge energy onto an axis gives the sharpest profile; at
  /// wrong angles it blurs out. The `SkewEstimate` carries the winning angle's height above the
  /// median (`contrast`) and the best competing peak (`secondPeakRatio`) — confidence, not just
  /// the fit, per decision #9's ±30° addendum. Deterministic (no Vision), so tests drive it.
  static func estimateSkew(_ image: CGImage) -> SkewEstimate {
    guard let gray = grayscaleBuffer(image, maxDimension: skewAnalysisMaxDimension) else {
      return SkewEstimate(angleDegrees: 0, contrast: 0, secondPeakRatio: 1)
    }
    let edges = gradientMagnitude(gray)

    var angles: [Double] = []
    var scores: [Double] = []
    var angle = -skewSearchLimitDegrees
    while angle <= skewSearchLimitDegrees + 1e-9 {
      angles.append(angle)
      scores.append(profileSharpness(edges, thetaDegrees: angle))
      angle += skewSearchStepDegrees
    }
    guard !scores.isEmpty else {
      return SkewEstimate(angleDegrees: 0, contrast: 0, secondPeakRatio: 1)
    }

    var bestIndex = 0
    for index in scores.indices where scores[index] > scores[bestIndex] {
      bestIndex = index
    }
    let bestAngle = angles[bestIndex]
    let peak = scores[bestIndex]
    let median = scores.sorted()[scores.count / 2]

    var competitor = 0.0
    for index in scores.indices
    where abs(angles[index] - bestAngle) > peakSeparationDegrees && scores[index] > competitor {
      competitor = scores[index]
    }

    return SkewEstimate(
      angleDegrees: bestAngle, contrast: peak / max(median, 1e-9),
      secondPeakRatio: competitor / max(peak, 1e-9))
  }

  /// A downsampled single-channel (0...1) view of `image`, longest edge `maxDimension`. Not
  /// `private` -- `DocumentCropper+ContentExtent.swift` reuses it too.
  static func grayscaleBuffer(
    _ image: CGImage, maxDimension: Int
  ) -> (width: Int, height: Int, pixels: [Float])? {
    let scale = min(1.0, Double(maxDimension) / Double(max(image.width, image.height)))
    let width = max(1, Int(Double(image.width) * scale))
    let height = max(1, Int(Double(image.height) * scale))
    var bytes = [UInt8](repeating: 0, count: width * height)
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
      guard
        let context = CGContext(
          data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else {
        return false
      }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drew else { return nil }
    return (width, height, bytes.map { Float($0) / 255 })
  }

  /// Sobel gradient magnitude — the edge-energy map the sweep runs over. Working from edges,
  /// not raw intensity, makes it robust: page boundaries and text light up, flat background not.
  private static func gradientMagnitude(
    _ gray: (width: Int, height: Int, pixels: [Float])
  ) -> (width: Int, height: Int, pixels: [Float]) {
    let width = gray.width
    let height = gray.height
    var out = [Float](repeating: 0, count: width * height)
    guard width >= 3, height >= 3 else { return (width, height, out) }
    func at(_ x: Int, _ y: Int) -> Float { gray.pixels[y * width + x] }
    for y in 1..<(height - 1) {
      for x in 1..<(width - 1) {
        let gx =
          (at(x + 1, y - 1) + 2 * at(x + 1, y) + at(x + 1, y + 1))
          - (at(x - 1, y - 1) + 2 * at(x - 1, y) + at(x - 1, y + 1))
        let gy =
          (at(x - 1, y + 1) + 2 * at(x, y + 1) + at(x + 1, y + 1))
          - (at(x - 1, y - 1) + 2 * at(x, y - 1) + at(x + 1, y - 1))
        out[y * width + x] = (gx * gx + gy * gy).squareRoot()
      }
    }
    return (width, height, out)
  }

  /// Projects `edges` onto the axis perpendicular to lines at `thetaDegrees` and returns the
  /// profile's sharpness (sum of squared adjacent-bin differences). Maximal where edges align
  /// into steep steps; small where a rotated edge smears across many bins.
  private static func profileSharpness(
    _ edges: (width: Int, height: Int, pixels: [Float]), thetaDegrees: Double
  ) -> Double {
    let theta = thetaDegrees * .pi / 180
    let sinT = sin(theta)
    let cosT = cos(theta)
    let width = edges.width
    let height = edges.height
    let centerX = Double(width) / 2
    let centerY = Double(height) / 2
    let binCount = Int((Double(width) * abs(sinT) + Double(height) * abs(cosT)).rounded()) + 2
    guard binCount > 2 else { return 0 }
    let offset = Double(binCount) / 2
    var profile = [Double](repeating: 0, count: binCount)
    for y in 0..<height {
      let dy = Double(y) - centerY
      for x in 0..<width {
        let magnitude = edges.pixels[y * width + x]
        if magnitude == 0 { continue }
        let dx = Double(x) - centerX
        let bin = Int(-dx * sinT + dy * cosT + offset)
        if bin >= 0 && bin < binCount { profile[bin] += Double(magnitude) }
      }
    }
    var sharpness = 0.0
    for bin in 1..<binCount {
      let delta = profile[bin] - profile[bin - 1]
      sharpness += delta * delta
    }
    return sharpness
  }
}
