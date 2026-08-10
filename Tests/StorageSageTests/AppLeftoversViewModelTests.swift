//
//  AppLeftoversViewModelTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

@MainActor
final class AppLeftoversViewModelTests: XCTestCase {
    func testToggleAllSelectsAndDeselectsEveryRecord() async {
        let records = [
            makeRecord(path: "/virtual/com.example.first", size: 10),
            makeRecord(path: "/virtual/com.example.second", size: 20)
        ]
        let viewModel = AppLeftoversViewModel(analyzer: StubAppLeftoverAnalyzer(records: records))

        await viewModel.scan()
        viewModel.toggleAll()

        XCTAssertTrue(viewModel.areAllRecordsSelected)
        XCTAssertEqual(viewModel.selectedIDs, Set(records.map(\.id)))
        XCTAssertEqual(viewModel.selectedSize, 30)

        viewModel.toggleAll()

        XCTAssertFalse(viewModel.areAllRecordsSelected)
        XCTAssertTrue(viewModel.selectedIDs.isEmpty)
    }

    func testToggleAllSkipsUnavailableRecords() async {
        let accessible = makeRecord(path: "/virtual/com.example.accessible", size: 10)
        let unavailable = makeRecord(path: "/virtual/com.example.protected", size: 20, canMoveToTrash: false)
        let viewModel = AppLeftoversViewModel(
            analyzer: StubAppLeftoverAnalyzer(records: [accessible, unavailable])
        )

        await viewModel.scan()
        viewModel.toggleAll()

        XCTAssertEqual(viewModel.selectedIDs, [accessible.id])
        XCTAssertEqual(viewModel.unavailableRecords.map(\.id), [unavailable.id])
    }

    private func makeRecord(path: String, size: Int64, canMoveToTrash: Bool = true) -> AppLeftoverRecord {
        AppLeftoverRecord(
            url: URL(fileURLWithPath: path),
            bundleIdentifier: URL(fileURLWithPath: path).lastPathComponent,
            locationName: "Caches",
            size: size,
            modifiedAt: nil,
            canMoveToTrash: canMoveToTrash
        )
    }
}

private struct StubAppLeftoverAnalyzer: AppLeftoverAnalyzing {
    let records: [AppLeftoverRecord]

    func analyze() -> [AppLeftoverRecord] { records }
    func noteFileChanges(_ batch: FileChangeBatch) { }
}
