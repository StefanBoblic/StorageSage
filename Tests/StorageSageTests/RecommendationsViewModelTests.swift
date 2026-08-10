//
//  RecommendationsViewModelTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import XCTest
@testable import StorageSage

final class RecommendationsViewModelTests: XCTestCase {
    func testCompletedEmptyInstallerSectionIsHidden() {
        let section = RecommendationSection(
            id: "installers",
            title: "Installers & Archives",
            candidates: [],
            isScanning: false
        )

        XCTAssertFalse(section.shouldDisplay)
    }

    func testInstallerSectionRemainsVisibleWhileScanning() {
        let section = RecommendationSection(
            id: "installers",
            title: "Installers & Archives",
            candidates: [],
            isScanning: true
        )

        XCTAssertTrue(section.shouldDisplay)
    }
}
