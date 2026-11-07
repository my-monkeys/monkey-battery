import Foundation

/// Where the time left can really land, around the forecast.
public struct ForecastBand: Equatable, Sendable {
    public var atLeast: TimeInterval
    public var atMost: TimeInterval

    public init(atLeast: TimeInterval, atMost: TimeInterval) {
        self.atLeast = atLeast
        self.atMost = atMost
    }

    /// Worth showing as a range rather than a single figure.
    public var isWide: Bool { atMost > atLeast * 1.2 }
}

/// The app grading its own forecasts, discharge after discharge.
///
/// The forecast assumes the drain stays at its recent average, and it rarely does. On
/// 2026-11-07, at 10 % on a near-idle Mac, it announced three hours; then the load tripled
/// and the battery lasted 51 minutes. No curve can tell that a build is about to start —
/// but how much the drain tends to change *on this Mac, with this user*, can be measured.
///
/// So every forecast of every past discharge is checked against what followed: from each
/// point, the time the charge really took to fall to each later level, divided by the
/// time the forecast drain implied. Grouped by how far ahead the forecast looked, the 10th
/// and 90th percentiles of those ratios become the band around the current forecast.
public struct ForecastReliability: Equatable, Sendable {
    /// Under three minutes the forecast is taken as is: the drain cannot change much in
    /// that time, and a final countdown ticking slower than the clock would look broken.
    public static let exactBelow: TimeInterval = 180
    /// Forecasts over minutes and over hours go wrong by different amounts.
    static let horizons: [(upTo: TimeInterval, typical: TimeInterval)] = [
        (10 * 60, 330), (30 * 60, 1020), (90 * 60, 3120), (.infinity, 9000),
    ]
    /// Until a horizon has been seen in enough discharges. Graded on the discharge above,
    /// the 10th percentiles ran from 0.67 (minutes ahead) to 0.46 (hours ahead), and the
    /// 90th from 1.97 to 1.18; the low end here is wider still, down to the 0.28 of the
    /// forecast that started it all.
    static let defaultLow = [0.6, 0.45, 0.35, 0.28]
    static let defaultHigh = [2.0, 1.8, 1.7, 1.5]
    public static let minimumDischarges = 3
    static let lowQuantile = 0.1
    static let highQuantile = 0.9
    /// Smaller drops are lost in the gauge's own corrections, which run to 20 mAh.
    static let minimumDrop = 20
    static let minimumElapsed: TimeInterval = 60
    /// Every pair of points is a forecast to grade: a ten-hour discharge would give
    /// 180 000. A hundred and fifty evenly spread points keep it to about 11 000.
    static let gradedPoints = 150

    /// Discharges the band was learned from.
    public let discharges: Int
    let low: [Double]
    let high: [Double]

    public init(records: [DischargeRecord] = []) {
        let count = Self.horizons.count
        var samples = Array(repeating: [(ratio: Double, weight: Double)](), count: count)
        var contributors = Array(repeating: 0, count: count)

        for record in records {
            for (index, ratios) in Self.ratios(in: record).enumerated() where !ratios.isEmpty {
                contributors[index] += 1
                // One vote per discharge: a long one must not outweigh the others.
                let weight = 1 / Double(ratios.count)
                samples[index] += ratios.map { (ratio: $0, weight: weight) }
            }
        }

        let learned = (0..<count).map { contributors[$0] >= Self.minimumDischarges }
        // Capped at 1 so the forecast itself always lies inside its band.
        low = (0..<count).map {
            learned[$0] ? min(1, Self.quantile(samples[$0], Self.lowQuantile)) : Self.defaultLow[$0]
        }
        high = (0..<count).map {
            learned[$0] ? max(1, Self.quantile(samples[$0], Self.highQuantile)) : Self.defaultHigh[$0]
        }
        discharges = records.count
    }

    public var isLearned: Bool { discharges >= Self.minimumDischarges }

    public func band(secondsLeft: TimeInterval) -> ForecastBand {
        guard secondsLeft > Self.exactBelow else {
            return ForecastBand(atLeast: secondsLeft, atMost: secondsLeft)
        }
        return ForecastBand(atLeast: Self.bound(secondsLeft, low), atMost: Self.bound(secondsLeft, high))
    }

    // MARK: - Grading

    /// For each horizon, the ratios real ÷ forecast time of every forecast in the record.
    static func ratios(in record: DischargeRecord) -> [[Double]] {
        var result = Array(repeating: [Double](), count: horizons.count)
        let points = gradable(record.points)

        for (index, start) in points.enumerated() where start.forecastMilliamps > 0 {
            var reached = start.charge
            for end in points[(index + 1)...] where end.charge < reached {
                // The first time the charge got this low: that is when the level was reached.
                reached = end.charge
                let drop = start.charge - end.charge
                let elapsed = end.at.timeIntervalSince(start.at)
                guard drop >= minimumDrop, elapsed >= minimumElapsed else { continue }

                let forecast = Double(drop) / start.forecastMilliamps * 3600
                let horizon = horizons.firstIndex { forecast <= $0.upTo } ?? horizons.count - 1
                result[horizon].append(elapsed / forecast)
            }
        }
        return result
    }

    /// Thinned to `gradedPoints`, without the readings above an earlier one: the gauge
    /// sometimes corrects itself upwards by a few mAh, and grading from such a reading
    /// would compare a charge with a moment it does not belong to.
    private static func gradable(_ points: [DischargePoint]) -> [DischargePoint] {
        let stride = max(1, (points.count + gradedPoints - 1) / gradedPoints)
        var lowest = Int.max
        return Swift.stride(from: 0, to: points.count, by: stride).compactMap { index in
            let point = points[index]
            guard point.charge <= lowest else { return nil }
            lowest = point.charge
            return point
        }
    }

    private static func quantile(_ samples: [(ratio: Double, weight: Double)], _ fraction: Double) -> Double {
        let sorted = samples.sorted { $0.ratio < $1.ratio }
        let total = sorted.reduce(0) { $0 + $1.weight }
        var cumulative = 0.0
        for sample in sorted {
            cumulative += sample.weight
            if cumulative >= fraction * total { return sample.ratio }
        }
        return sorted.last?.ratio ?? 1
    }

    // MARK: - Band

    /// The bound for a forecast of `seconds`: `horizon × factor` at each typical horizon,
    /// from exactly the forecast at `exactBelow`, kept non-decreasing and joined by
    /// straight lines. That shape cannot climb while the forecast falls, and stays on its
    /// side of the forecast — a factor interpolated on its own would allow neither.
    static func bound(_ seconds: TimeInterval, _ factors: [Double]) -> TimeInterval {
        var previous = (at: exactBelow, bound: exactBelow)
        for (horizon, factor) in zip(horizons, factors) {
            let bound = max(previous.bound, horizon.typical * factor)
            guard seconds > horizon.typical else {
                let position = (seconds - previous.at) / (horizon.typical - previous.at)
                return previous.bound + position * (bound - previous.bound)
            }
            previous = (horizon.typical, bound)
        }
        return max(previous.bound, seconds * (factors.last ?? 1))
    }
}
