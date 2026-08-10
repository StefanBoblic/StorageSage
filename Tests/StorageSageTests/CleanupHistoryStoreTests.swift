//
//  CleanupHistoryStoreTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class CleanupHistoryStoreTests: XCTestCase {
    func testPersistsNewestRecordsAndCanClearThem() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DiskCleanupHistoryStore(fileURL: fileURL, maximumRecordCount: 2)

        for index in 1...3 {
            store.append(CleanupHistoryRecord(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                source: "Run \(index)",
                items: [],
                movedToTrashBytes: Int64(index),
                deletedImmediatelyBytes: 0,
                actualFreedBytes: nil,
                isDryRun: false,
                errorCount: 0,
                skippedCount: 0
            ))
        }

        XCTAssertEqual(store.load().map(\.source), ["Run 3", "Run 2"])
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }
}
