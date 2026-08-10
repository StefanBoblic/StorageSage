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
    private let spotlight: any SpotlightFileQuerying

    init(
        roots: [URL] = LargeFileAnalyzer.defaultRoots(),
        spotlight: any SpotlightFileQuerying = SpotlightFileQuery()
    ) {
        self.roots = roots
        self.spotlight = spotlight
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
            if let spotlightURLs = spotlight.files(in: root, minimumSize: minimumSize) {
                records.append(contentsOf: spotlightURLs.compactMap {
                    record(for: $0, minimumSize: minimumSize, keys: Set(keys))
                })
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if let record = record(for: url, minimumSize: minimumSize, keys: Set(keys)) {
                    records.append(record)
                }
            }
        }
        return Dictionary(grouping: records, by: \.id)
            .compactMap(\.value.first)
            .sorted { $0.size > $1.size }
    }

    private func record(
        for url: URL,
        minimumSize: Int64,
        keys: Set<URLResourceKey>
    ) -> LargeFileRecord? {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              values.isSymbolicLink != true else { return nil }
        if values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus != .current {
            return nil
        }
        let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        guard size >= minimumSize else { return nil }
        return LargeFileRecord(url: url, size: size, modifiedAt: values.contentModificationDate)
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
