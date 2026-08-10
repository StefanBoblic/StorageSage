//
//  LargeFileAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol LargeFileAnalyzing: Sendable {
    func analyze(minimumSize: Int64) async -> [LargeFileRecord]
    func invalidate(_ batch: FileChangeBatch) async
}

struct LargeFileAnalyzer: LargeFileAnalyzing {
    private let index: any FileMetadataIndexing

    init(index: any FileMetadataIndexing = PersonalFileMetadataIndex.shared) {
        self.index = index
    }

    init(
        roots: [URL],
        spotlight: any SpotlightFileQuerying = SpotlightFileQuery(),
        exclusions: any ScanExclusionProviding = UserDefaultsScanExclusionStore()
    ) {
        index = PersonalFileMetadataIndex(roots: roots, spotlight: spotlight, exclusions: exclusions)
    }

    func analyze(minimumSize: Int64) async -> [LargeFileRecord] {
        await index.files(minimumSize: minimumSize)
            .filter { $0.allocatedSize >= minimumSize }
            .map { LargeFileRecord(url: $0.url, size: $0.allocatedSize, modifiedAt: $0.modifiedAt) }
            .sorted { $0.size > $1.size }
    }

    func invalidate(_ batch: FileChangeBatch) async {
        await index.invalidate(batch)
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
