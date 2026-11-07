import Foundation
@testable import MonkeyBatteryCore
import Testing

@Suite("Shutdown calibration")
struct ShutdownCalibrationTests {
    private func heartbeat(percent: Int, charge: Int = 90, projected: Double = 82, atCritical: Bool = false) -> Heartbeat {
        Heartbeat(
            aliveAt: t(30),
            sample: reading(at: 0, charge: charge, percent: percent, atCriticalLevel: atCritical),
            projectedCharge: projected
        )
    }

    /// Plugged in after the shutdown, so the first reading is back on the charger.
    private let afterRestart = reading(at: 900, charge: 95, milliamps: 2500, externalConnected: true, isCharging: true)

    @Test("before any evidence, the threshold is a small reserve of 0.5 % of the pack")
    func defaultGuess() {
        #expect(abs(ShutdownCalibration().cutoffMilliampHours(rawMaxCapacity: 8215) - 41.075) < 1e-9)
    }

    @Test("a reading on battery below the guess pulls the threshold down to it")
    func runningBelowTheGuess() {
        var calibration = ShutdownCalibration()
        let lowered = calibration.noteRunning(reading(at: 0, charge: 30, percent: 1))
        #expect(lowered)
        #expect(calibration.cutoffMilliampHours(rawMaxCapacity: 8215) == 30)

        let raised = calibration.noteRunning(reading(at: 60, charge: 35, percent: 1))
        #expect(!raised)
        #expect(calibration.lowestChargeSeenRunning == 30)
    }

    @Test("a reading above the guess leaves it alone")
    func runningAboveTheGuess() {
        var calibration = ShutdownCalibration()
        calibration.noteRunning(reading(at: 0, charge: 81, percent: 1))
        #expect(abs(calibration.cutoffMilliampHours(rawMaxCapacity: 8215) - 41.075) < 1e-9)
    }

    @Test("on the charger, a low charge proves nothing about the battery")
    func chargerReadingIgnored() {
        var calibration = ShutdownCalibration()
        let charging = reading(at: 0, charge: 10, milliamps: 2500, externalConnected: true, isCharging: true)
        // Right after plugging in, the gauge still reports the discharge for up to a minute.
        let stale = reading(at: 0, charge: 12, milliamps: -2000, externalConnected: true)
        let fromCharging = calibration.noteRunning(charging)
        let fromStale = calibration.noteRunning(stale)
        #expect(!fromCharging)
        #expect(!fromStale)
        #expect(calibration.lowestChargeSeenRunning == nil)
    }

    @Test("a recorded shutdown above a charge the Mac has run at is overruled")
    func shutdownAboveARunningCharge() {
        var calibration = ShutdownCalibration()
        calibration.recordShutdownIfAny(lastHeartbeat: heartbeat(percent: 1), firstAfterGap: afterRestart, gapEndedAt: t(900))
        calibration.noteRunning(reading(at: 1000, charge: 60, percent: 1))
        #expect(calibration.cutoffMilliampHours(rawMaxCapacity: 8215) == 60)
    }

    @Test("a journal written before the running floor existed still loads")
    func decodesOlderJournal() throws {
        let old = Data(#"{"observedCutoffs":[80]}"#.utf8)
        let calibration = try JSONDecoder().decode(ShutdownCalibration.self, from: old)
        #expect(calibration.observedCutoffs == [80])
        #expect(calibration.lowestChargeSeenRunning == nil)
    }

    @Test("a heartbeat at 1 % followed by silence is a shutdown at the projected charge")
    func recordsShutdown() {
        var calibration = ShutdownCalibration()
        let recorded = calibration.recordShutdownIfAny(lastHeartbeat: heartbeat(percent: 1), firstAfterGap: afterRestart, gapEndedAt: t(900))
        #expect(recorded)
        #expect(calibration.observedCutoffs == [82])
        #expect(calibration.cutoffMilliampHours(rawMaxCapacity: 8215) == 82)
    }

    @Test("the gauge's own critical flag counts, whatever the percentage")
    func criticalFlag() {
        var calibration = ShutdownCalibration()
        let beat = heartbeat(percent: 2, atCritical: true)
        let recorded = calibration.recordShutdownIfAny(lastHeartbeat: beat, firstAfterGap: afterRestart, gapEndedAt: t(900))
        #expect(recorded)
    }

    @Test("a lid closed at 5 % is not a shutdown")
    func lidClosedEarly() {
        var calibration = ShutdownCalibration()
        let beat = heartbeat(percent: 5, charge: 400, projected: 395)
        let recorded = calibration.recordShutdownIfAny(lastHeartbeat: beat, firstAfterGap: afterRestart, gapEndedAt: t(900))
        #expect(!recorded)
    }

    @Test("a short gap is a missed tick, not a shutdown")
    func shortGap() {
        var calibration = ShutdownCalibration()
        let recorded = calibration.recordShutdownIfAny(lastHeartbeat: heartbeat(percent: 1), firstAfterGap: afterRestart, gapEndedAt: t(60))
        #expect(!recorded)
    }

    @Test("a Mac that kept draining after the heartbeat did not stop there")
    func keptRunning() {
        var calibration = ShutdownCalibration()
        let stillDraining = reading(at: 900, charge: 30, percent: 1)
        let recorded = calibration.recordShutdownIfAny(lastHeartbeat: heartbeat(percent: 1), firstAfterGap: stillDraining, gapEndedAt: t(900))
        #expect(!recorded)
    }

    @Test("the threshold is the median of the last five shutdowns")
    func median() {
        var calibration = ShutdownCalibration()
        for projected in [300.0, 80, 90, 85, 70, 95] {
            calibration.recordShutdownIfAny(
                lastHeartbeat: heartbeat(percent: 1, projected: projected),
                firstAfterGap: afterRestart,
                gapEndedAt: t(900)
            )
        }
        #expect(calibration.observedCutoffs == [80, 90, 85, 70, 95])
        #expect(calibration.cutoffMilliampHours(rawMaxCapacity: 8215) == 85)
    }
}
