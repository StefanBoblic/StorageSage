//
//  StorageViewModelTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

@MainActor
final class StorageViewModelTests: XCTestCase {
    func testSuccessfulCleanupRefreshesOverviewData() async {
        let candidate = makeCandidate()
        let refreshedAt = Date()
        let scanner = SequencedScanner(results: [
            ScanResult(candidates: [candidate], volume: VolumeSnapshot(total: 100, available: 20), inaccessiblePaths: [], scannedAt: .distantPast),
            ScanResult(candidates: [], volume: VolumeSnapshot(total: 100, available: 40), inaccessiblePaths: [], scannedAt: refreshedAt)
        ])
        let viewModel = StorageViewModel(scanner: scanner, cleaner: SuccessfulCleaner())

        await viewModel.scan()
        viewModel.toggle(candidate)
        await viewModel.cleanSelected()

        XCTAssertEqual(scanner.callCount, 2)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertEqual(viewModel.volume.available, 40)
        XCTAssertEqual(viewModel.scannedAt, refreshedAt)
    }

    func testCleanupWithoutRemovalDoesNotRescanOverview() async {
        let candidate = makeCandidate()
        let scanner = SequencedScanner(results: [
            ScanResult(candidates: [candidate], volume: VolumeSnapshot(total: 100, available: 20), inaccessiblePaths: [], scannedAt: .distantPast)
        ])
        let viewModel = StorageViewModel(scanner: scanner, cleaner: PreviewCleaner())

        await viewModel.scan()
        viewModel.toggle(candidate)
        await viewModel.cleanSelected()

        XCTAssertEqual(scanner.callCount, 1)
    }

    private func makeCandidate() -> CleanupCandidate {
        let url = URL(fileURLWithPath: "/virtual/cache")
        return CleanupCandidate(
            id: url.path,
            name: "Test Cache",
            detail: "Test",
            path: url.path,
            category: .caches,
            safety: .safe,
            strategy: .trash(url),
            size: 20,
            modifiedAt: nil
        )
    }
}

private final class SequencedScanner: StorageScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [ScanResult]
    private(set) var callCount = 0

    init(results: [ScanResult]) {
        self.results = results
    }

    func scan() async -> ScanResult {
        lock.withLock {
            let index = min(callCount, results.count - 1)
            callCount += 1
            return results[index]
        }
    }
}

private struct SuccessfulCleaner: StorageCleaning {
    func clean(
        _ candidates: [CleanupCandidate],
        progress: @escaping @Sendable (CleanupProgress) -> Void
    ) -> CleanupReport {
        CleanupReport(
            reclaimed: candidates.reduce(0) { $0 + $1.size },
            removedCount: candidates.count
        )
    }
}

private struct PreviewCleaner: StorageCleaning {
    func clean(
        _ candidates: [CleanupCandidate],
        progress: @escaping @Sendable (CleanupProgress) -> Void
    ) -> CleanupReport {
        CleanupReport(
            previewedCount: candidates.count,
            estimatedReclaimable: candidates.reduce(0) { $0 + $1.size },
            isDryRun: true
        )
    }
}
