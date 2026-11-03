import Foundation
import MonkeyBatteryCore

/// The monitor's state, worded once for every surface that shows it — menu bar, popover,
/// panel and notifications — so they cannot disagree about the time left.
struct BatteryPresentation {
    let sample: BatterySample?
    let estimate: DrainEstimate?
    let isDraining: Bool
    let level: AlertLevel
    let now: Date

    @MainActor
    init(_ monitor: BatteryMonitor, now: Date? = nil) {
        sample = monitor.sample
        estimate = monitor.estimate
        isDraining = monitor.isDraining
        level = monitor.level
        self.now = now ?? monitor.now
    }

    var percent: Int { sample?.percent ?? 0 }

    var secondsLeft: TimeInterval? { estimate?.secondsLeft(at: now) }

    var isOnBattery: Bool { isDraining || sample?.externalConnected == false }

    var menuBar: MenuBarContent {
        MenuBarContent(
            percent: percent,
            text: isOnBattery ? (secondsLeft.map(TimeLeft.short) ?? "…") : "\(percent) %",
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
