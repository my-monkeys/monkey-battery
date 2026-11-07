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
/// macOS may force the Mac to sleep before the gauge reaches zero, and how far before is
/// not published anywhere. Two kinds of evidence narrow it down:
///
/// - **A shutdown** — the last heartbeat before a long silence at 1 % — gives the threshold
///   itself. The median of the last few keeps one odd reading from moving it.
/// - **Any reading on battery** proves the Mac still runs at that charge, so the threshold
///   lies below. This one comes for free on every discharge, including the usual ones that
///   end with the charger plugged in at 1 % — which is what this app is for, so shutdowns
///   will be rare.
///
/// Until either is available, the threshold is a small reserve. It used to be 2 %: on the
/// Mac this was written on, that announced the end while the Mac still ran at half that
/// charge, minutes ahead at a light load.
public struct ShutdownCalibration: Codable, Equatable, Sendable {
    public static let defaultReserveFraction = 0.005
    static let keptObservations = 5
    /// A heartbeat followed by this much silence is a shutdown, not a missed tick.
    static let minimumSilence: TimeInterval = 120
    /// Further drain than this after the last heartbeat means the Mac kept running without
    /// the app watching — the app was quit, say — so that heartbeat was not the end.
    static let drainTolerance = 20.0

    public private(set) var observedCutoffs: [Int]
    /// Optional so that a journal written before it existed still decodes.
    public private(set) var lowestChargeSeenRunning: Int?

    public init(observedCutoffs: [Int] = [], lowestChargeSeenRunning: Int? = nil) {
        self.observedCutoffs = observedCutoffs
        self.lowestChargeSeenRunning = lowestChargeSeenRunning
    }

    public var isMeasured: Bool { !observedCutoffs.isEmpty }

    /// Never above a charge the Mac has been seen running at: that would announce the end
    /// at a point this Mac is known to get past.
    public func cutoffMilliampHours(rawMaxCapacity: Int) -> Double {
        let threshold = isMeasured ? medianCutoff : Double(rawMaxCapacity) * Self.defaultReserveFraction
        guard let lowestChargeSeenRunning else { return threshold }
        return min(threshold, Double(lowestChargeSeenRunning))
    }

    /// Only a reading on battery counts: on the charger the Mac runs whatever the charge.
    @discardableResult
    public mutating func noteRunning(_ sample: BatterySample) -> Bool {
        guard sample.isDraining, !sample.externalConnected,
              sample.rawCharge < lowestChargeSeenRunning ?? .max
        else { return false }
        lowestChargeSeenRunning = sample.rawCharge
        return true
    }

    private var medianCutoff: Double {
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
