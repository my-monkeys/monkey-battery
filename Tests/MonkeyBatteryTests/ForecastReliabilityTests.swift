import Foundation
@testable import MonkeyBatteryCore
import Testing

/// A discharge at a steady `actual` drain while the app forecast `forecast`, one point a
/// minute — so every ratio graded from it is `forecast ÷ actual`.
func steadyRecord(minutes: Int, startCharge: Int = 2000, forecast: Double, actual: Double) -> DischargeRecord {
    let points = (0...minutes).map { minute in
        DischargePoint(
            at: t(Double(minute) * 60),
            charge: startCharge - Int(actual * Double(minute) / 60),
            percent: 20,
            forecastMilliamps: forecast
        )
    }
    return DischargeRecord(points: points)
}

@Suite("Discharge record")
struct DischargeRecordTests {
    private func point(at seconds: TimeInterval, charge: Int = 800) -> DischargePoint {
        DischargePoint(at: t(seconds), charge: charge, percent: 10, forecastMilliamps: 1000)
    }

    @Test("readings closer than a minute are absorbed, not added")
    func spacing() {
        var record = DischargeRecord(first: point(at: 0))
        let absorbed = record.append(point(at: 30))
        let added = record.append(point(at: 65))
        #expect(absorbed && added)
        #expect(record.points.map(\.at) == [t(0), t(65)])
    }

    @Test("a gap longer than five minutes ends the record — a sleep is not a forecast")
    func gap() {
        var record = DischargeRecord(first: point(at: 0))
        let continued = record.append(point(at: 301 + 0))
        #expect(!continued)
        #expect(record.points.count == 1)
    }

    @Test("a record too short or too flat is not worth keeping")
    func worthKeeping() {
        #expect(steadyRecord(minutes: 10, forecast: 600, actual: 600).isWorthKeeping)
        #expect(!steadyRecord(minutes: 3, forecast: 600, actual: 600).isWorthKeeping)
        #expect(!steadyRecord(minutes: 10, forecast: 200, actual: 200).isWorthKeeping)
    }
}

@Suite("Forecast reliability")
struct ForecastReliabilityTests {
    @Test("in the last three minutes the forecast is taken as is")
    func exactAtTheEnd() {
        let band = ForecastReliability().band(secondsLeft: 150)
        #expect(band == ForecastBand(atLeast: 150, atMost: 150))
        #expect(!band.isWide)
    }

    @Test("until enough discharges are learnt, the range is wide and says so")
    func defaultsAreWide() {
        let reliability = ForecastReliability(records: [steadyRecord(minutes: 60, forecast: 1000, actual: 1000)])
        #expect(!reliability.isLearned)
        let band = reliability.band(secondsLeft: 20 * 60)
        #expect(band.isWide)
        #expect(band.atLeast < 12 * 60)
        #expect(band.atMost > 30 * 60)
    }

    @Test("the forecast always lies inside its range, and neither end climbs as time runs out",
          arguments: [
              ForecastReliability(),
              ForecastReliability(records: (0..<3).map { _ in steadyRecord(minutes: 120, forecast: 400, actual: 1200) }),
              ForecastReliability(records: (0..<3).map { _ in steadyRecord(minutes: 120, forecast: 1200, actual: 400) }),
          ])
    func monotone(reliability: ForecastReliability) {
        var previous = ForecastBand(atLeast: 0, atMost: 0)
        for seconds in stride(from: 0.0, through: 6 * 3600, by: 15) {
            let band = reliability.band(secondsLeft: seconds)
            #expect(band.atLeast <= seconds + 1e-9 && seconds <= band.atMost + 1e-9)
            #expect(band.atLeast >= previous.atLeast - 1e-9 && band.atMost >= previous.atMost - 1e-9)
            previous = band
        }
    }

    @Test("forecasts that came true narrow the range down to the forecast")
    func learnsAccurateForecasts() {
        let records = (0..<3).map { _ in steadyRecord(minutes: 150, forecast: 600, actual: 600) }
        let reliability = ForecastReliability(records: records)
        #expect(reliability.isLearned)
        let band = reliability.band(secondsLeft: 20 * 60)
        #expect(!band.isWide)
        #expect(abs(band.atLeast - 20 * 60) < 60)
    }

    @Test("a Mac that always drains twice as fast as forecast gets half the time at the low end")
    func learnsOptimism() {
        let records = (0..<3).map { _ in steadyRecord(minutes: 150, forecast: 300, actual: 600) }
        let band = ForecastReliability(records: records).band(secondsLeft: 40 * 60)
        #expect(abs(band.atLeast - 20 * 60) < 2 * 60)
    }

    @Test("two discharges are not enough to override the defaults")
    func needsThreeDischarges() {
        let records = (0..<2).map { _ in steadyRecord(minutes: 150, forecast: 600, actual: 600) }
        #expect(ForecastReliability(records: records).band(secondsLeft: 20 * 60) == ForecastReliability().band(secondsLeft: 20 * 60))
    }

    @Test("an upward correction of the gauge is not graded as a forecast")
    func gaugeCorrections() {
        var points = steadyRecord(minutes: 10, forecast: 600, actual: 600).points
        points[5].charge += 40
        let ratios = ForecastReliability.ratios(in: DischargeRecord(points: points)).flatMap { $0 }
        #expect(ratios.allSatisfy { abs($0 - 1) < 0.15 })
    }

    /// The discharge that prompted all this: at 10 %, on a near-idle Mac, the forecast was
    /// three hours; the load tripled and the charge reached 75 mAh 51 minutes later.
    @Test("on the 2026-11-07 discharge, the default low end covered what happened")
    func realDischarge() throws {
        let url = try #require(Bundle.module.url(forResource: "discharge-2026-11-07", withExtension: "json", subdirectory: "Fixtures"))
        let samples = try JSONDecoder().decode([BatterySample].self, from: Data(contentsOf: url))
        let end = try #require(samples.last)

        var estimator = DrainEstimator()
        var graded = false
        for sample in samples {
            estimator.ingest(sample, readAt: sample.updatedAt)
            guard sample.percent <= 10,
                  let estimate = estimator.estimate(now: sample.updatedAt, cutoffMilliampHours: Double(end.rawCharge))
            else { continue }

            let forecast = estimate.secondsLeft(at: sample.updatedAt)
            let actual = end.updatedAt.timeIntervalSince(sample.updatedAt)
            #expect(forecast > 2.5 * 3600, "the forecast that went wrong")
            #expect(ForecastReliability().band(secondsLeft: forecast).atLeast <= actual)
            graded = true
            break
        }
        #expect(graded)
    }
}
