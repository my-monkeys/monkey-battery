import Foundation

/// How loudly the app speaks, from silent to everything at once.
public enum AlertLevel: Int, Comparable, Sendable, CaseIterable {
    /// Plenty left, or not on battery: the menu bar item stays hidden.
    case none
    /// Below the display threshold: the menu bar shows the time left.
    case low
    /// A few minutes left: one notification, with a sound.
    case warning
    /// The end is near: a panel over every window, an alarm that repeats.
    case critical
    /// The last seconds, or the gauge itself says it is about to stop.
    case final

    public static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The thresholds are time-based first. A percentage is a poor clock: on this kind of
/// battery 1 % lasts anywhere from two to six minutes depending on the load. The
/// percentages only catch the case where the estimate is not there yet.
public struct AlertThresholds: Equatable, Sendable {
    public var showBelowPercent: Int
    public var warningSeconds: TimeInterval = 5 * 60
    public var criticalSeconds: TimeInterval = 2 * 60
    public var finalSeconds: TimeInterval = 30
    public var warningPercent = 3
    public var criticalPercent = 1

    public static let showOptions = [5, 10, 15, 20]
    public static let defaultShowBelowPercent = 10

    public init(showBelowPercent: Int = AlertThresholds.defaultShowBelowPercent) {
        self.showBelowPercent = showBelowPercent
    }

    public func level(for sample: BatterySample, isDraining: Bool, secondsLeft: TimeInterval?) -> AlertLevel {
        // Unplugged with no estimate yet is still worth showing: the gauge simply has not
        // refreshed since the charger went away.
        let onBattery = isDraining || !sample.externalConnected
        guard onBattery, !sample.isCharging else { return .none }

        let seconds = secondsLeft ?? .infinity
        if isDraining, sample.atCriticalLevel || seconds <= finalSeconds { return .final }
        if seconds <= criticalSeconds || sample.percent <= criticalPercent { return .critical }
        if seconds <= warningSeconds || sample.percent <= warningPercent { return .warning }
        if sample.percent <= showBelowPercent { return .low }
        return .none
    }
}

/// Keeps a level from flapping. Within one discharge the level only ever rises: an
/// estimate that recovers by a minute because a video was paused is not a reason to take
/// the warning back. It falls back to the computed level once the battery stops draining.
public struct AlertEscalation: Sendable {
    public private(set) var level: AlertLevel = .none

    public init() {}

    /// Returns the level to act on, and whether it is new.
    @discardableResult
    public mutating func update(computed: AlertLevel, onBattery: Bool) -> (level: AlertLevel, isNew: Bool) {
        let next = onBattery ? max(level, computed) : computed
        defer { level = next }
        return (next, next > level)
    }
}
