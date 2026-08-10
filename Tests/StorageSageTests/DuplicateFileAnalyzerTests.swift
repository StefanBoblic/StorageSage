//
//  DuplicateFileAnalyzerTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class DuplicateFileAnalyzerTests: XCTestCase {
    func testUsesFullContentHashAndFindsOnlyIdenticalFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let duplicateData = Data(repeating: 7, count: 200_000)
        try duplicateData.write(to: root.appendingPathComponent("one.bin"))
        try duplicateData.write(to: root.appendingPathComponent("two.bin"))
        try Data(repeating: 8, count: 200_000).write(to: root.appendingPathComponent("different.bin"))

        let groups = await DuplicateFileAnalyzer(roots: [root], maximumConcurrentHashes: 2)
            .analyze(minimumSize: 100_000)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.name)), ["one.bin", "two.bin"])
        XCTAssertEqual(groups[0].reclaimableSize, 200_000)
    }

    func testVerificationRequiresAnUnselectedIdenticalCopy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data(repeating: 3, count: 20_000)
        try data.write(to: root.appendingPathComponent("one.bin"))
        try data.write(to: root.appendingPathComponent("two.bin"))
        let analyzer = DuplicateFileAnalyzer(roots: [root], maximumConcurrentHashes: 2)
        let groups = await analyzer.analyze(minimumSize: 10_000)
        let allPaths = Set(groups[0].files.map(\.id))

        let unsafeSelection = await analyzer.verifiedCleanupCandidates(
            groups: groups,
            selectedPaths: allPaths
        )
        let safeSelection = await analyzer.verifiedCleanupCandidates(
            groups: groups,
            selectedPaths: [groups[0].files[0].id]
        )

        XCTAssertTrue(unsafeSelection.isEmpty)
        XCTAssertEqual(safeSelection.map(\.id), [groups[0].files[0].id])
    }
}
