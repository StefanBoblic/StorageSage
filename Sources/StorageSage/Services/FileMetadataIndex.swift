//
//  FileMetadataIndex.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

struct IndexedFileRecord: Hashable, Sendable {
    let url: URL
    let logicalSize: Int64
    let allocatedSize: Int64
    let modifiedAt: Date?
    let resourceIdentifier: String
}

protocol FileMetadataIndexing: Sendable {
    func files(minimumSize: Int64) async -> [IndexedFileRecord]
    func invalidate(_ batch: FileChangeBatch) async
}

actor PersonalFileMetadataIndex: FileMetadataIndexing {
    static let shared = PersonalFileMetadataIndex()

    private let roots: [URL]
    private let spotlight: any SpotlightFileQuerying
    private let exclusions: any ScanExclusionProviding
    private var cachedMinimumSize: Int64?
    private var cachedFiles: [IndexedFileRecord] = []

    init(
        roots: [URL] = LargeFileAnalyzer.defaultRoots(),
        spotlight: any SpotlightFileQuerying = SpotlightFileQuery(),
        exclusions: any ScanExclusionProviding = UserDefaultsScanExclusionStore()
    ) {
        self.roots = roots.map(\.standardizedFileURL)
        self.spotlight = spotlight
        self.exclusions = exclusions
    }

    func files(minimumSize: Int64) async -> [IndexedFileRecord] {
        if let cachedMinimumSize, cachedMinimumSize <= minimumSize {
            return cachedFiles.filter { $0.logicalSize >= minimumSize || $0.allocatedSize >= minimumSize }
        }

        let matcher = exclusions.matcher()
        let records: [IndexedFileRecord]
        if let queryRoot = commonAncestor(of: roots),
           let spotlightURLs = spotlight.files(in: queryRoot, minimumSize: minimumSize) {
            records = spotlightURLs.compactMap {
                guard isInsideTrackedRoots($0), !matcher.excludes($0) else { return nil }
                return metadata(for: $0, minimumSize: minimumSize)
            }
        } else {
            records = await enumerateFiles(minimumSize: minimumSize, matcher: matcher)
        }

        cachedMinimumSize = minimumSize
        cachedFiles = Dictionary(grouping: records, by: { $0.url.standardizedFileURL.path })
            .compactMap(\.value.first)
        return cachedFiles
    }

    func invalidate(_ batch: FileChangeBatch) {
        guard batch.requiresFullRescan || batch.affects(roots) else { return }
        cachedMinimumSize = nil
        cachedFiles = []
    }

    private func enumerateFiles(
        minimumSize: Int64,
        matcher: PathExclusionMatcher
    ) async -> [IndexedFileRecord] {
        await withTaskGroup(of: [IndexedFileRecord].self, returning: [IndexedFileRecord].self) { group in
            for root in roots where FileManager.default.fileExists(atPath: root.path) && !matcher.excludes(root) {
                group.addTask {
                    Self.enumerate(root: root, minimumSize: minimumSize, matcher: matcher)
                }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }
    }

    private static func enumerate(
        root: URL,
        minimumSize: Int64,
        matcher: PathExclusionMatcher
    ) -> [IndexedFileRecord] {
        let keys = metadataKeys
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var records: [IndexedFileRecord] = []
        for case let url as URL in enumerator {
            if matcher.excludes(url) {
                enumerator.skipDescendants()
                continue
            }
            if let record = metadata(for: url, minimumSize: minimumSize, keys: keys) {
                records.append(record)
            }
        }
        return records
    }

    private func metadata(for url: URL, minimumSize: Int64) -> IndexedFileRecord? {
        Self.metadata(for: url, minimumSize: minimumSize, keys: Self.metadataKeys)
    }

    private static func metadata(
        for url: URL,
        minimumSize: Int64,
        keys: Set<URLResourceKey>
    ) -> IndexedFileRecord? {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              values.isSymbolicLink != true else { return nil }
        if values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus != .current {
            return nil
        }
        let logicalSize = Int64(values.fileSize ?? 0)
        let allocatedSize = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        guard logicalSize >= minimumSize || allocatedSize >= minimumSize else { return nil }
        return IndexedFileRecord(
            url: url.standardizedFileURL,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            modifiedAt: values.contentModificationDate,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) } ?? url.standardizedFileURL.path
        )
    }

    private func isInsideTrackedRoots(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { path == $0.path || path.hasPrefix($0.path + "/") }
    }

    private func commonAncestor(of urls: [URL]) -> URL? {
        guard var components = urls.first?.standardizedFileURL.pathComponents else { return nil }
        for url in urls.dropFirst() {
            let other = url.standardizedFileURL.pathComponents
            components = Array(zip(components, other).prefix { $0.0 == $0.1 }.map(\.0))
            if components.isEmpty { return nil }
        }
        return components.reduce(URL(fileURLWithPath: "/", isDirectory: true)) {
            $1 == "/" ? $0 : $0.appendingPathComponent($1, isDirectory: true)
        }
    }

    private static let metadataKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
        .fileResourceIdentifierKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey
    ]
}
