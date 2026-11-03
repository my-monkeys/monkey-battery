import AppKit
import MonkeyBatteryCore
import SwiftUI

/// One accent, two warning states, everything else neutral — the palette of Monkey
/// Claude Usage, so the two sit side by side in the menu bar as one family.
///
/// Nothing here comes from `.accentColor`: the system accent is whatever the user picked
/// for their buttons. Each colour carries a lighter variant for dark mode and a deeper one
/// for light, because a single sRGB value cannot be right on both.
enum Theme {
    static let popoverWidth: CGFloat = 320
    static let trackOpacity: Double = 0.12

    /// The terracotta of the app icon's battery.
    static let accent = adaptive(dark: (0.898, 0.510, 0.376), light: (0.769, 0.365, 0.235))
    static let warning = adaptive(dark: (0.949, 0.667, 0.263), light: (0.776, 0.494, 0.106))
    static let critical = adaptive(dark: (0.945, 0.353, 0.376), light: (0.816, 0.180, 0.208))

    /// The panel stays this red in both appearances: it has to read as an alarm over
    /// whatever window happens to be behind it.
    static let alarm = Color(nsColor: NSColor(srgbRed: 0.761, green: 0.153, blue: 0.180, alpha: 1))
    static let alarmNSColor = NSColor(srgbRed: 0.886, green: 0.231, blue: 0.259, alpha: 1)

    static func tint(for level: AlertLevel) -> Color {
        switch level {
        case .none, .low: accent
        case .warning: warning
        case .critical, .final: critical
        }
    }

    /// Figures stay plain text until something is worth warning about. Tinting every one
    /// costs contrast and spends the reader's attention on the ordinary case.
    static func numberTint(for level: AlertLevel) -> Color {
        level >= .warning ? tint(for: level) : .primary
    }

    private static func adaptive(
        dark: (Double, Double, Double),
        light: (Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (red, green, blue) = isDark ? dark : light
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        })
    }
}

extension Text {
    /// Figures that change every few seconds should not make the layout jitter.
    func numeric() -> Text { self.monospacedDigit() }
}

enum Figures {
    static func watts(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale))) W"
    }

    static func amps(_ milliamps: Double) -> String {
        "\((milliamps / 1000).formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.locale))) A"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }
}
