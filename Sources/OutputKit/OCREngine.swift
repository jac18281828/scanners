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
  /// `language` is a BCP-47 tag (`recognitionLanguages` takes an ordered-priority array;
  /// this always passes a single fixed language, `automaticallyDetectsLanguage = false`) —
  /// DESIGN.md decision #6. Vision's automatic language detection can trigger an on-device
  /// language-model fetch on first use, which hung indefinitely (>20 minutes, no test
  /// output at all) on a fresh GitHub Actions macOS CI runner in this phase's first CI
  /// push. Pinning a language sidesteps that fetch entirely, in CI and in production, with
  /// no accuracy tradeoff for documents actually in that language. Exposed as a parameter
  /// (default `en-US`) rather than hardcoded so Phase 5's Settings pane can plug a user
  /// preference into it.
  public static func recognizeLines(
    in image: CGImage,
    language: String = "en-US"
  ) throws -> [OCRTextLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [language]
    request.automaticallyDetectsLanguage = false

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
