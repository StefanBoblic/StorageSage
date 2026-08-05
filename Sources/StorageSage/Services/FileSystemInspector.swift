//
//  FileSystemInspector.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol FileSystemInspecting: Sendable {
    func children(of directory: URL) throws -> [URL]
    func allocatedSize(of url: URL) -> Int64
    func modificationDate(of url: URL) -> Date?
    func exists(_ url: URL) -> Bool
    func isReadable(_ url: URL) -> Bool
}

struct FileSystemInspector: FileSystemInspecting {
    private let commands: any CommandRunning

    init(commands: any CommandRunning = CommandRunner()) {
        self.commands = commands
    }

    func children(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
    }

    func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .isSymbolicLinkKey
        ]
        guard let root = try? url.resourceValues(forKeys: keys) else { return 0 }
        if root.isSymbolicLink == true { return 0 }
        if root.isRegularFile == true {
            return Int64(root.totalFileAllocatedSize ?? root.fileAllocatedSize ?? 0)
        }
        if root.isDirectory == true, let fastSize = diskUsageSize(of: url) {
            return fastSize
        }

        return enumeratedAllocatedSize(of: url, keys: keys)
    }

    private func diskUsageSize(of url: URL) -> Int64? {
        guard
            let result = commands.run("du", arguments: ["-sk", url.path], timeout: 30),
            result.terminationStatus == 0,
            let output = String(data: result.output, encoding: .utf8),
            let kilobytesText = output.split(whereSeparator: \.isWhitespace).first,
            let kilobytes = Int64(kilobytesText)
        else { return nil }
        return kilobytes * 1_024
    }

    private func enumeratedAllocatedSize(
        of url: URL,
        keys: Set<URLResourceKey>
    ) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isReadable(_ url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }
}
