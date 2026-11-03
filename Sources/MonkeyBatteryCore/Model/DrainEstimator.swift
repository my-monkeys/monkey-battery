import Foundation

/// How long the battery has left, projected from the gauge's own figures.
public struct DrainEstimate: Equatable, Sendable {
    /// The moment the charge reaches the shutdown threshold at the current drain. A date
    /// rather than a duration, so a countdown keeps ticking between gauge updates.
    public var emptyAt: Date
    /// Smoothed current leaving the battery, in mA.
    public var milliamps: Double
    public var watts: Double
    /// The charge right now, in mAh, projected from the last gauge reading.
    public var projectedCharge: Double
    /// False for the first minutes on battery, while the smoothing has little to go on.
    public var isSettled: Bool

    public func secondsLeft(at now: Date) -> TimeInterval {
        max(0, emptyAt.timeIntervalSince(now))
    }
}

/// Turns successive gauge readings into a time-to-empty.
///
/// The drain is an exponential moving average of the gauge's current, weighted by the
/// time between updates: a burst of compile load moves it, a one-second spike does not.
/// The remaining charge is projected forward from the last update at that drain, so the
/// estimate is continuous instead of jumping every 20 to 60 seconds.
public struct DrainEstimator: Sendable {
    /// Long enough to average out a spike, short enough that closing a heavy app shows
    /// up within a few minutes.
    public static let smoothingSeconds: TimeInterval = 180
    /// Time on battery after which the average is trusted.
    public static let settlingSeconds: TimeInterval = 120

    private var smoothedMilliamps: Double?
    private var lastSample: BatterySample?
    private var drainStartedAt: Date?
    /// The gauge keeps reporting the old current for up to a minute after the charger is
    /// plugged in. Until it refreshes past this moment, its figures describe the past.
    private var connectedAt: Date?
    private var wasConnected: Bool?

    public init() {}

    public mutating func ingest(_ sample: BatterySample, readAt: Date) {
        trackConnection(sample, readAt: readAt)

        guard isDraining(sample) else {
            reset()
            return
        }
        // Same update read twice: nothing new to learn.
        guard sample.updatedAt != lastSample?.updatedAt else { return }

        let current = Double(-sample.milliamps)
        if let previous = smoothedMilliamps, let last = lastSample {
            let elapsed = max(0, sample.updatedAt.timeIntervalSince(last.updatedAt))
            let weight = 1 - exp(-elapsed / Self.smoothingSeconds)
            smoothedMilliamps = previous + weight * (current - previous)
        } else {
            smoothedMilliamps = current
            drainStartedAt = sample.updatedAt
        }
        lastSample = sample
    }

    /// Nil until the gauge has reported a discharge.
    public func estimate(now: Date, cutoffMilliampHours: Double) -> DrainEstimate? {
        guard let drain = smoothedMilliamps, drain > 0, let sample = lastSample else { return nil }

        let sinceUpdate = max(0, now.timeIntervalSince(sample.updatedAt))
        let chargeNow = Double(sample.rawCharge) - drain * sinceUpdate / 3600
        let usable = max(0, chargeNow - cutoffMilliampHours)
        let secondsLeft = usable / drain * 3600
        let onBattery = drainStartedAt.map { now.timeIntervalSince($0) } ?? 0

        return DrainEstimate(
            emptyAt: now.addingTimeInterval(secondsLeft),
            milliamps: drain,
            watts: drain * Double(sample.millivolts) / 1_000_000,
            projectedCharge: chargeNow,
            isSettled: onBattery >= Self.settlingSeconds
        )
    }

    /// Whether this reading describes a battery being emptied right now.
    public func isDraining(_ sample: BatterySample) -> Bool {
        guard sample.isDraining else { return false }
        if sample.externalConnected, let connectedAt, sample.updatedAt <= connectedAt {
            return false
        }
        return true
    }

    private mutating func trackConnection(_ sample: BatterySample, readAt: Date) {
        if sample.externalConnected, wasConnected == false {
            connectedAt = readAt
        }
        if !sample.externalConnected {
            connectedAt = nil
        }
        wasConnected = sample.externalConnected
    }

    private mutating func reset() {
        smoothedMilliamps = nil
        lastSample = nil
        drainStartedAt = nil
    }
}
