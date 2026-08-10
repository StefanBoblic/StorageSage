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
    func allocatedSizes(of urls: [URL]) -> [URL: Int64]
    func modificationDate(of url: URL) -> Date?
    func exists(_ url: URL) -> Bool
    func isReadable(_ url: URL) -> Bool
    func canMoveToTrash(_ url: URL) -> Bool
}

extension FileSystemInspecting {
    func allocatedSizes(of urls: [URL]) -> [URL: Int64] {
        Dictionary(uniqueKeysWithValues: urls.map { ($0, allocatedSize(of: $0)) })
    }

    func canMoveToTrash(_ url: URL) -> Bool { true }
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
        allocatedSizes(of: [url])[url] ?? 0
    }

    func allocatedSizes(of urls: [URL]) -> [URL: Int64] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .isSymbolicLinkKey
        ]
        var sizes: [URL: Int64] = [:]
        var directories: [URL] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else {
                sizes[url] = 0
                continue
            }
            if values.isSymbolicLink == true {
                sizes[url] = 0
            } else if values.isRegularFile == true {
                sizes[url] = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            } else if values.isDirectory == true {
                directories.append(url)
            } else {
                sizes[url] = 0
            }
        }

        let fastSizes = diskUsageSizes(of: directories)
        for directory in directories {
            sizes[directory] = fastSizes[directory]
                ?? enumeratedAllocatedSize(of: directory, keys: keys)
        }
        return sizes
    }

    private func diskUsageSizes(of urls: [URL]) -> [URL: Int64] {
        guard !urls.isEmpty else { return [:] }
        guard
            let result = commands.run("du", arguments: ["-sk"] + urls.map(\.path), timeout: 60),
            let output = String(data: result.output, encoding: .utf8)
        else { return [:] }

        let urlsByPath = Dictionary(uniqueKeysWithValues: urls.map { ($0.path, $0) })
        var sizes: [URL: Int64] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(where: \.isWhitespace),
                  let kilobytes = Int64(line[..<separator]) else { continue }
            let path = String(line[separator...]).trimmingCharacters(in: .whitespaces)
            if let url = urlsByPath[path] {
                sizes[url] = kilobytes * 1_024
            }
        }
        return sizes
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

    func canMoveToTrash(_ url: URL) -> Bool {
        let parent = url.standardizedFileURL.deletingLastPathComponent()
        return exists(url) && FileManager.default.isWritableFile(atPath: parent.path)
    }
}
