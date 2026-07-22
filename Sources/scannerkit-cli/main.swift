import CoreGraphics
import Foundation
import ImageIO
import ScannerKit
import UniformTypeIdentifiers

// scannerkit-cli — hardware smoke tool for ScannerKit (and later phases).
//
//   scannerkit-cli list
//   scannerkit-cli scan --mode gray --dpi 100 -o /tmp/out.png [--source flatbed] [--device ID]

enum CLIError: Error, CustomStringConvertible {
  case unknownSubcommand(String)
  case unknownArgument(String)
  case missingValue(String)
  case invalidMode(String)
  case invalidSource(String)
  case invalidDPI(String)
  case missingOutputPath
  case noDeviceFound
  case deviceNotFound(String)
  case pngWriteFailed(String)

  var description: String {
    switch self {
    case .unknownSubcommand(let text):
      return "unknown subcommand '\(text)' (expected 'list' or 'scan')"
    case .unknownArgument(let text): return "unknown argument '\(text)'"
    case .missingValue(let flag): return "missing value for \(flag)"
    case .invalidMode(let text):
      return "invalid --mode '\(text)' (expected color, gray, or blackAndWhite)"
    case .invalidSource(let text): return "invalid --source '\(text)' (expected flatbed or adf)"
    case .invalidDPI(let text): return "invalid --dpi '\(text)' (expected a positive integer)"
    case .missingOutputPath: return "scan requires -o/--output <path>"
    case .noDeviceFound: return "no scanner devices found"
    case .deviceNotFound(let id): return "no device matching '\(id)' in the current device list"
    case .pngWriteFailed(let path): return "failed to write PNG to \(path)"
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
      scannerkit-cli list
      scannerkit-cli scan --mode <color|gray|blackAndWhite> --dpi <n> -o <path> \
    [--source <flatbed|adf>] [--device <id>]
    """
  )
}

struct ArgReader {
  private var iterator: Array<String>.Iterator
  private var peeked: String?

  init(_ args: [String]) {
    self.iterator = args.makeIterator()
  }

  mutating func next() -> String? {
    if let peeked {
      self.peeked = nil
      return peeked
    }
    return iterator.next()
  }

  mutating func requireValue(for flag: String) throws -> String {
    guard let value = next() else {
      throw CLIError.missingValue(flag)
    }
    return value
  }
}

func parseMode(_ raw: String) throws -> ScanMode {
  guard let mode = ScanMode(rawValue: raw) else {
    throw CLIError.invalidMode(raw)
  }
  return mode
}

func parseSource(_ raw: String) throws -> ScanSource {
  guard let source = ScanSource(rawValue: raw) else {
    throw CLIError.invalidSource(raw)
  }
  return source
}

func parseDPI(_ raw: String) throws -> Int {
  guard let dpi = Int(raw), dpi > 0 else {
    throw CLIError.invalidDPI(raw)
  }
  return dpi
}

func runList() async throws {
  let discovery = ScannerDiscovery()
  let devices = try await discovery.devices()
  if devices.isEmpty {
    print("No scanners found.")
    return
  }
  for device in devices {
    print("\(device.id)\t\(device.displayName) [\(device.type)]")
  }
}

func writePNG(_ image: CGImage, to url: URL) throws {
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    throw CLIError.pngWriteFailed(url.path)
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw CLIError.pngWriteFailed(url.path)
  }
}

// MARK: - scan subcommand

struct ScanArguments {
  var mode: ScanMode = .gray
  var dpi = 300
  var source: ScanSource = .flatbed
  var outputPath: String?
  var requestedDeviceID: String?
}

func parseScanArguments(_ args: [String]) throws -> ScanArguments {
  var result = ScanArguments()
  var reader = ArgReader(args)
  while let arg = reader.next() {
    switch arg {
    case "--mode":
      result.mode = try parseMode(try reader.requireValue(for: arg))
    case "--dpi":
      result.dpi = try parseDPI(try reader.requireValue(for: arg))
    case "--source":
      result.source = try parseSource(try reader.requireValue(for: arg))
    case "-o", "--output":
      result.outputPath = try reader.requireValue(for: arg)
    case "--device":
      result.requestedDeviceID = try reader.requireValue(for: arg)
    default:
      throw CLIError.unknownArgument(arg)
    }
  }
  return result
}

func resolveDevice(
  discovery: ScannerDiscovery,
  requestedID: String?
) async throws -> ScannerDevice {
  let devices = try await discovery.devices()
  if let requestedID {
    guard let match = devices.first(where: { $0.id == requestedID }) else {
      throw CLIError.deviceNotFound(requestedID)
    }
    return match
  }
  guard let first = devices.first else {
    throw CLIError.noDeviceFound
  }
  return first
}

func describeStarted(_ info: ScanParametersInfo) -> String {
  let widthMM = String(format: "%.1f", info.widthMM)
  let heightMM = String(format: "%.1f", info.heightMM)
  return "started: \(info.widthPixels)x\(info.heightPixels)px @ \(info.hardwareDPI)dpi "
    + "(requested \(info.requestedDPI)dpi), \(widthMM)x\(heightMM)mm"
}

func describeCompleted(_ page: ScannedPage, outputPath: String) -> String {
  let widthMM = String(format: "%.1f", page.widthMM)
  let heightMM = String(format: "%.1f", page.heightMM)
  return
    "wrote \(outputPath): \(page.image.width)x\(page.image.height)px, \(widthMM)x\(heightMM)mm, "
    + "requested \(page.requestedDPI)dpi / hardware \(page.hardwareDPI)dpi, mode \(page.mode)"
}

func handle(_ event: ScanEvent, outputPath: String) throws {
  switch event {
  case .started(let info):
    print(describeStarted(info))
  case .progress(let fraction):
    print("progress: \(Int((fraction * 100).rounded()))%")
  case .completed(let page):
    try writePNG(page.image, to: URL(fileURLWithPath: outputPath))
    print(describeCompleted(page, outputPath: outputPath))
  }
}

func runScan(_ args: [String]) async throws {
  let parsed = try parseScanArguments(args)
  guard let outputPath = parsed.outputPath else {
    throw CLIError.missingOutputPath
  }

  let discovery = ScannerDiscovery()
  let chosen = try await resolveDevice(discovery: discovery, requestedID: parsed.requestedDeviceID)
  print("Using device: \(chosen.id) (\(chosen.displayName))")

  let session = ScanSession(deviceID: chosen.id)
  let config = ScanConfiguration(mode: parsed.mode, requestedDPI: parsed.dpi, source: parsed.source)

  for try await event in session.scan(config: config) {
    try handle(event, outputPath: outputPath)
  }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

guard let subcommand = arguments.first else {
  printUsage()
  exit(64)
}

do {
  switch subcommand {
  case "list":
    try await runList()
  case "scan":
    try await runScan(Array(arguments.dropFirst()))
  case "-h", "--help", "help":
    printUsage()
  default:
    throw CLIError.unknownSubcommand(subcommand)
  }
} catch {
  fail(String(describing: error))
}
