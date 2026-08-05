//
//  StorageScanner.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol StorageScanning: Sendable {
    func scan() -> ScanResult
}

struct StorageScanner: StorageScanning {
    private let targetProvider: any ScanTargetProviding
    private let analyzers: [any StorageAnalyzing]
    private let fileSystem: any FileSystemInspecting
    private let nameProvider: any CandidateNameProviding

    init(
        targetProvider: any ScanTargetProviding = DefaultScanTargetProvider(),
        analyzers: [any StorageAnalyzing] = [SimulatorStorageAnalyzer()],
        fileSystem: any FileSystemInspecting = FileSystemInspector(),
        nameProvider: any CandidateNameProviding = CandidateNameProvider()
    ) {
        self.targetProvider = targetProvider
        self.analyzers = analyzers
        self.fileSystem = fileSystem
        self.nameProvider = nameProvider
    }

    func scan() -> ScanResult {
        var candidates: [CleanupCandidate] = analyzers.flatMap { $0.analyze() }
        var inaccessible: [String] = []

        for target in targetProvider.targets() {
            switch target.mode {
            case .item:
                if let candidate = candidate(for: target) {
                    candidates.append(candidate)
                }
            case .children(let minimumSize):
                addChildren(
                    of: target,
                    minimumSize: minimumSize,
                    to: &candidates,
                    inaccessible: &inaccessible
                )
            }
        }

        for url in targetProvider.protectedURLs()
        where fileSystem.exists(url) && !fileSystem.isReadable(url) {
            inaccessible.append(url.path)
        }

        candidates.sort { $0.size > $1.size }
        return ScanResult(
            candidates: candidates,
            volume: volumeSnapshot(),
            inaccessiblePaths: Array(Set(inaccessible)).sorted(),
            scannedAt: Date()
        )
    }

    private func addChildren(
        of target: ScanTarget,
        minimumSize: Int64,
        to candidates: inout [CleanupCandidate],
        inaccessible: inout [String]
    ) {
        guard let children = try? fileSystem.children(of: target.url) else {
            if fileSystem.exists(target.url) { inaccessible.append(target.url.path) }
            return
        }

        for child in children {
            let size = fileSystem.allocatedSize(of: child)
            guard size >= minimumSize else { continue }

            candidates.append(CleanupCandidate(
                id: child.path,
                name: nameProvider.displayName(for: child),
                detail: target.detail,
                path: child.path,
                category: target.category,
                safety: target.safety,
                strategy: target.safety == .analysisOnly ? .none : .trash(child),
                size: size,
                modifiedAt: fileSystem.modificationDate(of: child)
            ))
        }
    }

    private func candidate(for target: ScanTarget) -> CleanupCandidate? {
        guard fileSystem.exists(target.url) else { return nil }
        let size = fileSystem.allocatedSize(of: target.url)
        guard size > 0 else { return nil }

        return CleanupCandidate(
            id: target.url.path,
            name: target.name ?? nameProvider.displayName(for: target.url),
            detail: target.detail,
            path: target.url.path,
            category: target.category,
            safety: target.safety,
            strategy: target.safety == .analysisOnly ? .none : .trash(target.url),
            size: size,
            modifiedAt: fileSystem.modificationDate(of: target.url)
        )
    }

    private func volumeSnapshot() -> VolumeSnapshot {
        let volumeURL = FileManager.default.homeDirectoryForCurrentUser
        let values = try? volumeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        return VolumeSnapshot(
            total: Int64(values?.volumeTotalCapacity ?? 0),
            available: Int64(values?.volumeAvailableCapacity ?? 0)
        )
    }
}
