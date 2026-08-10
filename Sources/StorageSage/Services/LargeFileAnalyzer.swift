//
//  LargeFileAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol LargeFileAnalyzing: Sendable {
    func analyze(minimumSize: Int64) -> [LargeFileRecord]
}

struct LargeFileAnalyzer: LargeFileAnalyzing {
    private let roots: [URL]

    init(roots: [URL] = LargeFileAnalyzer.defaultRoots()) {
        self.roots = roots
    }

    func analyze(minimumSize: Int64) -> [LargeFileRecord] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        var records: [LargeFileRecord] = []
        let fileManager = FileManager.default

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true else { continue }
                if values.isUbiquitousItem == true,
                   values.ubiquitousItemDownloadingStatus != .current {
                    continue
                }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                guard size >= minimumSize else { continue }
                records.append(LargeFileRecord(
                    url: url,
                    size: size,
                    modifiedAt: values.contentModificationDate
                ))
            }
        }
        return records.sorted { $0.size > $1.size }
    }

    static func defaultRoots(fileManager: FileManager = .default) -> [URL] {
        [
            .desktopDirectory,
            .documentDirectory,
            .downloadsDirectory,
            .moviesDirectory,
            .musicDirectory,
            .picturesDirectory
        ].flatMap { fileManager.urls(for: $0, in: .userDomainMask) }
    }
}
