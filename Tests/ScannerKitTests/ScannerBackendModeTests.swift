import Testing

@testable import ScannerKit

/// `ScannerBackendMode` is Phase 5's only public seam into mock mode — these tests exercise
/// it exactly as `ScannersApp` will (through the public `mode:` initializers only, never
/// reaching into `MockSane` directly), confirming `.mock` drives the same device-discovery
/// and full scan(-decode) path real hardware would, with zero SANE/libusb involvement.
@Suite("ScannerBackendMode")
struct ScannerBackendModeTests {
  @Test(
    ".mock discovery finds the same scripted hp5590 device MockSane.Configuration.default ships")
  func mockDiscoveryFindsDefaultDevice() async throws {
    let discovery = ScannerDiscovery(mode: .mock)
    let devices = try await discovery.devices()

    #expect(devices.count == 1)
    #expect(devices[0].id == "hp5590:libusb:000:017")
    #expect(devices[0].displayName == "Hewlett-Packard ScanJet 4570c")
  }

  @Test(".mock ScanSession completes a full scan through the public API only")
  func mockScanSessionCompletesAScan() async throws {
    let session = ScanSession(deviceID: "hp5590:libusb:000:017", mode: .mock)
    let config = ScanConfiguration(mode: .gray, requestedDPI: 100)

    var sawStarted = false
    var sawCompleted = false
    for try await event in session.scan(config: config) {
      switch event {
      case .started: sawStarted = true
      case .progress: break
      case .completed(let page):
        sawCompleted = true
        #expect(page.mode == .gray)
        #expect(page.image.width > 0)
      }
    }

    #expect(sawStarted)
    #expect(sawCompleted)
  }
}
