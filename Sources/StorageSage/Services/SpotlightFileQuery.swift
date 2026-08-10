//
//  SpotlightFileQuery.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol SpotlightFileQuerying: Sendable {
    func files(in root: URL, minimumSize: Int64) -> [URL]?
}

struct SpotlightFileQuery: SpotlightFileQuerying {
    private let commands: any CommandRunning

    init(commands: any CommandRunning = CommandRunner()) {
        self.commands = commands
    }

    func files(in root: URL, minimumSize: Int64) -> [URL]? {
        guard let result = commands.run(
            "mdfind",
            arguments: [
                "-0",
                "-onlyin", root.path,
                "kMDItemFSSize >= \(minimumSize) && kMDItemContentTypeTree == 'public.data'"
            ],
            timeout: 15
        ), result.terminationStatus == 0 else { return nil }

        return result.output.split(separator: 0).compactMap { bytes in
            guard let path = String(data: Data(bytes), encoding: .utf8), !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: false)
        }
    }
}
