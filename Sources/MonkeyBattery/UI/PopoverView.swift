import MonkeyBatteryCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: BatteryMonitor
    let isSimulation: Bool

    @AppStorage(PreferenceKey.alwaysShow) private var alwaysShow = false
    @AppStorage(PreferenceKey.showBelowPercent) private var showBelow = AlertThresholds.defaultShowBelowPercent

    var body: some View {
        // Redrawn every second: the headline is a countdown, and the gauge only refreshes
        // every 20 to 60 seconds.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content(BatteryPresentation(monitor))
        }
    }

    @ViewBuilder
    private func content(_ presentation: BatteryPresentation) -> some View {
        if presentation.sample == nil {
            noBattery
        } else {
            details(presentation)
        }
    }

    /// A Mac mini or an iMac: nothing to measure, and nothing to pretend about.
    private var noBattery: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleBar
            Text(L("no_battery"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            footer
        }
        .padding(16)
        .frame(width: Theme.popoverWidth)
    }

    private func details(_ presentation: BatteryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            titleBar
            Headline(presentation: presentation)
            ChargeBar(presentation: presentation)

            Divider()

            // On the charger with nothing measured yet, the chart would only be a
            // placeholder taking a third of the popover.
            if presentation.isOnBattery || !monitor.discharge.isEmpty {
                DischargeChart(
                    samples: monitor.discharge,
                    estimate: presentation.estimate,
                    band: presentation.band,
                    cutoffMilliampHours: monitor.cutoffMilliampHours ?? 0,
                    level: presentation.level,
                    now: presentation.now
                )

                Divider()
            }

            DetailRows(presentation: presentation, calibration: monitor.calibration,
                       cutoffMilliampHours: monitor.cutoffMilliampHours ?? 0)

            if presentation.level == .none, !alwaysShow {
                hint(L("hidden_hint", showBelow) + " " + L("placement_hint"))
            }

            footer
        }
        .padding(16)
        .frame(width: Theme.popoverWidth)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Text(L("app_name"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if isSimulation {
                Text(L("simulation"))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassChip(isProminent: true)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Button(L("settings")) {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            Spacer()
            Button(L("quit")) { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

private struct Headline: View {
    let presentation: BatteryPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.isOnBattery ? L("time_left") : L("battery"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if !presentation.isOnBattery {
                Text("\(presentation.percent) %")
                    .numeric()
                    .font(.system(size: 34, weight: .semibold))
            } else if let band = presentation.band, let likely = presentation.secondsLeft {
                Text(band.isWide ? TimeLeft.range(band.atLeast, band.atMost) : TimeLeft.long(band.atLeast))
                    .numeric()
                    .font(.system(size: 34, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.numberTint(for: presentation.level))
                    .contentTransition(.numericText(countsDown: true))
                Text(subline(band: band, likely: likely))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("measuring"))
                    .font(.system(size: 22, weight: .semibold))
                Text(L("measuring_detail"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Under a range, the figure at the current drain, so the range reads as "it depends
    /// on what you do next" rather than as vagueness.
    private func subline(band: ForecastBand, likely: TimeInterval) -> String {
        var parts = [L("until_sleep")]
        if band.isWide { parts.append(L("at_current_drain", TimeLeft.long(likely))) }
        if presentation.estimate?.isSettled == false { parts.append(L("settling")) }
        return parts.joined(separator: " · ")
    }
}

private struct ChargeBar: View {
    let presentation: BatteryPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(presentation.status)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                // On the charger the headline is already the percentage.
                if presentation.isOnBattery {
                    Text("\(presentation.percent) %")
                        .numeric()
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.numberTint(for: presentation.level))
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(Theme.trackOpacity))
                    Capsule()
                        .fill(Theme.tint(for: presentation.level))
                        .frame(width: max(4, proxy.size.width * Double(presentation.percent) / 100))
                }
            }
            .frame(height: 6)

            if let sample = presentation.sample {
                Text("\(sample.rawCharge.formatted(.number.locale(AppLanguage.locale))) / \(sample.rawMaxCapacity.formatted(.number.locale(AppLanguage.locale))) mAh")
                    .numeric()
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DetailRows: View {
    let presentation: BatteryPresentation
    let calibration: ShutdownCalibration
    let cutoffMilliampHours: Double

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            if presentation.isDraining, let estimate = presentation.estimate {
                row(L("drain"), "\(Figures.watts(estimate.watts)) · \(Figures.amps(estimate.milliamps))")
            }
            row(
                L("threshold"),
                "\(Int(cutoffMilliampHours.rounded(.up))) mAh · \(calibration.isMeasured ? L("threshold_measured") : L("threshold_guessed"))"
            )
            .help(calibration.isMeasured ? "" : L("threshold_guessed_help"))

            row(L("forecast"), forecastState)
                .help(L("forecast_help"))

            if let sample = presentation.sample {
                row(L("health"), "\(Figures.percent(sample.healthFraction)) · \(L("cycles", sample.cycleCount))")
            }
        }
    }

    private var forecastState: String {
        let reliability = presentation.reliability
        return reliability.isLearned
            ? L("forecast_learned", reliability.discharges)
            : L("forecast_learning", reliability.discharges, ForecastReliability.minimumDischarges)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .numeric()
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("fr.mymonkey.monkeybattery.openSettings")
}
