//
//  DiskGrowthAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol DiskGrowthAnalyzing: Sendable {
    func createSnapshot(
        previous: DiskGrowthSnapshot?,
        affectedPaths: [String]?,
        trigger: GrowthSnapshotTrigger
    ) async -> DiskGrowthSnapshot
}

struct DiskGrowthAnalyzer: DiskGrowthAnalyzing {
    private let targets: any DiskGrowthTargetProviding
    private let fileSystem: any FileSystemInspecting
    private let exclusions: any ScanExclusionProviding
    private let configuration: any ScanConfigurationProviding
    private let volumeURL: URL

    init(
        targets: any DiskGrowthTargetProviding = DefaultDiskGrowthTargetProvider(),
        fileSystem: any FileSystemInspecting = FileSystemInspector(),
        exclusions: any ScanExclusionProviding = UserDefaultsScanExclusionStore(),
        configuration: any ScanConfigurationProviding = UserDefaultsScanConfiguration(),
        volumeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.targets = targets
        self.fileSystem = fileSystem
        self.exclusions = exclusions
        self.configuration = configuration
        self.volumeURL = volumeURL
    }

    func createSnapshot(
        previous: DiskGrowthSnapshot?,
        affectedPaths: [String]?,
        trigger: GrowthSnapshotTrigger
    ) async -> DiskGrowthSnapshot {
        let volume = volumeMetadata()
        let canReusePrevious = previous?.volumeID == volume.id
        let previousBuckets = canReusePrevious ? (previous?.buckets ?? []) : []
        let previousByID = Dictionary(uniqueKeysWithValues: previousBuckets.map { ($0.id, $0) })
        let matcher = exclusions.matcher()
        let allTargets = targets.targets()
        let changeBatch = affectedPaths.map { FileChangeBatch(paths: $0, requiresFullRescan: false) }
        var reused: [GrowthBucketSnapshot] = []
        var jobs: [DiskGrowthTarget] = []

        for target in allTargets {
            if matcher.excludes(target.url) {
                reused.append(bucket(for: target, bytes: 0, state: .excluded))
            } else if let changeBatch,
                      !changeBatch.affects([target.url]),
                      let previousBucket = previousByID[target.id] {
                reused.append(previousBucket)
            } else {
                jobs.append(target)
            }
        }

        let limit = min(max(configuration.maximumConcurrentTasks, 1), 4)
        let measured = await withTaskGroup(of: GrowthBucketSnapshot.self, returning: [GrowthBucketSnapshot].self) { group in
            var iterator = jobs.makeIterator()
            var results: [GrowthBucketSnapshot] = []
            for _ in 0..<min(limit, jobs.count) {
                if let target = iterator.next() { group.addTask { measure(target) } }
            }
            while let result = await group.next() {
                results.append(result)
                if let target = iterator.next() { group.addTask { measure(target) } }
            }
            return results
        }

        return DiskGrowthSnapshot(
            id: UUID(),
            createdAt: Date(),
            volumeID: volume.id,
            totalBytes: volume.total,
            availableBytes: volume.available,
            importantUsageAvailableBytes: volume.importantAvailable,
            buckets: (reused + measured).sorted { $0.name < $1.name },
            trigger: trigger
        )
    }

    private func measure(_ target: DiskGrowthTarget) -> GrowthBucketSnapshot {
        guard fileSystem.exists(target.url) else {
            return bucket(for: target, bytes: 0, state: .missing)
        }
        guard fileSystem.isReadable(target.url) else {
            return bucket(for: target, bytes: 0, state: .unavailable)
        }
        return bucket(
            for: target,
            bytes: fileSystem.allocatedSize(of: target.url),
            state: .measured
        )
    }

    private func bucket(
        for target: DiskGrowthTarget,
        bytes: Int64,
        state: GrowthMeasurementState
    ) -> GrowthBucketSnapshot {
        GrowthBucketSnapshot(
            id: target.id,
            name: target.name,
            path: target.url.standardizedFileURL.path,
            allocatedBytes: bytes,
            state: state
        )
    }

    private func volumeMetadata() -> (id: String, total: Int64, available: Int64, importantAvailable: Int64?) {
        let values = try? volumeURL.resourceValues(forKeys: [
            .volumeUUIDStringKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        return (
            values?.volumeUUIDString ?? volumeURL.standardizedFileURL.path,
            Int64(values?.volumeTotalCapacity ?? 0),
            Int64(values?.volumeAvailableCapacity ?? 0),
            values?.volumeAvailableCapacityForImportantUsage
        )
    }
}
