//
//  DuplicateFileAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import CryptoKit
import Foundation

protocol DuplicateFileAnalyzing: Sendable {
    func analyze(minimumSize: Int64) async -> [DuplicateGroup]
    func verifiedCleanupCandidates(
        groups: [DuplicateGroup],
        selectedPaths: Set<String>
    ) async -> [CleanupCandidate]
}

struct DuplicateFileAnalyzer: DuplicateFileAnalyzing {
    private let roots: [URL]
    private let maximumConcurrentHashes: Int
    private let fileSystem: any FileSystemInspecting

    init(
        roots: [URL] = LargeFileAnalyzer.defaultRoots(),
        maximumConcurrentHashes: Int = 4,
        fileSystem: any FileSystemInspecting = FileSystemInspector()
    ) {
        self.roots = roots
        self.maximumConcurrentHashes = max(maximumConcurrentHashes, 1)
        self.fileSystem = fileSystem
    }

    func analyze(minimumSize: Int64) async -> [DuplicateGroup] {
        let probes = discoverFiles(minimumSize: minimumSize)
        let sameSize = Dictionary(grouping: probes, by: \.size).values.filter { $0.count > 1 }
        let partialCandidates = sameSize.flatMap { $0 }
        let partialHashes = await hashes(for: partialCandidates, mode: .partial)
        let partialGroups = Dictionary(grouping: partialCandidates) { probe in
            partialHashes[probe.url] ?? UUID().uuidString
        }.values.filter { $0.count > 1 }
        let fullCandidates = partialGroups.flatMap { $0 }
        let fullHashes = await hashes(for: fullCandidates, mode: .full)
        let fullGroups = Dictionary(grouping: fullCandidates) { probe in
            fullHashes[probe.url] ?? UUID().uuidString
        }

        return fullGroups.compactMap { fingerprint, probes in
            let uniquePhysicalFiles = deduplicatingHardLinks(probes)
            guard uniquePhysicalFiles.count > 1 else { return nil }
            return DuplicateGroup(
                fingerprint: fingerprint,
                files: uniquePhysicalFiles.map {
                    DuplicateFileRecord(url: $0.url, size: $0.size, modifiedAt: $0.modifiedAt)
                }.sorted { $0.url.path < $1.url.path }
            )
        }.sorted { $0.reclaimableSize > $1.reclaimableSize }
    }

    func verifiedCleanupCandidates(
        groups: [DuplicateGroup],
        selectedPaths: Set<String>
    ) async -> [CleanupCandidate] {
        var candidates: [CleanupCandidate] = []
        for group in groups {
            let existing = group.files.filter { fileSystem.exists($0.url) }
            let probes = existing.map {
                FileProbe(url: $0.url, size: $0.size, modifiedAt: $0.modifiedAt, resourceIdentifier: $0.url.path)
            }
            let currentHashes = await hashes(for: probes, mode: .full)
            let keeperHashes: Set<String> = Set(existing.compactMap { file -> String? in
                guard !selectedPaths.contains(file.id) else { return nil }
                return currentHashes[file.url]
            })
            for file in existing where selectedPaths.contains(file.id) {
                guard let hash = currentHashes[file.url], keeperHashes.contains(hash) else { continue }
                let allocatedSize = fileSystem.allocatedSize(of: file.url)
                candidates.append(CleanupCandidate(
                    id: file.id,
                    name: file.name,
                    detail: "Verified duplicate with an unselected identical copy.",
                    path: file.url.path,
                    category: .appData,
                    safety: .review,
                    strategy: .trash(file.url),
                    size: allocatedSize,
                    modifiedAt: fileSystem.modificationDate(of: file.url)
                ))
            }
        }
        return candidates
    }

    private func discoverFiles(minimumSize: Int64) -> [FileProbe] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        var probesByPath: [String: FileProbe] = [:]
        let fileManager = FileManager.default

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true else { continue }
                if values.isUbiquitousItem == true,
                   values.ubiquitousItemDownloadingStatus != .current {
                    continue
                }
                let size = Int64(values.fileSize ?? 0)
                guard size >= minimumSize else { continue }
                probesByPath[url.path] = FileProbe(
                    url: url,
                    size: size,
                    modifiedAt: values.contentModificationDate,
                    resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) } ?? url.path
                )
            }
        }
        return Array(probesByPath.values)
    }

    private func hashes(for probes: [FileProbe], mode: HashMode) async -> [URL: String] {
        await withTaskGroup(of: (URL, String?).self, returning: [URL: String].self) { group in
            var iterator = probes.makeIterator()
            var results: [URL: String] = [:]
            for _ in 0..<min(maximumConcurrentHashes, probes.count) {
                if let probe = iterator.next() {
                    group.addTask { (probe.url, Self.hash(probe.url, mode: mode)) }
                }
            }
            while let (url, digest) = await group.next() {
                if let digest { results[url] = digest }
                if let probe = iterator.next() {
                    group.addTask { (probe.url, Self.hash(probe.url, mode: mode)) }
                }
            }
            return results
        }
    }

    private func deduplicatingHardLinks(_ probes: [FileProbe]) -> [FileProbe] {
        var seen: Set<String> = []
        return probes.filter { seen.insert($0.resourceIdentifier).inserted }
    }

    private static func hash(_ url: URL, mode: HashMode) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            switch mode {
            case .partial:
                let chunkSize = 64 * 1_024
                let first = try handle.read(upToCount: chunkSize) ?? Data()
                hasher.update(data: first)
                let end = try handle.seekToEnd()
                if end > UInt64(chunkSize) {
                    try handle.seek(toOffset: end - UInt64(chunkSize))
                    hasher.update(data: try handle.read(upToCount: chunkSize) ?? Data())
                }
            case .full:
                while true {
                    let data = try handle.read(upToCount: 1_048_576) ?? Data()
                    guard !data.isEmpty else { break }
                    hasher.update(data: data)
                }
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}

private struct FileProbe: Sendable {
    let url: URL
    let size: Int64
    let modifiedAt: Date?
    let resourceIdentifier: String
}

private enum HashMode: Sendable {
    case partial
    case full
}
