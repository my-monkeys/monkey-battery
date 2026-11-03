import AppKit
import MonkeyBatteryCore
import SwiftUI

/// Renders the menu bar states, the popover and the alert panel to PNG files, so the
/// layout can be checked without running a battery down. Used for the README too:
///
///     "Monkey Battery.app/Contents/MacOS/MonkeyBattery" --render-preview <dir>
@MainActor
enum PreviewRenderer {
    static func run(outputDirectory: String) {
        // Both appearances, because a colour that reads on one can vanish on the other and
        // there is no way to tell without looking.
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let isDark = appearance == .darkAqua
            render(into: URL(fileURLWithPath: outputDirectory).appendingPathComponent(isDark ? "dark" : "light"), isDark: isDark)
        }
    }

    private static func render(into directory: URL, isDark: Bool) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let menuBarCases: [(String, MenuBarContent)] = [
            ("menubar-low", MenuBarContent(percent: 7, text: "25 min", isCharging: false, isAlarm: false)),
            ("menubar-warning", MenuBarContent(percent: 3, text: "4 min", isCharging: false, isAlarm: false)),
            ("menubar-critical", MenuBarContent(percent: 2, text: "1:45", isCharging: false, isAlarm: true)),
            ("menubar-measuring", MenuBarContent(percent: 8, text: "…", isCharging: false, isAlarm: false)),
            ("menubar-charging", MenuBarContent(percent: 64, text: "64 %", isCharging: true, isAlarm: false)),
        ]
        for (name, content) in menuBarCases {
            write(menuBarStrip(renderMenuBarIcon(content), isDark: isDark), to: directory.appendingPathComponent("\(name).png"))
        }

        let low = scriptedMonitor(endingAtPercent: 7)
        capture(PopoverView(monitor: low, isSimulation: false), to: directory.appendingPathComponent("popover-low.png"))

        let critical = scriptedMonitor(endingAtPercent: 2.55)
        capture(PopoverView(monitor: critical, isSimulation: false), to: directory.appendingPathComponent("popover-critical.png"))
        capture(AlertCardView(monitor: critical, onDismiss: {}).padding(24), to: directory.appendingPathComponent("panel.png"), background: false)

        let charging = chargingMonitor()
        capture(PopoverView(monitor: charging, isSimulation: false), to: directory.appendingPathComponent("popover-charging.png"))

        print("wrote previews to \(directory.path)")
    }

    // MARK: - Scripted batteries

    /// A believable afternoon: from 23 % down to the given level, readings every thirty
    /// seconds, the load wandering between about 1 and 2 A.
    private static func scriptedMonitor(endingAtPercent target: Double) -> BatteryMonitor {
        let rawMax = 8215.0
        var charge = rawMax * 0.23
        var date = Date().addingTimeInterval(-3 * 3600)
        var samples: [BatterySample] = []
        var step = 0
        while charge > rawMax * target / 100 {
            let milliamps = 1500 + 550 * sin(Double(step) / 9) + (step % 7 == 0 ? 280 : 0)
            samples.append(sample(at: date, charge: charge, rawMax: rawMax, milliamps: -Int(milliamps)))
            charge -= milliamps * 30 / 3600
            date = date.addingTimeInterval(30)
            step += 1
        }
        return monitor(replaying: samples)
    }

    private static func chargingMonitor() -> BatteryMonitor {
        let reading = sample(at: Date(), charge: 8215 * 0.64, rawMax: 8215, milliamps: 2900, charging: true)
        return monitor(replaying: [reading])
    }

    private static func sample(at date: Date, charge: Double, rawMax: Double, milliamps: Int, charging: Bool = false) -> BatterySample {
        BatterySample(
            updatedAt: date,
            rawCharge: Int(charge),
            rawMaxCapacity: Int(rawMax),
            designCapacity: 8579,
            percent: Int((charge / rawMax * 100).rounded(.up)),
            millivolts: 11_100,
            milliamps: milliamps,
            isCharging: charging,
            externalConnected: charging,
            atCriticalLevel: false,
            cycleCount: 42
        )
    }

    private static func monitor(replaying samples: [BatterySample]) -> BatteryMonitor {
        let source = ScriptedBatterySource(samples: samples)
        let monitor = BatteryMonitor(source: source, journal: SampleJournal(url: nil), thresholds: AlertThresholds())
        for _ in samples { monitor.tick() }
        return monitor
    }

    // MARK: - Output

    /// The template image on a menu bar coloured background, at 2×, the way it is seen.
    private static func menuBarStrip(_ icon: NSImage, isDark: Bool) -> NSImage {
        let padding: CGFloat = 10
        let size = NSSize(width: icon.size.width + padding * 2, height: 24)
        let background = isDark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        let foreground = isDark ? NSColor.white : NSColor.black

        let tinted = NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            if icon.isTemplate {
                foreground.set()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        return NSImage(size: size, flipped: false) { rect in
            background.setFill()
            rect.fill()
            tinted.draw(in: NSRect(x: padding, y: (size.height - icon.size.height) / 2,
                                   width: icon.size.width, height: icon.size.height))
            return true
        }
    }

    private static func write(_ image: NSImage, to url: URL) {
        let scale: CGFloat = 2
        let pixels = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func capture(_ view: some View, to url: URL, background: Bool = true) {
        let root = view.background(background ? Color(nsColor: .windowBackgroundColor) : .clear)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        hosting.layoutSubtreeIfNeeded()

        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}

/// Replays a fixed list of readings, one per tick, with a clock that follows them.
@MainActor
private final class ScriptedBatterySource: BatterySource {
    private let samples: [BatterySample]
    private var index = 0
    private(set) var now: Date

    init(samples: [BatterySample]) {
        self.samples = samples
        now = samples.first?.updatedAt ?? Date()
    }

    func read() -> BatterySample? {
        guard !samples.isEmpty else { return nil }
        let sample = samples[min(index, samples.count - 1)]
        index += 1
        now = sample.updatedAt.addingTimeInterval(3)
        return sample
    }
}
