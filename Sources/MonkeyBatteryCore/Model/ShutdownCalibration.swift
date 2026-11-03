import Foundation

/// The last moment the app saw the Mac running on battery, kept on disk so it survives
/// the shutdown it may be about to witness.
public struct Heartbeat: Codable, Equatable, Sendable {
    public var aliveAt: Date
    /// The last gauge reading before `aliveAt`.
    public var sample: BatterySample
    /// The charge at `aliveAt`, projected from that reading at the measured drain. The
    /// gauge refreshes every 20 to 60 seconds, so its last reading can be a minute older
    /// than the shutdown; this is the closer figure.
    public var projectedCharge: Double

    public init(aliveAt: Date, sample: BatterySample, projectedCharge: Double) {
        self.aliveAt = aliveAt
        self.sample = sample
        self.projectedCharge = projectedCharge
    }
}

/// The charge at which this Mac actually gives up.
///
/// macOS forces the Mac to sleep before the gauge reaches zero, and how far before is not
/// published anywhere. Until it has been observed, the threshold is a deliberately high
/// guess: announcing the end two minutes early costs a little trust, announcing it late
/// costs the unsaved work this app exists to protect. Each observed shutdown replaces the
/// guess, and the median of the last few keeps one odd reading from moving it.
public struct ShutdownCalibration: Codable, Equatable, Sendable {
    public static let defaultReserveFraction = 0.02
    static let keptObservations = 5
    /// A heartbeat followed by this much silence is a shutdown, not a missed tick.
    static let minimumSilence: TimeInterval = 120
    /// Further drain than this after the last heartbeat means the Mac kept running without
    /// the app watching — the app was quit, say — so that heartbeat was not the end.
    static let drainTolerance = 20.0

    public private(set) var observedCutoffs: [Int]

    public init(observedCutoffs: [Int] = []) {
        self.observedCutoffs = observedCutoffs
    }

    public var isMeasured: Bool { !observedCutoffs.isEmpty }

    public func cutoffMilliampHours(rawMaxCapacity: Int) -> Double {
        guard isMeasured else { return Double(rawMaxCapacity) * Self.defaultReserveFraction }
        let sorted = observedCutoffs.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? Double(sorted[middle - 1] + sorted[middle]) / 2
            : Double(sorted[middle])
    }

    /// Looks at the last heartbeat before a gap — a relaunch, or a wake from sleep — and
    /// records it as a shutdown point when it was one.
    ///
    /// Only a heartbeat at the very end counts: a lid closed at 5 % is also followed by
    /// silence, and recording it would push the threshold up for no reason.
    @discardableResult
    public mutating func recordShutdownIfAny(
        lastHeartbeat heartbeat: Heartbeat,
        firstAfterGap first: BatterySample,
        gapEndedAt: Date
    ) -> Bool {
        let last = heartbeat.sample
        guard last.isDraining,
              last.percent <= 1 || last.atCriticalLevel,
              gapEndedAt.timeIntervalSince(heartbeat.aliveAt) >= Self.minimumSilence,
              Double(first.rawCharge) >= heartbeat.projectedCharge - Self.drainTolerance
        else { return false }

        // The Mac was still running at the heartbeat, so the true threshold is at most
        // this — rounding up keeps the error on the early side.
        observedCutoffs.append(Int(heartbeat.projectedCharge.rounded(.up)))
        if observedCutoffs.count > Self.keptObservations {
            observedCutoffs.removeFirst(observedCutoffs.count - Self.keptObservations)
        }
        return true
    }
}
