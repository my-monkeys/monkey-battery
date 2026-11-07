import AppKit
import MonkeyBatteryCore
import UserNotifications

/// What each level does, beyond the menu bar: one notification at the warning, then the
/// panel and an alarm that repeats faster as the end gets closer.
@MainActor
final class AlertCenter {
    private static let warningSound = "Glass"
    private static let alarmSound = "Sosumi"
    private static let criticalAlarmInterval: TimeInterval = 15
    private static let finalAlarmInterval: TimeInterval = 5

    private let monitor: BatteryMonitor
    private let panel = AlertPanelController()
    private var alarm: Timer?
    /// Set by "Hide": the panel and the alarm stay away until the next level up.
    private var dismissedAt: AlertLevel?

    /// `UNUserNotificationCenter` traps outside an app bundle, which is what `swift run`
    /// produces.
    private let canNotify = Bundle.main.bundleIdentifier != nil

    init(monitor: BatteryMonitor) {
        self.monitor = monitor
        if canNotify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func escalated(to level: AlertLevel) {
        switch level {
        case .none, .low:
            break
        case .warning:
            notify(title: L("warning_title", timeLeft), body: L("warning_body"))
            play(Self.warningSound)
        case .critical:
            notify(title: L("critical_title"), body: L("critical_body", timeLeft))
            showPanel()
            startAlarm(every: Self.criticalAlarmInterval)
        case .final:
            dismissedAt = nil
            showPanel()
            startAlarm(every: Self.finalAlarmInterval)
        }
    }

    /// Called on every update: the moment the drain stops — charger plugged in — the panel
    /// and the alarm go, without waiting for anything else.
    func levelDidChange(_ level: AlertLevel) {
        guard level < .critical else { return }
        panel.close()
        stopAlarm()
        dismissedAt = nil
    }

    // MARK: - Private

    private var timeLeft: String {
        BatteryPresentation(monitor).atLeast.map(TimeLeft.long) ?? "—"
    }

    private func showPanel() {
        guard dismissedAt == nil else { return }
        panel.show(monitor: monitor) { [weak self] in self?.dismiss() }
    }

    private func dismiss() {
        dismissedAt = monitor.level
        panel.close()
        stopAlarm()
    }

    private func startAlarm(every interval: TimeInterval) {
        guard dismissedAt == nil else { return }
        stopAlarm()
        play(Self.alarmSound)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.play(Self.alarmSound) }
        }
        RunLoop.main.add(timer, forMode: .common)
        alarm = timer
    }

    private func stopAlarm() {
        alarm?.invalidate()
        alarm = nil
    }

    private func play(_ name: String) {
        guard UserDefaults.standard.object(forKey: PreferenceKey.alarmSound) as? Bool ?? true else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func notify(title: String, body: String) {
        guard canNotify,
              UserDefaults.standard.object(forKey: PreferenceKey.notificationsEnabled) as? Bool ?? true
        else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // One identifier: the critical notice replaces the warning instead of stacking.
        let request = UNNotificationRequest(identifier: "battery", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
