import CoreGraphics
import Vision

/// A single recognized line of text and where it sits on the page.
///
/// `boundingBox` is in Vision's own normalized coordinate space: origin at the
/// bottom-left of the image, axes 0...1 across width/height. That's the same
/// bottom-left-origin convention a raw (non-flipped) `CGContext` — which is what
/// `PDFBuilder` draws into — already uses, so mapping this box onto a PDF page rect is a
/// straight scale by page width/height in points, no y-flip required.
public struct OCRTextLine: Sendable, Equatable {
  public let text: String
  public let boundingBox: CGRect
}

public enum OCRError: Error, CustomStringConvertible, Sendable {
  case recognitionFailed(String)

  public var description: String {
    switch self {
    case .recognitionFailed(let message): return "OCR recognition failed: \(message)"
    }
  }
}

/// Vision-backed text recognition. `VNRecognizeTextRequest` runs synchronously once
/// `VNImageRequestHandler.perform` is called, so this whole call is blocking — callers on
/// the main actor should hop off it first, same as any other CPU-bound Vision request.
public enum OCREngine {
  /// `recognitionLevel`/`automaticallyDetectsLanguage` are exposed (rather than hardcoded)
  /// so tests can request `.fast` — real usage (the app, `outputkit-cli`'s hardware smoke
  /// test) keeps the phase-specified defaults (`.accurate`, autodetect on). This exists
  /// because a GitHub Actions macOS runner's `.accurate` request took >20 minutes and never
  /// produced a single line of test output before a manual cancellation was needed — Apple
  /// Silicon CI runners are virtualized without Neural Engine passthrough, so CoreML falls
  /// back to CPU-only inference; the heavier accurate-mode model is what's suspected to pay
  /// for that, not a true infinite hang (unconfirmed — GitHub buffers a non-TTY child's
  /// stdout until it exits, so no intermediate log output survived the cancellation to
  /// prove which). `.fast` in CI keeps the code path genuinely exercised (real Vision
  /// inference, not skipped) while bounding runtime.
  public static func recognizeLines(
    in image: CGImage,
    recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
    automaticallyDetectsLanguage: Bool = true
  ) throws -> [OCRTextLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = recognitionLevel
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = automaticallyDetectsLanguage

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw OCRError.recognitionFailed(String(describing: error))
    }

    let observations = request.results ?? []
    return observations.compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      return OCRTextLine(text: candidate.string, boundingBox: observation.boundingBox)
    }
  }
}
