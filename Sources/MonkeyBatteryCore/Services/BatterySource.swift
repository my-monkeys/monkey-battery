import Foundation
import IOKit
import IOKit.ps

/// Where readings come from, and what time it is there. The simulation runs its own
/// clock, so the monitor never calls `Date()` directly.
@MainActor
public protocol BatterySource: AnyObject {
    var now: Date { get }
    func read() -> BatterySample?
}

/// Reads the `AppleSmartBattery` registry entry — the same figures `ioreg` prints. No
/// entitlement, no helper, no privilege: any process may read it.
@MainActor
public final class LiveBatterySource: BatterySource {
    public init() {}

    public var now: Date { Date() }

    public func read() -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return BatterySample(registry: dictionary, readAt: now)
    }
}

/// Calls back the moment the Mac switches between charger and battery. The gauge only
/// catches up within a minute; without this, plugging in would leave the alert panel up
/// for that long.
///
/// ⚠️ Lives as long as the app: the run loop source holds an unretained pointer to it,
/// and there is no deinit to remove the source.
@MainActor
public final class PowerSourceObserver {
    private let onChange: @MainActor () -> Void

    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let observer = Unmanaged<PowerSourceObserver>.fromOpaque(context).takeUnretainedValue()
            // Delivered on the main run loop, where the source was added.
            MainActor.assumeIsolated { observer.onChange() }
        }, context)?.takeRetainedValue() else { return }

        // Common modes, so a change still lands while a menu is being tracked.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
}
