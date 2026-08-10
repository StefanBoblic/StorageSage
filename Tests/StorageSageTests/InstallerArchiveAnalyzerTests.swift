//
//  InstallerArchiveAnalyzerTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class InstallerArchiveAnalyzerTests: XCTestCase {
    func testFindsOnlyOldSupportedArchivesAboveThreshold() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let oldArchive = root.appendingPathComponent("old.dmg")
        let recentArchive = root.appendingPathComponent("new.zip")
        let unrelated = root.appendingPathComponent("notes.txt")
        for url in [oldArchive, recentArchive, unrelated] {
            try Data(repeating: 1, count: 20_000).write(to: url)
        }
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldArchive.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelated.path)

        let results = InstallerArchiveAnalyzer(
            roots: [root],
            minimumSize: 10_000,
            minimumAge: 100,
            now: { Date(timeIntervalSince1970: 2_000) },
            spotlight: nil
        ).analyze()

        XCTAssertEqual(results.map(\.name), ["old.dmg"])
        guard case .trashReviewedFile(let resultURL) = results.first?.strategy else {
            return XCTFail("Expected a reviewed file cleanup strategy")
        }
        XCTAssertEqual(resultURL.standardizedFileURL.path, oldArchive.standardizedFileURL.path)
    }

    func testUsesSpotlightCandidatesWithoutWalkingUnrelatedTrees() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("indexed.pkg")
        try Data(repeating: 1, count: 20_000).write(to: archive)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: archive.path
        )

        let results = InstallerArchiveAnalyzer(
            roots: [root],
            minimumSize: 10_000,
            minimumAge: 100,
            now: { Date(timeIntervalSince1970: 2_000) },
            spotlight: FixedInstallerLocator(urls: [archive])
        ).analyze()

        XCTAssertEqual(results.map(\.name), ["indexed.pkg"])
    }
}

private struct FixedInstallerLocator: InstallerArchiveLocating {
    let urls: [URL]
    func files(in roots: [URL], minimumSize: Int64) -> [URL]? { urls }
}
