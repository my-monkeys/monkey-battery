import Foundation
import MonkeyBatteryCore
import Testing

@Suite("Alert levels")
struct AlertLevelTests {
    private let thresholds = AlertThresholds()

    @Test("time left drives the level", arguments: [
        (TimeInterval(3600), 8, AlertLevel.low),
        (600, 6, .low),
        (299, 6, .warning),
        (119, 4, .critical),
        (29, 4, .final),
    ])
    func byTime(seconds: TimeInterval, percent: Int, expected: AlertLevel) {
        let sample = reading(at: 0, percent: percent)
        #expect(thresholds.level(for: sample, isDraining: true, secondsLeft: seconds) == expected)
    }

    @Test("above the display threshold nothing shows, however short the time")
    func aboveThreshold() {
        let sample = reading(at: 0, percent: 40)
        #expect(thresholds.level(for: sample, isDraining: true, secondsLeft: 3 * 3600) == .none)
        // A heavy load can still make 40 % last only a few minutes.
        #expect(thresholds.level(for: sample, isDraining: true, secondsLeft: 200) == .warning)
    }

    @Test("percentages catch what the estimate has not measured yet")
    func percentFallback() {
        #expect(thresholds.level(for: reading(at: 0, percent: 3), isDraining: true, secondsLeft: nil) == .warning)
        #expect(thresholds.level(for: reading(at: 0, percent: 1), isDraining: true, secondsLeft: nil) == .critical)
    }

    @Test("unplugged at 8 % shows even before the gauge reports the drain")
    func unpluggedWithoutEstimate() {
        let stale = reading(at: 0, percent: 8, milliamps: 1448)
        #expect(thresholds.level(for: stale, isDraining: false, secondsLeft: nil) == .low)
    }

    @Test("on the charger, nothing")
    func charging() {
        let sample = reading(at: 0, percent: 1, milliamps: 2500, externalConnected: true, isCharging: true)
        #expect(thresholds.level(for: sample, isDraining: false, secondsLeft: nil) == .none)
    }

    @Test("the gauge's critical flag is the final level")
    func criticalFlag() {
        let sample = reading(at: 0, percent: 2, atCriticalLevel: true)
        #expect(thresholds.level(for: sample, isDraining: true, secondsLeft: 400) == .final)
    }

    @Test("within one discharge the level only rises, and resets on the charger")
    func escalation() {
        var escalation = AlertEscalation()
        let steps: [(AlertLevel, Bool, AlertLevel, Bool)] = [
            (.warning, true, .warning, true),
            (.low, true, .warning, false),
            (.critical, true, .critical, true),
            (.none, false, .none, false),
            (.low, true, .low, true),
        ]
        for (computed, onBattery, level, isNew) in steps {
            let result = escalation.update(computed: computed, onBattery: onBattery)
            #expect(result.level == level && result.isNew == isNew, "\(computed) on battery: \(onBattery)")
        }
    }
}
