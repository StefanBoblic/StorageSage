//
//  CleanupHistoryStore.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol CleanupHistoryStoring: Sendable {
    func load() -> [CleanupHistoryRecord]
    func append(_ record: CleanupHistoryRecord)
    func clear()
}

final class DiskCleanupHistoryStore: CleanupHistoryStoring, @unchecked Sendable {
    private let fileURL: URL?
    private let lock = NSLock()
    private let maximumRecordCount: Int

    init(fileURL: URL? = nil, maximumRecordCount: Int = 100) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.maximumRecordCount = maximumRecordCount
    }

    func load() -> [CleanupHistoryRecord] {
        lock.withLock { loadUnlocked() }
    }

    func append(_ record: CleanupHistoryRecord) {
        lock.withLock {
            guard let fileURL else { return }
            var records = loadUnlocked()
            records.insert(record, at: 0)
            records = Array(records.prefix(maximumRecordCount))
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(records).write(to: fileURL, options: .atomic)
            } catch {
                // History must never block a cleanup operation.
            }
        }
    }

    func clear() {
        lock.withLock {
            guard let fileURL else { return }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func loadUnlocked() -> [CleanupHistoryRecord] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CleanupHistoryRecord].self, from: data)) ?? []
    }

    private static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StorageSage", isDirectory: true)
            .appendingPathComponent("cleanup-history.json", isDirectory: false)
    }
}
