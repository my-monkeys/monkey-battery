import Foundation

/// Past discharges, for the app to grade its forecasts against.
///
/// A file of its own, written once per finished discharge: the journal is rewritten every
/// few seconds near the end of the battery, and would drag thirty discharges along each
/// time. The discharge under way lives in the journal until it ends, so it survives a
/// shutdown.
public struct DischargeArchive: Sendable {
    static let keptRecords = 30

    public private(set) var records: [DischargeRecord] = []
    private let url: URL?

    /// `url` nil keeps everything in memory — a simulated discharge must not be learnt.
    public init(url: URL?) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        records = file.records
    }

    public static var defaultURL: URL {
        SampleJournal.defaultURL.deletingLastPathComponent().appendingPathComponent("discharges.json")
    }

    /// False when the record was too short to keep.
    @discardableResult
    public mutating func add(_ record: DischargeRecord) -> Bool {
        guard record.isWorthKeeping else { return false }
        records.append(record)
        if records.count > Self.keptRecords {
            records.removeFirst(records.count - Self.keptRecords)
        }
        save()
        return true
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(File(records: records)) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private struct File: Codable {
        var records: [DischargeRecord]
    }
}
