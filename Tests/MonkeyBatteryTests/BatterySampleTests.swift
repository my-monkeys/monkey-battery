import Foundation
import MonkeyBatteryCore
import Testing

/// Both fixtures are trimmed copies of `ioreg -rn AppleSmartBattery -a` on a 14-inch
/// MacBook. `charged.plist` is macOS 27 as read: the raw capacities only exist inside
/// `BatteryData`. `discharging.plist` carries them at the top level, the way older
/// releases did, and its current is stored the way ioreg prints it — as an unsigned
/// 64-bit number.
@Suite("Registry parsing")
struct BatterySampleTests {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("raw capacities are found inside BatteryData")
    func nestedLayout() throws {
        let sample = try #require(BatterySample(registry: try fixture("charged"), readAt: Date()))
        #expect(sample.rawCharge == 8241)
        #expect(sample.rawMaxCapacity == 8400)
        #expect(sample.designCapacity == 8579)
        #expect(sample.percent == 100)
        #expect(sample.externalConnected)
        #expect(!sample.isDraining)
    }

    @Test("a current printed as an unsigned number is read as negative")
    func unsignedCurrent() throws {
        let sample = try #require(BatterySample(registry: try fixture("discharging"), readAt: Date()))
        #expect(sample.milliamps == -1448)
        #expect(sample.rawCharge == 554)
        #expect(sample.isDraining)
        #expect(sample.updatedAt == Date(timeIntervalSince1970: 1_793_412_000))
        #expect(abs(sample.watts - 16.1) < 0.05)
    }

    @Test("a reading without its raw charge is refused")
    func missingCharge() throws {
        var properties = try fixture("discharging")
        properties["AppleRawCurrentCapacity"] = nil
        #expect(BatterySample(registry: properties, readAt: Date()) == nil)
    }
}
