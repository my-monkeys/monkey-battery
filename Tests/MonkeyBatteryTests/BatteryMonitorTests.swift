import Foundation
@testable import MonkeyBatteryCore
import Testing

/// Hands the monitor one reading at a time, at the reading's own date.
@MainActor
private final class ScriptedSource: BatterySource {
    var reading: BatterySample?
    var now: Date { reading?.updatedAt ?? t(0) }
    func read() -> BatterySample? { reading }
}

@Suite("Battery monitor")
@MainActor
struct BatteryMonitorTests {
    @Test("a discharge ended by the charger is archived and graded")
    func archivesDischarges() {
        let source = ScriptedSource()
        let monitor = BatteryMonitor(source: source, journal: SampleJournal(url: nil), thresholds: AlertThresholds())

        for minute in 0...30 {
            source.reading = reading(at: Double(minute) * 60, charge: 900 - minute * 10, milliamps: -600)
            monitor.tick()
        }
        #expect(monitor.reliability.discharges == 0)

        source.reading = reading(at: 31 * 60, charge: 600, milliamps: 2500, externalConnected: true, isCharging: true)
        monitor.tick()
        #expect(monitor.reliability.discharges == 1)
    }

    @Test("the alert level goes by the low end of the range, not the forecast")
    func alertsUseTheLowEnd() {
        let source = ScriptedSource()
        let monitor = BatteryMonitor(source: source, journal: SampleJournal(url: nil), thresholds: AlertThresholds())

        // 600 mA steady, about 8 minutes to the 41 mAh reserve at the end.
        for minute in 0...4 {
            source.reading = reading(at: Double(minute) * 60, charge: 160 - minute * 10, percent: 2, milliamps: -600)
            monitor.tick()
        }
        let forecast = monitor.estimate?.secondsLeft(at: monitor.now) ?? 0
        #expect(forecast > 5 * 60, "the forecast alone would not warn yet")
        #expect(monitor.level == .warning)
    }
}
