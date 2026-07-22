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
  public static func recognizeLines(in image: CGImage) throws -> [OCRTextLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true

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
