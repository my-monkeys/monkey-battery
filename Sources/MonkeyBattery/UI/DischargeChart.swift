import Charts
import MonkeyBatteryCore
import SwiftUI

/// The discharge so far, and where it is heading: a measured line, then a dashed one to
/// the shutdown point at the projected time.
struct DischargeChart: View {
    let samples: [BatterySample]
    let estimate: DrainEstimate?
    let cutoffMilliampHours: Double
    let level: AlertLevel
    let now: Date

    private struct Point: Identifiable {
        let date: Date
        let percent: Double
        var id: Date { date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("chart_title"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if measured.count < 2 {
                Text(L("chart_empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                chart.frame(height: 112)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(measured) { point in
                AreaMark(
                    x: .value("time", point.date),
                    y: .value("charge", point.percent),
                    series: .value("series", "area")
                )
                .foregroundStyle(LinearGradient(
                    colors: [Theme.tint(for: level).opacity(0.24), Theme.tint(for: level).opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("time", point.date),
                    y: .value("charge", point.percent),
                    series: .value("series", L("chart_charge"))
                )
                .foregroundStyle(Theme.tint(for: level))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            ForEach(projection) { point in
                LineMark(
                    x: .value("time", point.date),
                    y: .value("charge", point.percent),
                    series: .value("series", L("chart_projection"))
                )
                .foregroundStyle(Theme.tint(for: level).opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
            }

            if let end = projection.last {
                PointMark(x: .value("time", end.date), y: .value("charge", end.percent))
                    .symbolSize(28)
                    .foregroundStyle(Theme.tint(for: level))
            }

            RuleMark(y: .value("threshold", cutoffPercent))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .chartYScale(domain: 0...yMax)
        .chartXScale(domain: xDomain)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, yMax / 2, yMax]) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent)) %").font(.system(size: 9)).numeric()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: timeTicks) { _ in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.system(size: 9))
            }
        }
    }

    // MARK: - Data

    private var rawMax: Double { Double(samples.last?.rawMaxCapacity ?? 1) }

    private var cutoffPercent: Double { cutoffMilliampHours / rawMax * 100 }

    private var measured: [Point] {
        samples.map { Point(date: $0.updatedAt, percent: Double($0.rawCharge) / rawMax * 100) }
    }

    /// From the charge now to the threshold at the projected time — only when the end is
    /// close enough to fit, otherwise the measured part would be squashed into a corner.
    private var projection: [Point] {
        guard let estimate, estimate.secondsLeft(at: now) < 3 * 3600 else { return [] }
        return [
            Point(date: now, percent: estimate.projectedCharge / rawMax * 100),
            Point(date: max(now, estimate.emptyAt), percent: cutoffPercent),
        ]
    }

    /// A multiple of ten, so the middle gridline lands on a round figure too.
    private var yMax: Double {
        let highest = measured.map(\.percent).max() ?? 10
        return max(10, (highest / 10).rounded(.up) * 10)
    }

    /// Round times, three or so, kept clear of the right edge: Swift Charts centres each
    /// label on its tick and truncates the one that would overflow ("15…").
    private var timeTicks: [Date] {
        let domain = xDomain
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let step = [5.0, 10, 15, 30, 60, 120].map { $0 * 60 }.first { span / $0 <= 4 } ?? 4 * 3600
        let first = (domain.lowerBound.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        let lastUsable = domain.upperBound.addingTimeInterval(-span * 0.12)
        return stride(from: first, through: lastUsable.timeIntervalSinceReferenceDate, by: step)
            .map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    private var xDomain: ClosedRange<Date> {
        let start = measured.first?.date ?? now
        let end = projection.last?.date ?? measured.last?.date ?? now
        return start...max(end, start.addingTimeInterval(60))
    }
}
