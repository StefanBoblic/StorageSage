//
//  DiskGrowthStore.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol DiskGrowthStoring: Sendable {
    func load() async -> [DiskGrowthSnapshot]
    func append(_ snapshot: DiskGrowthSnapshot) async -> [DiskGrowthSnapshot]
    func clear() async
}

actor DiskGrowthStore: DiskGrowthStoring {
    private let fileURL: URL?
    private let maximumSnapshotCount: Int

    init(fileURL: URL? = nil, maximumSnapshotCount: Int = 500) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.maximumSnapshotCount = maximumSnapshotCount
    }

    func load() -> [DiskGrowthSnapshot] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(GrowthHistoryArchive.self, from: data),
              archive.schemaVersion == 1 else { return [] }
        return archive.snapshots.sorted { $0.createdAt < $1.createdAt }
    }

    func append(_ snapshot: DiskGrowthSnapshot) -> [DiskGrowthSnapshot] {
        var snapshots = load().filter { $0.id != snapshot.id }
        snapshots.append(snapshot)
        snapshots = retained(snapshots.sorted { $0.createdAt < $1.createdAt }, now: snapshot.createdAt)
        save(snapshots)
        return snapshots
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func retained(_ snapshots: [DiskGrowthSnapshot], now: Date) -> [DiskGrowthSnapshot] {
        var retained: [DiskGrowthSnapshot] = []
        var hourlyBuckets: Set<Int> = []
        var dailyBuckets: Set<Int> = []

        for snapshot in snapshots.reversed() {
            let age = max(now.timeIntervalSince(snapshot.createdAt), 0)
            if age <= 7 * 24 * 60 * 60 || snapshot.trigger == .baseline {
                retained.append(snapshot)
            } else if age <= 30 * 24 * 60 * 60 {
                let bucket = Int(snapshot.createdAt.timeIntervalSince1970 / 3_600)
                if hourlyBuckets.insert(bucket).inserted { retained.append(snapshot) }
            } else {
                let bucket = Int(snapshot.createdAt.timeIntervalSince1970 / 86_400)
                if dailyBuckets.insert(bucket).inserted { retained.append(snapshot) }
            }
        }
        return Array(retained.prefix(maximumSnapshotCount)).sorted { $0.createdAt < $1.createdAt }
    }

    private func save(_ snapshots: [DiskGrowthSnapshot]) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(GrowthHistoryArchive(schemaVersion: 1, snapshots: snapshots))
                .write(to: fileURL, options: .atomic)
        } catch {
            // Growth history must never block the app.
        }
    }

    private static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StorageSage", isDirectory: true)
            .appendingPathComponent("growth-history.json", isDirectory: false)
    }
}

private struct GrowthHistoryArchive: Codable {
    let schemaVersion: Int
    let snapshots: [DiskGrowthSnapshot]
}
