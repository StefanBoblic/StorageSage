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
    func testScannerUsesInjectedTargetsWithoutKnowingTheirPaths() {
        let targetURL = URL(fileURLWithPath: "/virtual/custom-cache")
        let scanner = StorageScanner(
            targetProvider: TargetProvider(url: targetURL),
            analyzers: [],
            fileSystem: FileSystem(size: 42),
            nameProvider: NameProvider()
        )

        let result = scanner.scan()

        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.path, targetURL.path)
        XCTAssertEqual(result.candidates.first?.size, 42)
        XCTAssertEqual(result.candidates.first?.name, "Injected target")
    }
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

private struct FileSystem: FileSystemInspecting {
    let size: Int64

    func children(of directory: URL) throws -> [URL] { [] }
    func allocatedSize(of url: URL) -> Int64 { size }
    func modificationDate(of url: URL) -> Date? { nil }
    func exists(_ url: URL) -> Bool { true }
    func isReadable(_ url: URL) -> Bool { true }
}

private struct NameProvider: CandidateNameProviding {
    func displayName(for url: URL) -> String { "Injected target" }
}
