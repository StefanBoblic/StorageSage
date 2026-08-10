//
//  StoragePerformanceTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class StoragePerformanceTests: XCTestCase {
    func testRealScanBenchmarkWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["STORAGESAGE_BENCHMARK"] == "1" else {
            throw XCTSkip("Set STORAGESAGE_BENCHMARK=1 to run the real filesystem benchmark.")
        }

        let startedAt = ContinuousClock.now
        let result = await StorageScanner().scan()
        let elapsed = startedAt.duration(to: .now)

        print("StorageSage real scan: \(elapsed), \(result.candidates.count) candidates")
        XCTAssertFalse(result.candidates.isEmpty)
    }

    func testRealRecommendationBenchmarkWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["STORAGESAGE_BENCHMARK"] == "1" else {
            throw XCTSkip("Set STORAGESAGE_BENCHMARK=1 to run the real filesystem benchmark.")
        }

        var startedAt = ContinuousClock.now
        let installers = InstallerArchiveAnalyzer().analyze()
        let installerElapsed = startedAt.duration(to: .now)

        startedAt = ContinuousClock.now
        let artifacts = ProjectArtifactAnalyzer().analyze()
        let projectElapsed = startedAt.duration(to: .now)

        print("StorageSage installers: \(installerElapsed), \(installers.count) candidates")
        print("StorageSage project artifacts: \(projectElapsed), \(artifacts.count) candidates")
    }
}
