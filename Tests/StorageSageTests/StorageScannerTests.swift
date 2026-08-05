//
//  StorageScannerTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class StorageScannerTests: XCTestCase {
    func testScannerUsesInjectedTargetsWithoutKnowingTheirPaths() async {
        let targetURL = URL(fileURLWithPath: "/virtual/custom-cache")
        let scanner = StorageScanner(
            targetProvider: TargetProvider(url: targetURL),
            analyzers: [],
            fileSystem: FileSystem(size: 42),
            nameProvider: NameProvider(),
            configuration: Configuration(maximumConcurrentTasks: 2)
        )

        let result = await scanner.scan()

        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.path, targetURL.path)
        XCTAssertEqual(result.candidates.first?.size, 42)
        XCTAssertEqual(result.candidates.first?.name, "Injected target")
    }

    func testScannerRunsTargetsInParallelWithinConfiguredLimit() async {
        let tracker = ConcurrencyTracker()
        let targets = (0..<6).map { index in
            ScanTarget(
                url: URL(fileURLWithPath: "/virtual/cache-\(index)"),
                name: "Cache \(index)",
                detail: "Test",
                category: .caches,
                safety: .safe,
                mode: .item
            )
        }
        let scanner = StorageScanner(
            targetProvider: MultipleTargetProvider(targets: targets),
            analyzers: [],
            fileSystem: DelayedFileSystem(tracker: tracker),
            nameProvider: NameProvider(),
            configuration: Configuration(maximumConcurrentTasks: 3)
        )

        let result = await scanner.scan()

        XCTAssertEqual(result.candidates.count, targets.count)
        XCTAssertEqual(tracker.maximumObserved, 3)
    }
}

private struct Configuration: ScanConfigurationProviding {
    let maximumConcurrentTasks: Int
}

private struct TargetProvider: ScanTargetProviding {
    let url: URL

    func targets() -> [ScanTarget] {
        [ScanTarget(
            url: url,
            name: nil,
            detail: "Test target",
            category: .caches,
            safety: .safe,
            mode: .item
        )]
    }

    func protectedURLs() -> [URL] { [] }
}

private struct MultipleTargetProvider: ScanTargetProviding {
    let targetsValue: [ScanTarget]

    init(targets: [ScanTarget]) {
        targetsValue = targets
    }

    func targets() -> [ScanTarget] { targetsValue }
    func protectedURLs() -> [URL] { [] }
}

private struct FileSystem: FileSystemInspecting {
    let size: Int64

    func children(of directory: URL) throws -> [URL] { [] }
    func allocatedSize(of url: URL) -> Int64 { size }
    func modificationDate(of url: URL) -> Date? { nil }
    func exists(_ url: URL) -> Bool { true }
    func isReadable(_ url: URL) -> Bool { true }
}

private struct DelayedFileSystem: FileSystemInspecting {
    let tracker: ConcurrencyTracker

    func children(of directory: URL) throws -> [URL] { [] }
    func allocatedSize(of url: URL) -> Int64 {
        tracker.begin()
        defer { tracker.end() }
        Thread.sleep(forTimeInterval: 0.04)
        return 1
    }
    func modificationDate(of url: URL) -> Date? { nil }
    func exists(_ url: URL) -> Bool { true }
    func isReadable(_ url: URL) -> Bool { true }
}

private final class ConcurrencyTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var maximumObserved = 0

    func begin() {
        lock.lock()
        current += 1
        maximumObserved = max(maximumObserved, current)
        lock.unlock()
    }

    func end() {
        lock.lock()
        current -= 1
        lock.unlock()
    }
}

private struct NameProvider: CandidateNameProviding {
    func displayName(for url: URL) -> String { "Injected target" }
}
