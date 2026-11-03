import Foundation
import MonkeyBatteryCore

/// A reading with sensible defaults: 8215 mAh pack, 11.1 V, unplugged.
func reading(
    at seconds: TimeInterval,
    charge: Int = 800,
    percent: Int? = nil,
    milliamps: Int = -1500,
    externalConnected: Bool = false,
    isCharging: Bool = false,
    atCriticalLevel: Bool = false
) -> BatterySample {
    BatterySample(
        updatedAt: t(seconds),
        rawCharge: charge,
        rawMaxCapacity: 8215,
        designCapacity: 8579,
        percent: percent ?? Int((Double(charge) / 8215 * 100).rounded(.up)),
        millivolts: 11_100,
        milliamps: milliamps,
        isCharging: isCharging,
        externalConnected: externalConnected,
        atCriticalLevel: atCriticalLevel,
        cycleCount: 42
    )
}

/// A fixed origin, so failures print readable offsets.
func t(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_800_000_000 + seconds)
}
