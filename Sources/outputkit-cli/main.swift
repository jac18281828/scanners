import Foundation
import OutputKit
import ScannerKit

// outputkit-cli — hardware smoke tool for OutputKit (Phase 4), driven by
// Scripts/smoke-output.sh. Runs two real scans of whatever's on the flatbed (Gray then
// Lineart, same physical page) through the full ScannerKit -> OutputKit pipeline: builds
// a 2-page searchable PDF and exports a standalone JPEG, and prints what Vision recognized
// on each page so the Gray-vs-Lineart OCR comparison (DESIGN.md flag #4) has real numbers
// behind it, not just a synthetic fixture.
//
//   outputkit-cli smoke --pdf-out <path> --jpeg-out <path> [--dpi 300] [--device ID]

enum CLIError: Error, CustomStringConvertible {
  case unknownSubcommand(String)
  case unknownArgument(String)
  case missingValue(String)
  case missingOutputPath(String)
  case noDeviceFound
  case deviceNotFound(String)

  var description: String {
    switch self {
    case .unknownSubcommand(let text): return "unknown subcommand '\(text)' (expected 'smoke')"
    case .unknownArgument(let text): return "unknown argument '\(text)'"
    case .missingValue(let flag): return "missing value for \(flag)"
    case .missingOutputPath(let flag): return "smoke requires \(flag) <path>"
    case .noDeviceFound: return "no scanner devices found"
    case .deviceNotFound(let id): return "no device matching '\(id)' in the current device list"
    }
  }
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(1)
}

func printUsage() {
  print(
    """
    Usage:
      outputkit-cli smoke --pdf-out <path> --jpeg-out <path> [--dpi 300] [--device <id>]
    """
  )
}

struct ArgReader {
  private var iterator: Array<String>.Iterator
  init(_ args: [String]) { self.iterator = args.makeIterator() }
  mutating func next() -> String? { iterator.next() }
  mutating func requireValue(for flag: String) throws -> String {
    guard let value = next() else { throw CLIError.missingValue(flag) }
    return value
  }
}

struct SmokeArguments {
  var dpi = 300
  var pdfOutPath: String?
  var jpegOutPath: String?
  var requestedDeviceID: String?
}

func parseSmokeArguments(_ args: [String]) throws -> SmokeArguments {
  var result = SmokeArguments()
  var reader = ArgReader(args)
  while let arg = reader.next() {
    switch arg {
    case "--dpi":
      guard let dpi = Int(try reader.requireValue(for: arg)) else {
        throw CLIError.unknownArgument(arg)
      }
      result.dpi = dpi
    case "--pdf-out":
      result.pdfOutPath = try reader.requireValue(for: arg)
    case "--jpeg-out":
      result.jpegOutPath = try reader.requireValue(for: arg)
    case "--device":
      result.requestedDeviceID = try reader.requireValue(for: arg)
    default:
      throw CLIError.unknownArgument(arg)
    }
  }
  return result
}

func resolveDevice(
  discovery: ScannerDiscovery, requestedID: String?
) async throws -> ScannerDevice {
  let devices = try await discovery.devices()
  if let requestedID {
    guard let match = devices.first(where: { $0.id == requestedID }) else {
      throw CLIError.deviceNotFound(requestedID)
    }
    return match
  }
  guard let first = devices.first else { throw CLIError.noDeviceFound }
  return first
}

/// Runs one scan to completion and returns the resulting page, printing progress as it goes.
func scanOnePage(deviceID: String, mode: ScanMode, dpi: Int) async throws -> ScannedPage {
  let session = ScanSession(deviceID: deviceID)
  let config = ScanConfiguration(mode: mode, requestedDPI: dpi, source: .flatbed)
  var result: ScannedPage?
  for try await event in session.scan(config: config) {
    switch event {
    case .started(let info):
      print(
        "  started: \(info.widthPixels)x\(info.heightPixels)px @ \(info.hardwareDPI)dpi, mode \(mode)"
      )
    case .progress(let fraction):
      if Int((fraction * 100).rounded()).isMultiple(of: 20) {
        print("  progress: \(Int((fraction * 100).rounded()))%")
      }
    case .completed(let page):
      result = page
    }
  }
  guard let page = result else {
    fail("scan of mode \(mode) never completed")
  }
  return page
}

func summarizeOCR(_ label: String, lines: [OCRTextLine]) {
  let words = lines.flatMap { $0.text.split(separator: " ") }
  print("  \(label): \(lines.count) line(s), \(words.count) word(s) recognized")
  for line in lines {
    print("    - \"\(line.text)\"")
  }
}

func runSmoke(_ args: [String]) async throws {
  let parsed = try parseSmokeArguments(args)
  guard let pdfOutPath = parsed.pdfOutPath else {
    throw CLIError.missingOutputPath("--pdf-out")
  }
  guard let jpegOutPath = parsed.jpegOutPath else {
    throw CLIError.missingOutputPath("--jpeg-out")
  }

  let discovery = ScannerDiscovery()
  let chosen = try await resolveDevice(discovery: discovery, requestedID: parsed.requestedDeviceID)
  print("Using device: \(chosen.id) (\(chosen.displayName))")

  print("Scan 1/2 (Gray, page 1 of the PDF)...")
  let grayPage = try await scanOnePage(deviceID: chosen.id, mode: .gray, dpi: parsed.dpi)

  print("Scan 2/2 (Lineart, page 2 of the PDF — same physical page as scan 1)...")
  let lineartPage = try await scanOnePage(
    deviceID: chosen.id, mode: .blackAndWhite, dpi: parsed.dpi)

  print("Running OCR on both for the Gray-vs-Lineart comparison (DESIGN.md flag #4)...")
  let grayLines = try OCREngine.recognizeLines(in: grayPage.image)
  let lineartLines = try OCREngine.recognizeLines(in: lineartPage.image)
  summarizeOCR("Gray", lines: grayLines)
  summarizeOCR("Lineart", lines: lineartLines)

  print("Assembling 2-page PDF (page 1 Gray, page 2 Lineart, both with an OCR text layer)...")
  let builder = try PDFBuilder()
  try builder.append(page: grayPage, includeOCRTextLayer: true)
  try builder.append(page: lineartPage, includeOCRTextLayer: true)
  let pdfData = builder.finish()
  try pdfData.write(to: URL(fileURLWithPath: pdfOutPath))
  print("Wrote \(pdfOutPath) (\(pdfData.count) bytes, \(builder.pageCount) pages)")

  print("Exporting the Gray page as a standalone JPEG...")
  let jpegData = try ImageExporter.jpegData(for: grayPage)
  try jpegData.write(to: URL(fileURLWithPath: jpegOutPath))
  print("Wrote \(jpegOutPath) (\(jpegData.count) bytes)")
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard let subcommand = arguments.first else {
  printUsage()
  exit(64)
}

do {
  switch subcommand {
  case "smoke":
    try await runSmoke(Array(arguments.dropFirst()))
  case "-h", "--help", "help":
    printUsage()
  default:
    throw CLIError.unknownSubcommand(subcommand)
  }
} catch {
  fail(String(describing: error))
}
