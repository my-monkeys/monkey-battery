import Foundation

/// One reading of the battery gauge, in the units the gauge itself reports.
///
/// Everything here comes from the `AppleSmartBattery` registry entry rather than from the
/// percentage and time macOS displays: the raw charge is in mAh and moves every update,
/// where the percentage moves once per 80 mAh or so, and the system's own time estimate
/// is withheld for minutes after unplugging.
public struct BatterySample: Codable, Equatable, Sendable {
    /// When the gauge last refreshed these figures — not when they were read. The gauge
    /// refreshes every 20 to 60 seconds; reading it in between returns the same values.
    public var updatedAt: Date
    public var rawCharge: Int
    public var rawMaxCapacity: Int
    public var designCapacity: Int
    /// The percentage macOS shows, which is not quite `rawCharge / rawMaxCapacity`.
    public var percent: Int
    public var millivolts: Int
    /// Negative while discharging.
    public var milliamps: Int
    public var isCharging: Bool
    public var externalConnected: Bool
    /// Set by the gauge shortly before macOS forces the Mac to sleep.
    public var atCriticalLevel: Bool
    public var cycleCount: Int

    public init(
        updatedAt: Date,
        rawCharge: Int,
        rawMaxCapacity: Int,
        designCapacity: Int,
        percent: Int,
        millivolts: Int,
        milliamps: Int,
        isCharging: Bool,
        externalConnected: Bool,
        atCriticalLevel: Bool,
        cycleCount: Int
    ) {
        self.updatedAt = updatedAt
        self.rawCharge = rawCharge
        self.rawMaxCapacity = rawMaxCapacity
        self.designCapacity = designCapacity
        self.percent = percent
        self.millivolts = millivolts
        self.milliamps = milliamps
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.atCriticalLevel = atCriticalLevel
        self.cycleCount = cycleCount
    }

    /// On the charger, below this the battery is only idling. A full battery held at 100 %
    /// reads a few dozen mA out (−34 mA measured) without anything being wrong.
    static let pluggedDrainFloor = -300

    /// Current flowing out of the battery — on a charger too, when it is too weak for the
    /// load and the battery makes up the difference.
    public var isDraining: Bool {
        guard !isCharging else { return false }
        return milliamps < (externalConnected ? Self.pluggedDrainFloor : 0)
    }

    public var watts: Double { Double(abs(milliamps)) * Double(millivolts) / 1_000_000 }

    /// Health as the gauge measures it, against the capacity the pack was designed for.
    public var healthFraction: Double {
        guard designCapacity > 0 else { return 0 }
        return Double(rawMaxCapacity) / Double(designCapacity)
    }
}

extension BatterySample {
    /// Builds a sample from the properties of the `AppleSmartBattery` registry entry.
    /// Nil when a figure the estimate cannot do without is missing.
    public init?(registry properties: [String: Any], readAt: Date) {
        let nested = properties["BatteryData"] as? [String: Any] ?? [:]

        func integer(_ key: String) -> Int? {
            let value = properties[key] ?? nested[key]
            guard let number = value as? NSNumber else { return nil }
            // ioreg prints negative currents as huge unsigned numbers; depending on how the
            // driver stored them they arrive either way. The bit pattern is what matters.
            return Int(Int64(truncatingIfNeeded: number.uint64Value))
        }

        func flag(_ key: String) -> Bool {
            (properties[key] as? NSNumber)?.boolValue ?? false
        }

        guard let rawCharge = integer("AppleRawCurrentCapacity"),
              let rawMax = integer("AppleRawMaxCapacity"), rawMax > 0,
              let percent = integer("CurrentCapacity"),
              let millivolts = integer("Voltage"),
              let milliamps = integer("Amperage") ?? integer("InstantAmperage")
        else { return nil }

        self.init(
            updatedAt: integer("UpdateTime").map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? readAt,
            rawCharge: rawCharge,
            rawMaxCapacity: rawMax,
            designCapacity: integer("DesignCapacity") ?? rawMax,
            percent: percent,
            millivolts: millivolts,
            milliamps: milliamps,
            isCharging: flag("IsCharging"),
            externalConnected: flag("ExternalConnected"),
            atCriticalLevel: flag("AtCriticalLevel"),
            cycleCount: integer("CycleCount") ?? 0
        )
    }
}
