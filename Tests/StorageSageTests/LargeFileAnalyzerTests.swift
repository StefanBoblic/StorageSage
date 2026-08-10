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

        let results = LargeFileAnalyzer(roots: [root]).analyze(minimumSize: 500_000)

        XCTAssertEqual(results.map(\.name), ["large.bin"])
        XCTAssertGreaterThanOrEqual(results[0].size, 500_000)
    }
}
