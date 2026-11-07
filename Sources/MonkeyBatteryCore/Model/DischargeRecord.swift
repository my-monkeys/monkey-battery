import Foundation

/// One moment of a discharge, with the drain the app was forecasting from at that moment.
public struct DischargePoint: Codable, Equatable, Sendable {
    /// When the gauge took the reading.
    public var at: Date
    /// In mAh.
    public var charge: Int
    public var percent: Int
    /// The smoothed drain behind the forecast shown at that moment, in mA. Kept so the app
    /// can later grade what it announced against what happened.
    public var forecastMilliamps: Double

    public init(at: Date, charge: Int, percent: Int, forecastMilliamps: Double) {
        self.at = at
        self.charge = charge
        self.percent = percent
        self.forecastMilliamps = forecastMilliamps
    }
}

/// A stretch of continuous discharge, one point a minute: from unplugging to plugging in
/// again, or to the shutdown.
public struct DischargeRecord: Codable, Equatable, Sendable {
    static let spacing: TimeInterval = 60
    /// Longer than this between two points is a sleep, or the app not running: the Mac
    /// barely drains asleep, so a record spanning it would look like a forecast that was
    /// wildly pessimistic. The discharge after the gap is a record of its own.
    static let maximumGap: TimeInterval = 5 * 60
    static let minimumPoints = 5
    static let minimumDrop = 50

    public private(set) var points: [DischargePoint]

    public init(first: DischargePoint) {
        points = [first]
    }

    init(points: [DischargePoint]) {
        self.points = points
    }

    /// False when the point cannot continue this record; nothing is added then.
    public mutating func append(_ point: DischargePoint) -> Bool {
        guard let last = points.last else {
            points = [point]
            return true
        }
        let elapsed = point.at.timeIntervalSince(last.at)
        guard elapsed >= 0, elapsed <= Self.maximumGap else { return false }
        if elapsed >= Self.spacing { points.append(point) }
        return true
    }

    /// Too short to say anything about a forecast.
    public var isWorthKeeping: Bool {
        guard let first = points.first, let last = points.last else { return false }
        return points.count >= Self.minimumPoints && first.charge - last.charge >= Self.minimumDrop
    }
}
