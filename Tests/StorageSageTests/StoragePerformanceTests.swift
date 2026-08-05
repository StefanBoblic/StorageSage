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
}
