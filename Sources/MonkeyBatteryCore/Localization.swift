import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system, en, fr

    public var label: String {
        switch self {
        case .system: "Auto"
        case .en: "English"
        case .fr: "Français"
        }
    }

    public static var resolved: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: PreferenceKey.language) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: stored) ?? .system
        guard language == .system else { return language }
        return Locale.preferredLanguages.first?.hasPrefix("fr") == true ? .fr : .en
    }

    /// For number formatting: "16,6 W" in French, "16.6 W" in English.
    public static var locale: Locale {
        Locale(identifier: resolved == .fr ? "fr_FR" : "en_US")
    }
}

/// Localized string. Keys are English-ish slugs; unknown keys fall through unchanged so
/// a missing translation is visible rather than silently empty.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    let table = AppLanguage.resolved == .fr ? frenchStrings : englishStrings
    let format = table[key] ?? englishStrings[key] ?? key
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

public enum PreferenceKey {
    public static let language = "appLanguage"
    public static let showBelowPercent = "showBelowPercent"
    public static let alwaysShow = "alwaysShow"
    public static let alarmSound = "alarmSound"
    public static let notificationsEnabled = "notificationsEnabled"
    public static let didRegisterLoginItem = "didRegisterLoginItem"
}

package let englishStrings: [String: String] = [
    "app_name": "Monkey Battery",
    "simulation": "Simulation",
    "time_left": "Time left",
    "battery": "Battery",
    "no_battery": "This Mac has no battery to watch.",
    "until_sleep": "before the Mac puts itself to sleep",
    "measuring": "Measuring…",
    "measuring_detail": "The gauge reports the drain within a minute of unplugging.",
    "settling": "still averaging",
    "on_battery": "On battery",
    "on_charger": "On the charger",
    "charging": "Charging",
    "charged": "Charged",
    "weak_charger": "Charger too weak for the load",
    "hidden_hint": "The menu bar icon stays hidden until the battery drops below %d %%.",
    "placement_hint": "⌘-drag this icon next to the battery icon — macOS remembers the spot.",
    "drain": "Drain",
    "threshold": "Shutdown point",
    "threshold_guessed": "estimated",
    "threshold_guessed_help": "Not observed on this Mac yet. The first time the battery runs out, the app learns the real figure.",
    "threshold_measured": "measured on this Mac",
    "health": "Health",
    "cycles": "%d cycles",
    "chart_title": "This discharge",
    "chart_empty": "The chart fills in while the Mac runs on battery.",
    "chart_charge": "Charge",
    "chart_projection": "Projection",
    "settings": "Settings…",
    "settings_title": "Settings",
    "quit": "Quit",
    "check_for_updates": "Check for Updates…",
    "show_below": "Show the time left below",
    "always_show": "Always show in the menu bar",
    "always_show_help": "Otherwise the icon only appears when the battery runs low.",
    "alarm_sound": "Alarm sound",
    "notifications": "Notifications",
    "launch_at_login": "Open at login",
    "automatic_updates": "Check for updates automatically",
    "language": "Language",
    "version": "Version %@",
    "warning_title": "Battery low — about %@ left",
    "warning_body": "Plug in the charger. After that, the Mac puts itself to sleep.",
    "critical_title": "Plug in the charger now",
    "critical_body": "The Mac puts itself to sleep in %@.",
    "panel_title": "Plug in the charger",
    "panel_subtitle": "The Mac puts itself to sleep in",
    "panel_imminent": "any second now",
    "panel_dismiss": "Hide",
    "panel_dismiss_help": "Hidden until the last thirty seconds.",
    "simulate_plug": "Plug In (Simulation)",
    "simulate_unplug": "Unplug (Simulation)",
]

package let frenchStrings: [String: String] = [
    "app_name": "Monkey Battery",
    "simulation": "Simulation",
    "time_left": "Temps restant",
    "battery": "Batterie",
    "no_battery": "Ce Mac n'a pas de batterie à surveiller.",
    "until_sleep": "avant que le Mac ne se mette en veille",
    "measuring": "Mesure en cours…",
    "measuring_detail": "La jauge donne la consommation dans la minute qui suit le débranchement.",
    "settling": "moyenne en cours",
    "on_battery": "Sur batterie",
    "on_charger": "Sur secteur",
    "charging": "En charge",
    "charged": "Chargée",
    "weak_charger": "Chargeur trop faible pour la consommation",
    "hidden_hint": "L'icône reste masquée tant que la batterie est au-dessus de %d %%.",
    "placement_hint": "Glisse cette icône avec ⌘ à côté de la batterie : macOS retient l'emplacement.",
    "drain": "Consommation",
    "threshold": "Seuil d'extinction",
    "threshold_guessed": "estimé",
    "threshold_guessed_help": "Pas encore observé sur ce Mac. La première fois que la batterie se vide, l'app apprend la vraie valeur.",
    "threshold_measured": "mesuré sur ce Mac",
    "health": "Santé",
    "cycles": "%d cycles",
    "chart_title": "Cette décharge",
    "chart_empty": "Le graphique se remplit pendant que le Mac est sur batterie.",
    "chart_charge": "Charge",
    "chart_projection": "Projection",
    "settings": "Réglages…",
    "settings_title": "Réglages",
    "quit": "Quitter",
    "check_for_updates": "Rechercher des mises à jour…",
    "show_below": "Afficher le temps restant sous",
    "always_show": "Toujours afficher dans la barre des menus",
    "always_show_help": "Sinon l'icône n'apparaît que quand la batterie est faible.",
    "alarm_sound": "Son d'alarme",
    "notifications": "Notifications",
    "launch_at_login": "Ouvrir à la connexion",
    "automatic_updates": "Rechercher les mises à jour automatiquement",
    "language": "Langue",
    "version": "Version %@",
    "warning_title": "Batterie faible — environ %@",
    "warning_body": "Branche le chargeur. Passé ce délai, le Mac se met en veille de lui-même.",
    "critical_title": "Branche le chargeur maintenant",
    "critical_body": "Le Mac se met en veille dans %@.",
    "panel_title": "Branche le chargeur",
    "panel_subtitle": "Le Mac se met en veille dans",
    "panel_imminent": "d'une seconde à l'autre",
    "panel_dismiss": "Masquer",
    "panel_dismiss_help": "Masqué jusqu'aux trente dernières secondes.",
    "simulate_plug": "Brancher (simulation)",
    "simulate_unplug": "Débrancher (simulation)",
]
