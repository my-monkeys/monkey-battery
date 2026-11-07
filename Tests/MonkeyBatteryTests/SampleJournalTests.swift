import Foundation
@testable import MonkeyBatteryCore
import Testing

@Suite("Sample journal")
struct SampleJournalTests {
    @Test("the current discharge starts after the last moment on the charger")
    func currentDischarge() {
        var journal = SampleJournal(url: nil)
        journal.append(reading(at: 0, charge: 900))
        journal.append(reading(at: 30, charge: 950, milliamps: 2000, externalConnected: true, isCharging: true))
        journal.append(reading(at: 60, charge: 940))
        journal.append(reading(at: 90, charge: 930))
        #expect(journal.currentDischarge.map(\.rawCharge) == [940, 930])

        journal.append(reading(at: 120, charge: 935, milliamps: 2000, externalConnected: true, isCharging: true))
        #expect(journal.currentDischarge.isEmpty)
    }

    @Test("a reading repeated between two gauge updates is kept once")
    func duplicates() {
        var journal = SampleJournal(url: nil)
        journal.append(reading(at: 0))
        journal.append(reading(at: 0))
        #expect(journal.samples.count == 1)
    }

    @Test("readings older than the retention are dropped")
    func retention() {
        var journal = SampleJournal(url: nil)
        journal.append(reading(at: 0))
        journal.append(reading(at: 60))
        journal.append(reading(at: SampleJournal.retention + 30))
        #expect(journal.samples.map(\.updatedAt) == [t(60), t(SampleJournal.retention + 30)])
    }

    @Test("calibration and heartbeat survive a relaunch")
    func persistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("journal.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var journal = SampleJournal(url: url)
        journal.append(reading(at: 0, charge: 90, percent: 1))
        journal.heartbeat = Heartbeat(aliveAt: t(20), sample: reading(at: 0, charge: 90, percent: 1), projectedCharge: 82)
        journal.calibration = ShutdownCalibration(observedCutoffs: [80])
        journal.currentRecord = steadyRecord(minutes: 3, forecast: 600, actual: 600)
        journal.save(now: t(20), urgent: true)

        let reloaded = SampleJournal(url: url)
        #expect(reloaded.samples.count == 1)
        #expect(reloaded.heartbeat?.projectedCharge == 82)
        #expect(reloaded.calibration.observedCutoffs == [80])
        #expect(reloaded.currentRecord?.points.count == 4)
    }
}
