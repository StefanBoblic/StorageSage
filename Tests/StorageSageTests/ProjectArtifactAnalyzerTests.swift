//
//  ProjectArtifactAnalyzerTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class ProjectArtifactAnalyzerTests: XCTestCase {
    func testFindsArtifactsOnlyWhenProjectMarkerExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("WebApp", isDirectory: true)
        let modules = project.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data(repeating: 1, count: 20_000).write(to: modules.appendingPathComponent("module.bin"))

        let results = ProjectArtifactAnalyzer(
            roots: FixedProjectRoots(roots: [project]),
            minimumSize: 10_000
        ).analyze()

        XCTAssertEqual(results.map(\.name), ["WebApp / node_modules"])
        XCTAssertEqual(results.first?.category, .projectArtifacts)
    }
}

private struct FixedProjectRoots: ProjectRootLocating {
    let roots: [URL]
    func projectRoots() -> [URL] { roots }
}
