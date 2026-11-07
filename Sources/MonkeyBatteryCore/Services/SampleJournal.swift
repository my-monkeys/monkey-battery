import Foundation

/// Recent gauge readings and what has been learnt about this Mac's shutdown point, kept
/// in one small JSON file under Application Support.
///
/// It exists for two readers: the chart, which wants the current discharge, and the
/// calibration, which needs the last heartbeat to still be there after the Mac died.
/// That second reader is why it is written at every tick near the end, and only every
/// few minutes otherwise.
public struct SampleJournal: Sendable {
    public static let retention: TimeInterval = 3 * 3600
    static let relaxedSaveInterval: TimeInterval = 5 * 60

    public private(set) var samples: [BatterySample] = []
    public var calibration = ShutdownCalibration()
    public var heartbeat: Heartbeat?
    /// The discharge under way, until it ends and moves to the `DischargeArchive`.
    public var currentRecord: DischargeRecord?

    private let url: URL?
    private var lastSavedAt: Date?

    /// `url` nil keeps everything in memory — the simulation must not teach the real
    /// calibration a shutdown that never happened.
    public init(url: URL?) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        samples = file.samples
        calibration = file.calibration
        heartbeat = file.heartbeat
        currentRecord = file.currentRecord
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("fr.mymonkey.monkeybattery", isDirectory: true)
            .appendingPathComponent("journal.json")
    }

    public mutating func append(_ sample: BatterySample) {
        guard sample.updatedAt != samples.last?.updatedAt else { return }
        samples.append(sample)
        let horizon = sample.updatedAt.addingTimeInterval(-Self.retention)
        if let firstKept = samples.firstIndex(where: { $0.updatedAt >= horizon }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
    }

    /// The readings of the discharge under way, oldest first; empty when not draining.
    public var currentDischarge: [BatterySample] {
        guard samples.last?.isDraining == true else { return [] }
        let start = samples.lastIndex(where: { !$0.isDraining }).map { $0 + 1 } ?? 0
        return Array(samples[start...])
    }

    public mutating func save(now: Date, urgent: Bool) {
        guard let url else { return }
        if !urgent, let lastSavedAt, now.timeIntervalSince(lastSavedAt) < Self.relaxedSaveInterval { return }

        let file = File(samples: samples, calibration: calibration, heartbeat: heartbeat, currentRecord: currentRecord)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
        lastSavedAt = now
    }

    private struct File: Codable {
        var samples: [BatterySample]
        var calibration: ShutdownCalibration
        var heartbeat: Heartbeat?
        var currentRecord: DischargeRecord?
    }
}
