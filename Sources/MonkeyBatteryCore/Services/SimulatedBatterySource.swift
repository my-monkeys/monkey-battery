import Foundation

/// A discharge played back fast, to see every alert without emptying a real battery.
///
///     "Monkey Battery.app/Contents/MacOS/MonkeyBattery" --simulate [start percent]
///
/// Starts at 9 % with a steady 1.5 A drain, runs twenty times faster than real time,
/// and slows to real time for the last three minutes so the alert panel can be watched
/// counting down. The charger can be plugged in from the menu.
@MainActor
public final class SimulatedBatterySource: BatterySource {
    static let rawMaxCapacity = 8215
    static let designCapacity = 8579
    static let drainMilliamps = 1500.0
    static let chargeMilliamps = 3000.0
    static let millivolts = 11_100
    static let fastForward = 20.0
    static let realTimeBelow: TimeInterval = 3 * 60

    public var isPluggedIn = false

    private var simulatedNow: Date
    private var lastRealNow: Date
    private var charge: Double
    private let cutoff = Double(SimulatedBatterySource.rawMaxCapacity) * ShutdownCalibration.defaultReserveFraction

    public init(startPercent: Double = 9, now: Date = Date()) {
        simulatedNow = now
        lastRealNow = now
        charge = Double(Self.rawMaxCapacity) * startPercent / 100
    }

    /// Advances on every call, not only on reads, so a countdown redrawn every second
    /// moves at the simulated pace instead of jumping at each tick.
    public var now: Date {
        advance()
        return simulatedNow
    }

    public func read() -> BatterySample? {
        advance()
        let percent = Int((charge / Double(Self.rawMaxCapacity) * 100).rounded(.up))
        let dead = !isPluggedIn && charge <= cutoff
        return BatterySample(
            updatedAt: simulatedNow,
            rawCharge: Int(charge),
            rawMaxCapacity: Self.rawMaxCapacity,
            designCapacity: Self.designCapacity,
            percent: min(100, percent),
            millivolts: Self.millivolts,
            milliamps: isPluggedIn ? Int(Self.chargeMilliamps) : (dead ? -1 : -Int(Self.drainMilliamps)),
            isCharging: isPluggedIn,
            externalConnected: isPluggedIn,
            atCriticalLevel: dead,
            cycleCount: 42
        )
    }

    private func advance() {
        let realNow = Date()
        let realElapsed = realNow.timeIntervalSince(lastRealNow)
        lastRealNow = realNow

        var elapsed = realElapsed * Self.fastForward
        if !isPluggedIn {
            // Fast-forward only up to the slow stretch, so a tick cannot jump over it.
            let secondsLeft = (charge - cutoff) / Self.drainMilliamps * 3600
            let fastRoom = max(0, secondsLeft - Self.realTimeBelow)
            if elapsed > fastRoom {
                elapsed = fastRoom + (realElapsed - fastRoom / Self.fastForward)
            }
        }
        simulatedNow = simulatedNow.addingTimeInterval(elapsed)

        if isPluggedIn {
            charge = min(Double(Self.rawMaxCapacity), charge + Self.chargeMilliamps * elapsed / 3600)
        } else {
            charge = max(cutoff, charge - Self.drainMilliamps * elapsed / 3600)
        }
    }
}
