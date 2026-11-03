import AppKit
import Combine
import MonkeyBatteryCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// How long the icon stays up after a launch or a reopen whatever the battery says, so
    /// there is time to ⌘-drag it into place.
    private static let placementSeconds: TimeInterval = 60
    /// The name macOS files the item's position under. Changing it loses the spot every
    /// user dragged the icon to.
    private static let autosaveName = "MonkeyBattery"

    private var monitor: BatteryMonitor!
    private var alerts: AlertCenter!
    private var simulation: SimulatedBatterySource?
    // Built after the `--render-preview` early exit: that path never gets an event loop,
    // and a Sparkle updater started there would look for a feed it must not fetch.
    private var updater: Updater!

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var redrawTimer: Timer?
    private var observations: Set<AnyCancellable> = []
    private var placementUntil = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
           index + 1 < CommandLine.arguments.count {
            PreviewRenderer.run(outputDirectory: CommandLine.arguments[index + 1])
            NSApplication.shared.terminate(nil)
            return
        }

        startMonitor(simulated: CommandLine.arguments.contains("--simulate"))
        updater = Updater()
        setUpStatusItem()
        observeSystem()
        registerLoginItemOnce()

        placementUntil = Date().addingTimeInterval(Self.placementSeconds)
        monitor.start()
        redraw()
    }

    /// Opening the app again — Spotlight, Finder, Launchpad — while it runs hidden is how
    /// one gets at it when the battery is fine. Show the icon and what it knows.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        placementUntil = Date().addingTimeInterval(Self.placementSeconds)
        redraw()
        if !popover.isShown { togglePopover() }
        return false
    }

    // MARK: - Setup

    private func startMonitor(simulated: Bool) {
        let source: BatterySource
        let journal: SampleJournal
        if simulated {
            let simulation = SimulatedBatterySource()
            self.simulation = simulation
            source = simulation
            journal = SampleJournal(url: nil)
        } else {
            source = LiveBatterySource()
            journal = SampleJournal(url: SampleJournal.defaultURL)
        }

        monitor = BatteryMonitor(source: source, journal: journal, thresholds: storedThresholds)
        alerts = AlertCenter(monitor: monitor)
        monitor.onEscalation = { [weak self] level in self?.alerts.escalated(to: level) }

        // objectWillChange fires before the change; hopping to the next run loop pass reads
        // the new values.
        monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &observations)
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.autosaveName
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.preferencesChanged() }
            .store(in: &observations)
    }

    /// The app is only useful if it is running when the battery runs out, so it adds itself
    /// to the login items once — macOS says so in a notification, and Settings undoes it.
    /// Only from /Applications: a development build registered from dist/ would linger.
    private func registerLoginItemOnce() {
        let defaults = UserDefaults.standard
        guard simulation == nil,
              Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !defaults.bool(forKey: PreferenceKey.didRegisterLoginItem)
        else { return }
        try? SMAppService.mainApp.register()
        defaults.set(true, forKey: PreferenceKey.didRegisterLoginItem)
    }

    private var storedThresholds: AlertThresholds {
        let stored = UserDefaults.standard.integer(forKey: PreferenceKey.showBelowPercent)
        return AlertThresholds(showBelowPercent: stored > 0 ? stored : AlertThresholds.defaultShowBelowPercent)
    }

    // MARK: - System events

    @objc private func willSleep() {
        monitor.systemWillSleep()
    }

    @objc private func didWake() {
        monitor.systemDidWake()
    }

    private func preferencesChanged() {
        let thresholds = storedThresholds
        if monitor.thresholds != thresholds { monitor.thresholds = thresholds }
        redraw()
    }

    // MARK: - Status item

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        statusItem.isVisible = true
        // A fresh view per opening: a hosting controller kept around would keep its
        // once-a-second timeline running behind a closed popover.
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(monitor: monitor, isSimulation: simulation != nil)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        if let simulation {
            menu.addItem(item(simulation.isPluggedIn ? L("simulate_unplug") : L("simulate_plug"), #selector(toggleSimulatedCharger)))
            menu.addItem(.separator())
        }

        let checkForUpdates = item(L("check_for_updates"), #selector(checkForUpdates))
        checkForUpdates.isEnabled = updater.canCheckForUpdates
        menu.addItem(checkForUpdates)
        menu.addItem(item(L("settings"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(L("quit"), #selector(quit), key: "q"))

        // NSMenu re-enables items from the responder chain unless told otherwise, which
        // would undo the line above.
        menu.autoenablesItems = false

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func toggleSimulatedCharger() {
        simulation?.isPluggedIn.toggle()
        monitor.tick()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSettings() {
        popover.performClose(nil)

        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings_title")
        window.contentView = NSHostingView(rootView: SettingsView(updater: updater))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Drawing

    private func redraw() {
        let presentation = BatteryPresentation(monitor)
        alerts.levelDidChange(presentation.level)

        let alwaysShow = UserDefaults.standard.bool(forKey: PreferenceKey.alwaysShow)
        statusItem.isVisible = alwaysShow
            || Date() < placementUntil
            || presentation.level >= .low
            || popover.isShown
        statusItem.button?.image = renderMenuBarIcon(presentation.menuBar)
        statusItem.button?.toolTip = "\(presentation.status) · \(presentation.percent) %"

        scheduleRedraw(fast: presentation.isOnBattery && (presentation.secondsLeft ?? .infinity) < 3 * 60)
    }

    /// Once a second in the last minutes, when the menu bar shows seconds; every ten
    /// seconds otherwise, which is enough for minutes and to end the placement window.
    private func scheduleRedraw(fast: Bool) {
        let interval: TimeInterval = fast ? 1 : 10
        guard redrawTimer?.timeInterval != interval else { return }
        redrawTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.redraw() }
        }
        timer.tolerance = interval / 10
        RunLoop.main.add(timer, forMode: .common)
        redrawTimer = timer
    }
}
