//
//  LargeFileAnalyzerTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class LargeFileAnalyzerTests: XCTestCase {
    func testFindsOnlyFilesAboveThreshold() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 1_000_000).write(to: root.appendingPathComponent("large.bin"))
        try Data(repeating: 1, count: 1).write(to: root.appendingPathComponent("small.bin"))

        let results = LargeFileAnalyzer(
            roots: [root],
            spotlight: UnavailableSpotlight()
        ).analyze(minimumSize: 500_000)

        XCTAssertEqual(results.map(\.name), ["large.bin"])
        XCTAssertGreaterThanOrEqual(results[0].size, 500_000)
    }

    func testUsesSpotlightResultsWhenAvailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("indexed.bin")
        try Data(repeating: 2, count: 100_000).write(to: file)

        let results = LargeFileAnalyzer(
            roots: [root],
            spotlight: FixedSpotlight(files: [file])
        ).analyze(minimumSize: 50_000)

        XCTAssertEqual(results.map(\.name), ["indexed.bin"])
    }
}

private struct UnavailableSpotlight: SpotlightFileQuerying {
    func files(in root: URL, minimumSize: Int64) -> [URL]? { nil }
}

private struct FixedSpotlight: SpotlightFileQuerying {
    let files: [URL]
    func files(in root: URL, minimumSize: Int64) -> [URL]? { files }
}
