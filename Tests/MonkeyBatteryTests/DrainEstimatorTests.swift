import Foundation
@testable import MonkeyBatteryCore
import Testing

@Suite("Drain estimate")
struct DrainEstimatorTests {
    private let cutoff = 160.0

    @Test("time left is the usable charge over the drain")
    func steadyDrain() throws {
        var estimator = DrainEstimator()
        estimator.ingest(reading(at: 0, charge: 800), readAt: t(0))
        let estimate = try #require(estimator.estimate(now: t(0), cutoffMilliampHours: cutoff))
        // 640 mAh above the threshold at 1.5 A.
        #expect(abs(estimate.secondsLeft(at: t(0)) - 1536) < 0.5)
        #expect(abs(estimate.watts - 16.65) < 0.01)
    }

    @Test("the countdown keeps running between two gauge updates")
    func projectionBetweenUpdates() throws {
        var estimator = DrainEstimator()
        estimator.ingest(reading(at: 0, charge: 800), readAt: t(0))
        let atUpdate = try #require(estimator.estimate(now: t(0), cutoffMilliampHours: cutoff))
        let later = try #require(estimator.estimate(now: t(45), cutoffMilliampHours: cutoff))
        #expect(abs(atUpdate.secondsLeft(at: t(0)) - later.secondsLeft(at: t(45)) - 45) < 0.5)
        #expect(abs(atUpdate.emptyAt.timeIntervalSince(later.emptyAt)) < 0.5)
    }

    @Test("a one-off spike moves the average a little, not all the way")
    func smoothing() throws {
        var estimator = DrainEstimator()
        for step in 0..<5 {
            estimator.ingest(reading(at: Double(step) * 30, charge: 800 - step * 12), readAt: t(Double(step) * 30))
        }
        estimator.ingest(reading(at: 150, charge: 740, milliamps: -6000), readAt: t(150))
        let estimate = try #require(estimator.estimate(now: t(150), cutoffMilliampHours: cutoff))
        let expected = 1500 + (1 - exp(-30.0 / DrainEstimator.smoothingSeconds)) * 4500
        #expect(abs(estimate.milliamps - expected) < 0.5)
    }

    @Test("the same update read twice counts once")
    func duplicateUpdate() throws {
        var estimator = DrainEstimator()
        estimator.ingest(reading(at: 0, charge: 800), readAt: t(0))
        estimator.ingest(reading(at: 0, charge: 800, milliamps: -6000), readAt: t(5))
        let estimate = try #require(estimator.estimate(now: t(5), cutoffMilliampHours: cutoff))
        #expect(estimate.milliamps == 1500)
    }

    @Test("right after unplugging, the stale charging current gives no estimate")
    func staleAfterUnplug() {
        var estimator = DrainEstimator()
        estimator.ingest(reading(at: 0, milliamps: 1448), readAt: t(3))
        #expect(estimator.estimate(now: t(3), cutoffMilliampHours: cutoff) == nil)
    }

    @Test("plugging in stops the drain before the gauge has caught up")
    func pluggedBeforeGaugeRefresh() {
        var estimator = DrainEstimator()
        estimator.ingest(reading(at: 0), readAt: t(0))
        // The charger is in, the gauge still reports the discharge it measured before.
        let stale = reading(at: 0, externalConnected: true)
        estimator.ingest(stale, readAt: t(4))
        #expect(!estimator.isDraining(stale))
        #expect(estimator.estimate(now: t(4), cutoffMilliampHours: cutoff) == nil)
    }

    @Test("a charger too weak for the load still counts as a drain once measured")
    func weakCharger() throws {
        var estimator = DrainEstimator()
        estimator.ingest(reading(at: 0), readAt: t(0))
        estimator.ingest(reading(at: 0, externalConnected: true), readAt: t(4))
        let fresh = reading(at: 40, charge: 790, milliamps: -400, externalConnected: true)
        estimator.ingest(fresh, readAt: t(41))
        #expect(estimator.isDraining(fresh))
        #expect(estimator.estimate(now: t(41), cutoffMilliampHours: cutoff) != nil)
    }

    @Test("the estimate is flagged settled after two minutes on battery")
    func settling() throws {
        var estimator = DrainEstimator()
        estimator.ingest(reading(at: 0), readAt: t(0))
        #expect(try #require(estimator.estimate(now: t(60), cutoffMilliampHours: cutoff)).isSettled == false)
        estimator.ingest(reading(at: 120, charge: 750), readAt: t(120))
        #expect(try #require(estimator.estimate(now: t(121), cutoffMilliampHours: cutoff)).isSettled)
    }

    @Test("below the threshold the estimate is zero, not negative")
    func belowThreshold() throws {
        var estimator = DrainEstimator()
        estimator.ingest(reading(at: 0, charge: 100), readAt: t(0))
        let estimate = try #require(estimator.estimate(now: t(0), cutoffMilliampHours: cutoff))
        #expect(estimate.secondsLeft(at: t(0)) == 0)
    }
}
