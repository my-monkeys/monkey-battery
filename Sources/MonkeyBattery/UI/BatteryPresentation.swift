import Foundation
import MonkeyBatteryCore

/// The monitor's state, worded once for every surface that shows it — menu bar, popover,
/// panel and notifications — so they cannot disagree about the time left.
struct BatteryPresentation {
    let sample: BatterySample?
    let estimate: DrainEstimate?
    /// Where the time left can really land, learnt from past discharges.
    let band: ForecastBand?
    let reliability: ForecastReliability
    let isDraining: Bool
    let level: AlertLevel
    let now: Date

    @MainActor
    init(_ monitor: BatteryMonitor, now: Date? = nil) {
        sample = monitor.sample
        estimate = monitor.estimate
        isDraining = monitor.isDraining
        level = monitor.level
        let now = now ?? monitor.now
        self.now = now
        band = monitor.band(at: now)
        reliability = monitor.reliability
    }

    var percent: Int { sample?.percent ?? 0 }

    /// At the current drain.
    var secondsLeft: TimeInterval? { estimate?.secondsLeft(at: now) }

    /// What can be counted on, whatever the drain does next — the figure every surface
    /// leads with, and the one the alerts go by.
    var atLeast: TimeInterval? { band?.atLeast }

    var isOnBattery: Bool { isDraining || sample?.externalConnected == false }

    var menuBar: MenuBarContent {
        MenuBarContent(
            percent: percent,
            text: isOnBattery ? (atLeast.map(TimeLeft.short) ?? "…") : "\(percent) %",
            isCharging: sample?.isCharging == true,
            isAlarm: level >= .critical
        )
    }

    var status: String {
        guard let sample else { return "—" }
        if isDraining, sample.externalConnected { return L("weak_charger") }
        if isOnBattery { return L("on_battery") }
        if sample.isCharging { return L("charging") }
        return sample.percent >= 100 ? L("charged") : L("on_charger")
    }
}
