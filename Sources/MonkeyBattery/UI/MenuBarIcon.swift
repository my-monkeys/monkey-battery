import AppKit
import MonkeyBatteryCore

/// What the status item shows: a battery drawn to the real charge, then one figure.
struct MenuBarContent: Equatable {
    var percent: Int
    /// `25 min`, `1:45`, `…` while measuring, or the percentage on the charger.
    var text: String
    var isCharging: Bool
    /// Red instead of the menu bar's own colour, from the critical level on.
    var isAlarm: Bool
}

private enum Metrics {
    static let height: CGFloat = 18
    static let bodyWidth: CGFloat = 21
    static let bodyHeight: CGFloat = 10
    static let corner: CGFloat = 2.6
    static let stroke: CGFloat = 1
    static let inset: CGFloat = 1.5
    static let nubWidth: CGFloat = 1.6
    static let nubHeight: CGFloat = 3.6
    static let boltSize: CGFloat = 9
    static let gap: CGFloat = 4
    static let fontSize: CGFloat = 12
}

/// A template image, so macOS picks the colour that contrasts with the menu bar — except
/// in alarm, where the point is precisely to stop blending in.
func renderMenuBarIcon(_ content: MenuBarContent) -> NSImage {
    let color = content.isAlarm ? Theme.alarmNSColor : NSColor.black
    let text = NSAttributedString(string: content.text, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: Metrics.fontSize, weight: .medium),
        .foregroundColor: color,
    ])
    let textSize = text.size()
    let batteryWidth = Metrics.bodyWidth + Metrics.nubWidth + 0.5
    let boltWidth = content.isCharging ? Metrics.boltSize + 1 : 0
    let width = batteryWidth + boltWidth + Metrics.gap + ceil(textSize.width)

    let image = NSImage(size: NSSize(width: width, height: Metrics.height), flipped: true) { _ in
        drawBattery(percent: content.percent, color: color)
        if content.isCharging {
            drawBolt(x: batteryWidth + 1, color: color)
        }
        text.draw(at: NSPoint(x: batteryWidth + boltWidth + Metrics.gap, y: (Metrics.height - textSize.height) / 2))
        return true
    }
    image.isTemplate = !content.isAlarm
    return image
}

private func drawBattery(percent: Int, color: NSColor) {
    let top = (Metrics.height - Metrics.bodyHeight) / 2
    let body = NSRect(x: Metrics.stroke / 2, y: top, width: Metrics.bodyWidth, height: Metrics.bodyHeight)

    let outline = NSBezierPath(roundedRect: body, xRadius: Metrics.corner, yRadius: Metrics.corner)
    outline.lineWidth = Metrics.stroke
    color.withAlphaComponent(0.45).setStroke()
    outline.stroke()

    let nub = NSRect(
        x: body.maxX + 0.5,
        y: (Metrics.height - Metrics.nubHeight) / 2,
        width: Metrics.nubWidth,
        height: Metrics.nubHeight
    )
    color.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: nub, xRadius: 0.8, yRadius: 0.8).fill()

    // Never fully empty: a battery drawn with nothing in it reads as "no battery".
    let inner = body.insetBy(dx: Metrics.inset, dy: Metrics.inset)
    let fraction = min(1, max(0.08, Double(percent) / 100))
    let filled = NSRect(x: inner.minX, y: inner.minY, width: inner.width * fraction, height: inner.height)
    color.setFill()
    NSBezierPath(roundedRect: filled, xRadius: Metrics.corner - 1, yRadius: Metrics.corner - 1).fill()
}

private func drawBolt(x: CGFloat, color: NSColor) {
    let configuration = NSImage.SymbolConfiguration(pointSize: Metrics.boltSize, weight: .bold)
    guard let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return }
    let box = NSRect(x: x, y: (Metrics.height - Metrics.boltSize) / 2, width: Metrics.boltSize, height: Metrics.boltSize)
    // Tinted by hand: a symbol drawn into a template image keeps its own black otherwise,
    // which is right, but in alarm it has to follow the red.
    let tinted = NSImage(size: box.size, flipped: false) { rect in
        bolt.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    // `respectFlipped`: the surrounding image is drawn flipped, and without it the symbol
    // lands upside down.
    tinted.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}
