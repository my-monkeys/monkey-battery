import Combine
import Foundation

/// Reads the battery on a timer and turns each reading into what the UI shows: the time
/// left, the alert level, the discharge so far.
@MainActor
public final class BatteryMonitor: ObservableObject {
    /// The gauge refreshes every 20 to 60 seconds; reading every five catches each
    /// refresh promptly without keeping the CPU awake on battery.
    static let drainingInterval: TimeInterval = 5
    static let idleInterval: TimeInterval = 30

    @Published public private(set) var sample: BatterySample?
    @Published public private(set) var estimate: DrainEstimate?
    @Published public private(set) var isDraining = false
    @Published public private(set) var level: AlertLevel = .none
    @Published public private(set) var discharge: [BatterySample] = []
    @Published public private(set) var calibration: ShutdownCalibration

    public var thresholds: AlertThresholds {
        didSet { evaluate() }
    }

    /// Called once each time the level rises. Falling back to `.none` is not announced:
    /// the observers read `level` for that.
    public var onEscalation: ((AlertLevel) -> Void)?

    private let source: BatterySource
    private var journal: SampleJournal
    private var estimator = DrainEstimator()
    private var escalation = AlertEscalation()
    private var timer: Timer?
    private var powerObserver: PowerSourceObserver?

    public init(source: BatterySource, journal: SampleJournal, thresholds: AlertThresholds) {
        self.source = source
        self.journal = journal
        self.thresholds = thresholds
        calibration = journal.calibration
    }

    public var now: Date { source.now }

    public var cutoffMilliampHours: Double? {
        sample.map { calibration.cutoffMilliampHours(rawMaxCapacity: $0.rawMaxCapacity) }
    }

    public func start() {
        learnFromGap()
        tick()
        powerObserver = PowerSourceObserver { [weak self] in self?.tick() }
    }

    public func tick() {
        guard let reading = source.read() else { return }
        estimator.ingest(reading, readAt: now)
        journal.append(reading)
        sample = reading
        evaluate()
        recordHeartbeat()
        journal.save(now: now, urgent: level >= .low)
        scheduleNextTick()
    }

    /// The last chance to write the heartbeat before a sleep that may be the end.
    public func systemWillSleep() {
        journal.save(now: now, urgent: true)
    }

    public func systemDidWake() {
        learnFromGap()
        tick()
    }

    // MARK: - Private

    private func evaluate() {
        guard let sample else { return }
        let draining = estimator.isDraining(sample)
        let cutoff = calibration.cutoffMilliampHours(rawMaxCapacity: sample.rawMaxCapacity)
        let estimate = draining ? estimator.estimate(now: now, cutoffMilliampHours: cutoff) : nil
        let computed = thresholds.level(for: sample, isDraining: draining, secondsLeft: estimate?.secondsLeft(at: now))
        let (level, isNew) = escalation.update(computed: computed, onBattery: draining || !sample.externalConnected)

        self.estimate = estimate
        isDraining = draining
        discharge = journal.currentDischarge
        if self.level != level { self.level = level }
        if isNew { onEscalation?(level) }
    }

    private func recordHeartbeat() {
        guard isDraining, let sample, let estimate else { return }
        journal.heartbeat = Heartbeat(aliveAt: now, sample: sample, projectedCharge: estimate.projectedCharge)
    }

    /// A relaunch or a wake: if the last heartbeat was taken at the very end, the Mac
    /// died there, and that is this Mac's real shutdown point.
    private func learnFromGap() {
        guard let heartbeat = journal.heartbeat, let first = source.read() else { return }
        if journal.calibration.recordShutdownIfAny(lastHeartbeat: heartbeat, firstAfterGap: first, gapEndedAt: now) {
            calibration = journal.calibration
        }
        // Consumed either way: the same heartbeat must not be counted at the next wake.
        journal.heartbeat = nil
        journal.save(now: now, urgent: true)
    }

    private func scheduleNextTick() {
        let interval = isDraining || level > .none ? Self.drainingInterval : Self.idleInterval
        guard timer?.timeInterval != interval || timer?.isValid != true else { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
