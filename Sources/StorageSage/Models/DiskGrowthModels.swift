//
//  DiskGrowthModels.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

enum GrowthSnapshotTrigger: String, Codable, Sendable {
    case baseline
    case manual
    case filesystemChange
    case overviewScan
    case cleanup
    case applicationLaunch
}

enum GrowthMeasurementState: String, Codable, Sendable {
    case measured
    case unavailable
    case missing
    case excluded
}

struct GrowthBucketSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let allocatedBytes: Int64
    let state: GrowthMeasurementState
}

struct DiskGrowthSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let volumeID: String
    let totalBytes: Int64
    let availableBytes: Int64
    let importantUsageAvailableBytes: Int64?
    let buckets: [GrowthBucketSnapshot]
    let trigger: GrowthSnapshotTrigger

    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }
}

struct GrowthBucketChange: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String?
    let previousBytes: Int64
    let currentBytes: Int64
    let state: GrowthMeasurementState
    let isUnattributed: Bool

    var deltaBytes: Int64 { currentBytes - previousBytes }
}

struct DiskGrowthComparison: Sendable {
    let baseline: DiskGrowthSnapshot
    let current: DiskGrowthSnapshot
    let changes: [GrowthBucketChange]
    let diskDeltaBytes: Int64
    let unattributedDeltaBytes: Int64

    init?(baseline: DiskGrowthSnapshot, current: DiskGrowthSnapshot) {
        guard baseline.volumeID == current.volumeID, baseline.id != current.id else { return nil }
        self.baseline = baseline
        self.current = current
        diskDeltaBytes = baseline.availableBytes - current.availableBytes

        let previous = Dictionary(uniqueKeysWithValues: baseline.buckets.map { ($0.id, $0) })
        let measuredChanges = current.buckets.map { bucket in
            GrowthBucketChange(
                id: bucket.id,
                name: bucket.name,
                path: bucket.path,
                previousBytes: previous[bucket.id]?.allocatedBytes ?? 0,
                currentBytes: bucket.allocatedBytes,
                state: bucket.state,
                isUnattributed: false
            )
        }
        let attributedDelta = measuredChanges
            .filter { $0.state == .measured || $0.state == .missing }
            .reduce(Int64(0)) { $0 + $1.deltaBytes }
        unattributedDeltaBytes = diskDeltaBytes - attributedDelta
        changes = (measuredChanges + [
            GrowthBucketChange(
                id: "system-and-apfs",
                name: "System & APFS / Unattributed",
                path: nil,
                previousBytes: 0,
                currentBytes: diskDeltaBytes - attributedDelta,
                state: .measured,
                isUnattributed: true
            )
        ]).sorted { abs($0.deltaBytes) > abs($1.deltaBytes) }
    }
}

enum GrowthHistoryRange: String, CaseIterable, Identifiable {
    case lastSnapshot = "Since Last Snapshot"
    case baseline = "Since Baseline"
    case day = "24 Hours"
    case week = "7 Days"
    case month = "30 Days"
    case all = "All Time"

    var id: String { rawValue }

    var interval: TimeInterval? {
        switch self {
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        case .lastSnapshot, .baseline, .all: return nil
        }
    }
}
