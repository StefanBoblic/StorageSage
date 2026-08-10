//
//  AppLeftoverAnalyzerTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class AppLeftoverAnalyzerTests: XCTestCase {
    func testReturnsOnlyUnownedBundleIdentifierEntries() throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: library) }
        try writeData(to: caches.appendingPathComponent("com.example.removed", isDirectory: true))
        try writeData(to: caches.appendingPathComponent("com.example.installed", isDirectory: true))
        try writeData(to: caches.appendingPathComponent("com.apple.system", isDirectory: true))
        try writeData(to: caches.appendingPathComponent("Friendly App", isDirectory: true))

        let results = AppLeftoverAnalyzer(
            libraryURL: library,
            installedBundleIdentifiers: ["com.example.installed"]
        ).analyze()

        XCTAssertEqual(results.map(\.bundleIdentifier), ["com.example.removed"])
    }

    private func writeData(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32).write(to: directory.appendingPathComponent("data"))
    }
}
