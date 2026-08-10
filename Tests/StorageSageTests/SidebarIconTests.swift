//
//  SidebarIconTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import AppKit
import XCTest
@testable import StorageSage

final class SidebarIconTests: XCTestCase {
    func testEverySidebarPageUsesAnAvailableSystemSymbol() {
        for page in SidebarPage.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: page.icon, accessibilityDescription: nil),
                "Missing SF Symbol for \(page.rawValue): \(page.icon)"
            )
        }
    }
}
