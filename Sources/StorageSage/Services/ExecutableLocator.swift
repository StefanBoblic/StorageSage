//
//  ExecutableLocator.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol ExecutableLocating: Sendable {
    func locate(_ executable: String) -> URL?
}

struct PathExecutableLocator: ExecutableLocating {
    private let searchDirectories: [URL]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        searchDirectories = environment["PATH", default: ""]
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
    }

    func locate(_ executable: String) -> URL? {
        searchDirectories
            .map { $0.appendingPathComponent(executable, isDirectory: false) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
