//
//  CleanupPreflightServiceTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class CleanupPreflightServiceTests: XCTestCase {
    func testRemeasuresExistingItemsAndDropsMissingItems() {
        let existingURL = URL(fileURLWithPath: "/virtual/existing")
        let missingURL = URL(fileURLWithPath: "/virtual/missing")
        let service = CleanupPreflightService(
            fileSystem: PreflightFileSystem(existingPath: existingURL.path, size: 4_096),
            simulatorAnalyzer: EmptyAnalyzer()
        )

        let result = service.measure([
            candidate(existingURL, size: 10),
            candidate(missingURL, size: 20)
        ])

        XCTAssertEqual(result.candidates.map(\.size), [4_096])
        XCTAssertEqual(result.unavailableNames, ["missing"])
    }

    func testDropsItemsThatCannotBeMovedToTrash() {
        let accessibleURL = URL(fileURLWithPath: "/virtual/accessible")
        let inaccessibleURL = URL(fileURLWithPath: "/virtual/protected-container")
        let service = CleanupPreflightService(
            fileSystem: PreflightFileSystem(
                existingPath: accessibleURL.path,
                size: 4_096,
                inaccessiblePath: inaccessibleURL.path
            ),
            simulatorAnalyzer: EmptyAnalyzer()
        )

        let result = service.measure([
            candidate(accessibleURL, size: 10),
            candidate(inaccessibleURL, size: 20)
        ])

        XCTAssertEqual(result.candidates.map(\.id), [accessibleURL.path])
        XCTAssertEqual(result.unavailableNames, ["protected-container"])
    }

    private func candidate(_ url: URL, size: Int64) -> CleanupCandidate {
        CleanupCandidate(
            id: url.path,
            name: url.lastPathComponent,
            detail: "Test",
            path: url.path,
            category: .caches,
            safety: .safe,
            strategy: .trash(url),
            size: size,
            modifiedAt: nil
        )
    }
}

private struct PreflightFileSystem: FileSystemInspecting {
    let existingPath: String
    let size: Int64
    var inaccessiblePath: String? = nil

    func children(of directory: URL) throws -> [URL] { [] }
    func allocatedSize(of url: URL) -> Int64 { url.path == existingPath ? size : 1 }
    func modificationDate(of url: URL) -> Date? { .distantPast }
    func exists(_ url: URL) -> Bool { url.path == existingPath || url.path == inaccessiblePath }
    func isReadable(_ url: URL) -> Bool { true }
    func canMoveToTrash(_ url: URL) -> Bool { url.path != inaccessiblePath }
}

private struct EmptyAnalyzer: StorageAnalyzing {
    func analyze() -> [CleanupCandidate] { [] }
}
