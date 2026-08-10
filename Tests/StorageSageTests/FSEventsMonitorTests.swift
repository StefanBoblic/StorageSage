//
//  FSEventsMonitorTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class FSEventsMonitorTests: XCTestCase {
    func testChangeBatchMatchesDescendantsAndAncestorEvents() {
        let root = URL(fileURLWithPath: "/Users/example/Documents", isDirectory: true)

        XCTAssertTrue(FileChangeBatch(
            paths: ["/Users/example/Documents/project/file.swift"],
            requiresFullRescan: false
        ).affects([root]))
        XCTAssertTrue(FileChangeBatch(
            paths: ["/Users/example"],
            requiresFullRescan: false
        ).affects([root]))
        XCTAssertFalse(FileChangeBatch(
            paths: ["/Users/example/Downloads/file.zip"],
            requiresFullRescan: false
        ).affects([root]))
    }
}
