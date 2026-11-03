import MonkeyBatteryCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var updater: Updater

    @AppStorage(PreferenceKey.language) private var language = AppLanguage.system.rawValue
    @AppStorage(PreferenceKey.showBelowPercent) private var showBelow = AlertThresholds.defaultShowBelowPercent
    @AppStorage(PreferenceKey.alwaysShow) private var alwaysShow = false
    @AppStorage(PreferenceKey.alarmSound) private var alarmSound = true
    @AppStorage(PreferenceKey.notificationsEnabled) private var notifications = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Picker(L("show_below"), selection: $showBelow) {
                ForEach(AlertThresholds.showOptions, id: \.self) { percent in
                    Text("\(percent) %").tag(percent)
                }
            }

            Toggle(isOn: $alwaysShow) {
                Text(L("always_show"))
                Text(L("always_show_help"))
            }

            Divider()

            Toggle(L("alarm_sound"), isOn: $alarmSound)
            Toggle(L("notifications"), isOn: $notifications)

            Toggle(L("launch_at_login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }

            Toggle(L("automatic_updates"), isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))

            Picker(L("language"), selection: $language) {
                ForEach(AppLanguage.allCases, id: \.rawValue) { value in
                    Text(value.label).tag(value.rawValue)
                }
            }

            if let version = Updater.displayedVersion {
                Text(L("version", version))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        // Must match the window in AppDelegate.openSettings.
        .frame(width: 420, height: 380)
    }
}
