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

    @Test("before any shutdown, the threshold is a cautious 2 % of the pack")
    func defaultGuess() {
        #expect(abs(ShutdownCalibration().cutoffMilliampHours(rawMaxCapacity: 8215) - 164.3) < 1e-9)
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
