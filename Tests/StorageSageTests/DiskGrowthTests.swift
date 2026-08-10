//
//  DiskGrowthTests.swift
//  StorageSageTests
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class DiskGrowthTests: XCTestCase {
    func testComparisonSeparatesTrackedAndUnattributedGrowth() {
        let baseline = snapshot(
            id: UUID(),
            date: Date(timeIntervalSince1970: 100),
            available: 800,
            buckets: [bucket(id: "downloads", bytes: 100)]
        )
        let current = snapshot(
            id: UUID(),
            date: Date(timeIntervalSince1970: 200),
            available: 650,
            buckets: [bucket(id: "downloads", bytes: 190)]
        )

        let comparison = DiskGrowthComparison(baseline: baseline, current: current)

        XCTAssertEqual(comparison?.diskDeltaBytes, 150)
        XCTAssertEqual(comparison?.changes.first(where: { $0.id == "downloads" })?.deltaBytes, 90)
        XCTAssertEqual(comparison?.unattributedDeltaBytes, 60)
    }

    func testComparisonRejectsDifferentVolumes() {
        let first = snapshot(id: UUID(), date: .distantPast, available: 1, volumeID: "one")
        let second = snapshot(id: UUID(), date: .now, available: 1, volumeID: "two")
        XCTAssertNil(DiskGrowthComparison(baseline: first, current: second))
    }

    func testStorePersistsAndClearsSnapshots() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("growth.json")
        let store = DiskGrowthStore(fileURL: fileURL, maximumSnapshotCount: 2)
        _ = await store.append(snapshot(id: UUID(), date: Date(timeIntervalSince1970: 1), available: 10))
        _ = await store.append(snapshot(id: UUID(), date: Date(timeIntervalSince1970: 2), available: 9))
        _ = await store.append(snapshot(id: UUID(), date: Date(timeIntervalSince1970: 3), available: 8))

        let retained = await store.load()
        XCTAssertEqual(retained.count, 2)
        await store.clear()
        let cleared = await store.load()
        XCTAssertTrue(cleared.isEmpty)
    }

    func testAnalyzerRemeasuresOnlyAffectedBuckets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstURL = root.appendingPathComponent("First", isDirectory: true)
        let secondURL = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = GrowthFileSystem(sizes: [firstURL: 10, secondURL: 20])
        let analyzer = DiskGrowthAnalyzer(
            targets: FixedGrowthTargets(values: [
                .init(id: "first", name: "First", url: firstURL),
                .init(id: "second", name: "Second", url: secondURL)
            ]),
            fileSystem: fileSystem,
            exclusions: NoGrowthExclusions(),
            configuration: GrowthScanConfiguration(),
            volumeURL: root
        )
        let baseline = await analyzer.createSnapshot(previous: nil, affectedPaths: nil, trigger: .baseline)
        fileSystem.setSize(30, for: firstURL)
        fileSystem.setSize(99, for: secondURL)

        let incremental = await analyzer.createSnapshot(
            previous: baseline,
            affectedPaths: [firstURL.path],
            trigger: .filesystemChange
        )

        XCTAssertEqual(incremental.buckets.first(where: { $0.id == "first" })?.allocatedBytes, 30)
        XCTAssertEqual(incremental.buckets.first(where: { $0.id == "second" })?.allocatedBytes, 20)
        XCTAssertEqual(fileSystem.measurementCount(for: secondURL), 1)
    }

    private func snapshot(
        id: UUID,
        date: Date,
        available: Int64,
        volumeID: String = "volume",
        buckets: [GrowthBucketSnapshot] = []
    ) -> DiskGrowthSnapshot {
        DiskGrowthSnapshot(
            id: id,
            createdAt: date,
            volumeID: volumeID,
            totalBytes: 1_000,
            availableBytes: available,
            importantUsageAvailableBytes: nil,
            buckets: buckets,
            trigger: .manual
        )
    }

    private func bucket(id: String, bytes: Int64) -> GrowthBucketSnapshot {
        GrowthBucketSnapshot(id: id, name: id, path: "/\(id)", allocatedBytes: bytes, state: .measured)
    }
}

private struct FixedGrowthTargets: DiskGrowthTargetProviding {
    let values: [DiskGrowthTarget]
    func targets() -> [DiskGrowthTarget] { values }
}

private struct NoGrowthExclusions: ScanExclusionProviding {
    func excludedURLs() -> [URL] { [] }
}

private struct GrowthScanConfiguration: ScanConfigurationProviding {
    let maximumConcurrentTasks = 2
}

private final class GrowthFileSystem: FileSystemInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [URL: Int64]
    private var counts: [URL: Int] = [:]

    init(sizes: [URL: Int64]) { self.sizes = sizes }
    func children(of directory: URL) throws -> [URL] { [] }
    func allocatedSize(of url: URL) -> Int64 {
        lock.withLock {
            counts[url, default: 0] += 1
            return sizes[url] ?? 0
        }
    }
    func modificationDate(of url: URL) -> Date? { nil }
    func exists(_ url: URL) -> Bool { true }
    func isReadable(_ url: URL) -> Bool { true }
    func setSize(_ size: Int64, for url: URL) { lock.withLock { sizes[url] = size } }
    func measurementCount(for url: URL) -> Int { lock.withLock { counts[url, default: 0] } }
}
