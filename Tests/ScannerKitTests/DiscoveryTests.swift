import Testing

@testable import ScannerKit

@Suite("ScannerDiscovery")
struct DiscoveryTests {
  @Test("returns the scripted device list, mapped to public ScannerDevice")
  func returnsScriptedDevices() async throws {
    let mock = MockSane(
      configuration: MockSane.Configuration(
        devices: [
          SaneDeviceRecord(
            name: "hp5590:libusb:000:017",
            vendor: "Hewlett-Packard",
            model: "ScanJet 4570c",
            type: "flatbed scanner"
          ),
          SaneDeviceRecord(
            name: "test:0", vendor: "Acme", model: "Widget", type: "flatbed scanner"),
        ],
        supportedDPI: ResolutionPolicy.nativeDPI.map(Int32.init),
        bedWidthMM: 215.899,
        bedHeightMM: 297.699,
        openFailure: nil,
        readDelay: 0
      )
    )
    let discovery = ScannerDiscovery(backend: mock, runner: SaneRunner())

    let devices = try await discovery.devices()

    #expect(devices.count == 2)
    #expect(devices[0].id == "hp5590:libusb:000:017")
    #expect(devices[0].vendor == "Hewlett-Packard")
    #expect(devices[0].model == "ScanJet 4570c")
    #expect(devices[0].displayName == "Hewlett-Packard ScanJet 4570c")
    #expect(devices[1].id == "test:0")
  }

  @Test("empty device list is not an error")
  func emptyDeviceListIsNotAnError() async throws {
    let mock = MockSane(
      configuration: MockSane.Configuration(
        devices: [],
        supportedDPI: ResolutionPolicy.nativeDPI.map(Int32.init),
        bedWidthMM: 215.899,
        bedHeightMM: 297.699,
        openFailure: nil,
        readDelay: 0
      )
    )
    let discovery = ScannerDiscovery(backend: mock, runner: SaneRunner())

    let devices = try await discovery.devices()

    #expect(devices.isEmpty)
  }

  @Test("device strings are re-fetched on every call, not cached")
  func reEnumeratesOnDemand() async throws {
    // Simulates a replug: the device id changes between two calls (bus/address vary per
    // plug event per DESIGN.md) — ScannerDiscovery must reflect that, not memoize.
    let mock = MockSane(
      configuration: MockSane.Configuration(
        devices: [
          SaneDeviceRecord(
            name: "hp5590:libusb:000:016", vendor: "HP", model: "4570c", type: "flatbed")
        ],
        supportedDPI: ResolutionPolicy.nativeDPI.map(Int32.init),
        bedWidthMM: 215.899,
        bedHeightMM: 297.699,
        openFailure: nil,
        readDelay: 0
      )
    )
    let discovery = ScannerDiscovery(backend: mock, runner: SaneRunner())

    let first = try await discovery.devices()
    mock.setDevicesForTesting([
      SaneDeviceRecord(name: "hp5590:libusb:000:018", vendor: "HP", model: "4570c", type: "flatbed")
    ])
    let second = try await discovery.devices()

    #expect(first.first?.id == "hp5590:libusb:000:016")
    #expect(second.first?.id == "hp5590:libusb:000:018")
  }
}
