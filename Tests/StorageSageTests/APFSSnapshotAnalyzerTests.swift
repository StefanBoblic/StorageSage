//
//  APFSSnapshotAnalyzerTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class APFSSnapshotAnalyzerTests: XCTestCase {
    func testParsesDiskutilPropertyListWithoutEstimatingSize() throws {
        let payload: [String: Any] = ["Snapshots": [[
            "SnapshotName": "com.apple.TimeMachine.2026-08-10-120000.local",
            "SnapshotUUID": "TEST-UUID",
            "Purgeable": true,
            "LimitingContainerShrink": false
        ]]]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        let snapshots = APFSSnapshotAnalyzer(commands: SnapshotCommands(output: data)).analyze()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].kind, "Time Machine")
        XCTAssertEqual(snapshots[0].isPurgeable, true)
        XCTAssertNotNil(snapshots[0].createdAt)
    }
}

private struct SnapshotCommands: CommandRunning {
    let output: Data
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult? {
        CommandResult(output: output, errorOutput: Data(), terminationStatus: 0)
    }
}
