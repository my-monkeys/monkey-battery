import AppKit
import MonkeyBatteryCore
import SwiftUI

/// The part that cannot be missed: a red card at the top of the screen, above every
/// window, every Space and every full-screen app, counting down to the forced sleep.
///
/// A notification is not enough — it is what people miss today. A banner leaves after
/// five seconds, a Focus mode swallows it, and the notification type that overrides Focus
/// is reserved by Apple. This panel answers to none of those rules.
@MainActor
final class AlertPanelController {
    private static let size = NSSize(width: 440, height: 132)
    private static let topMargin: CGFloat = 14

    private var panel: NSPanel?

    var isShown: Bool { panel?.isVisible == true }

    func show(monitor: BatteryMonitor, onDismiss: @escaping () -> Void) {
        let panel = self.panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: AlertCardView(monitor: monitor, onDismiss: onDismiss))
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        // Non-activating: it must not take the keyboard from whatever is being typed — a
        // stray Return would otherwise land on its button instead of in the document.
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Top centre of the screen the pointer is on — where the user is looking.
    private func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - Self.size.width / 2,
            y: visible.maxY - Self.size.height - Self.topMargin
        ))
    }
}

struct AlertCardView: View {
    @ObservedObject var monitor: BatteryMonitor
    let onDismiss: () -> Void

    @State private var pulse = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            card(BatteryPresentation(monitor))
        }
        .onAppear { pulse = true }
    }

    private func card(_ presentation: BatteryPresentation) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "battery.0percent")
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .opacity(pulse ? 1 : 0.45)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

            VStack(alignment: .leading, spacing: 3) {
                Text(L("panel_title"))
                    .font(.system(size: 17, weight: .bold))
                Text(L("panel_subtitle"))
                    .font(.system(size: 12))
                    .opacity(0.85)
                Text(countdown(presentation))
                    .numeric()
                    .font(.system(size: 30, weight: .bold))
                    .contentTransition(.numericText(countsDown: true))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                Text(detail(presentation))
                    .numeric()
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.85)
                Button(L("panel_dismiss"), action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .help(presentation.level < .final ? L("panel_dismiss_help") : "")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .frame(width: 440, height: 132)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.alarm)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(pulse ? 0.55 : 0.12), lineWidth: 2)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
        )
    }

    private func countdown(_ presentation: BatteryPresentation) -> String {
        guard let seconds = presentation.atLeast else { return "…" }
        return seconds < 1 ? L("panel_imminent") : TimeLeft.clock(Int(seconds))
    }

    private func detail(_ presentation: BatteryPresentation) -> String {
        guard let estimate = presentation.estimate else { return "\(presentation.percent) %" }
        return "\(presentation.percent) % · \(Figures.watts(estimate.watts))"
    }
}
