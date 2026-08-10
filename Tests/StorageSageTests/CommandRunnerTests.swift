//
//  CommandRunnerTests.swift
//  StorageSageTests
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class CommandRunnerTests: XCTestCase {
    func testDrainsLargeOutputWithoutBlockingTheChildProcess() {
        let runner = CommandRunner(executables: FixedExecutableLocator(url: URL(fileURLWithPath: "/bin/sh")))

        let result = runner.run(
            "sh",
            arguments: ["-c", "head -c 262144 /dev/zero"],
            timeout: 5
        )

        XCTAssertEqual(result?.terminationStatus, 0)
        XCTAssertEqual(result?.output.count, 262_144)
    }
}

private struct FixedExecutableLocator: ExecutableLocating {
    let url: URL
    func locate(_ executable: String) -> URL? { url }
}
