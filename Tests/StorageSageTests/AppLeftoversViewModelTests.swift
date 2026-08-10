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

    private func makeRecord(path: String, size: Int64) -> AppLeftoverRecord {
        AppLeftoverRecord(
            url: URL(fileURLWithPath: path),
            bundleIdentifier: URL(fileURLWithPath: path).lastPathComponent,
            locationName: "Caches",
            size: size,
            modifiedAt: nil
        )
    }
}

private struct StubAppLeftoverAnalyzer: AppLeftoverAnalyzing {
    let records: [AppLeftoverRecord]

    func analyze() -> [AppLeftoverRecord] { records }
    func noteFileChanges(_ batch: FileChangeBatch) { }
}
