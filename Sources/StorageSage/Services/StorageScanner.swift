//
//  StorageScanner.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol StorageScanning: Sendable {
    func scan() async -> ScanResult
}

struct StorageScanner: StorageScanning {
    private let targetProvider: any ScanTargetProviding
    private let analyzers: [any StorageAnalyzing]
    private let fileSystem: any FileSystemInspecting
    private let nameProvider: any CandidateNameProviding
    private let configuration: any ScanConfigurationProviding

    init(
        targetProvider: any ScanTargetProviding = DefaultScanTargetProvider(),
        analyzers: [any StorageAnalyzing] = [SimulatorStorageAnalyzer()],
        fileSystem: any FileSystemInspecting = FileSystemInspector(),
        nameProvider: any CandidateNameProviding = CandidateNameProvider(),
        configuration: any ScanConfigurationProviding = UserDefaultsScanConfiguration()
    ) {
        self.targetProvider = targetProvider
        self.analyzers = analyzers
        self.fileSystem = fileSystem
        self.nameProvider = nameProvider
        self.configuration = configuration
    }

    func scan() async -> ScanResult {
        async let targetResult = scanTargets(targetProvider.targets())
        async let analyzerCandidates = runAnalyzers()
        let (scanned, analyzed) = await (targetResult, analyzerCandidates)

        var candidates = analyzed + scanned.candidates
        var inaccessible = scanned.inaccessiblePaths

        for url in targetProvider.protectedURLs()
        where fileSystem.exists(url) && !fileSystem.isReadable(url) {
            inaccessible.append(url.path)
        }

        candidates = candidates.reduce(into: [String: CleanupCandidate]()) { unique, candidate in
            if unique[candidate.id] == nil { unique[candidate.id] = candidate }
        }.map(\.value).sorted { $0.size > $1.size }
        return ScanResult(
            candidates: candidates,
            volume: volumeSnapshot(),
            inaccessiblePaths: Array(Set(inaccessible)).sorted(),
            scannedAt: Date()
        )
    }

    private func scanTargets(_ targets: [ScanTarget]) async -> TargetScanResult {
        let prepared = prepareJobs(for: targets)
        let limit = max(configuration.maximumConcurrentTasks, 1)
        let batchSize = min(max((prepared.jobs.count + (limit * 2) - 1) / (limit * 2), 1), 32)
        let batches = stride(from: 0, to: prepared.jobs.count, by: batchSize).map {
            Array(prepared.jobs[$0..<min($0 + batchSize, prepared.jobs.count)])
        }
        let scannedCandidates = await withTaskGroup(of: [CleanupCandidate].self, returning: [CleanupCandidate].self) { group in
            var iterator = batches.makeIterator()
            var results: [CleanupCandidate] = []

            for _ in 0..<min(limit, batches.count) {
                if let batch = iterator.next() {
                    group.addTask { candidates(for: batch) }
                }
            }

            while let batchResults = await group.next() {
                results.append(contentsOf: batchResults)
                if let batch = iterator.next() {
                    group.addTask { candidates(for: batch) }
                }
            }
            return results
        }
        return TargetScanResult(
            candidates: scannedCandidates,
            inaccessiblePaths: prepared.inaccessiblePaths
        )
    }

    private func runAnalyzers() async -> [CleanupCandidate] {
        await withTaskGroup(of: [CleanupCandidate].self, returning: [CleanupCandidate].self) { group in
            for analyzer in analyzers {
                group.addTask { analyzer.analyze() }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }
    }

    private func prepareJobs(for targets: [ScanTarget]) -> PreparedScanJobs {
        var jobs: [ScanJob] = []
        var inaccessiblePaths: [String] = []

        for target in targets {
            switch target.mode {
            case .item:
                jobs.append(.item(target))
            case .children(let minimumSize):
                guard let children = try? fileSystem.children(of: target.url) else {
                    if fileSystem.exists(target.url) { inaccessiblePaths.append(target.url.path) }
                    continue
                }
                jobs.append(contentsOf: children.map { .child($0, parent: target, minimumSize: minimumSize) })
            }
        }
        return PreparedScanJobs(jobs: jobs, inaccessiblePaths: inaccessiblePaths)
    }

    private func candidates(for jobs: [ScanJob]) -> [CleanupCandidate] {
        let sizes = fileSystem.allocatedSizes(of: jobs.map(\.url))
        return jobs.compactMap { candidate(for: $0, size: sizes[$0.url] ?? 0) }
    }

    private func candidate(for job: ScanJob, size: Int64) -> CleanupCandidate? {
        switch job {
        case .item(let target):
            return candidate(for: target, size: size)
        case .child(let child, let target, let minimumSize):
            guard size >= minimumSize else { return nil }
            return CleanupCandidate(
                id: child.path,
                name: nameProvider.displayName(for: child),
                detail: target.detail,
                path: child.path,
                category: target.category,
                safety: target.safety,
                strategy: target.safety == .analysisOnly ? .none : .trash(child),
                size: size,
                modifiedAt: fileSystem.modificationDate(of: child)
            )
        }
    }

    private func candidate(for target: ScanTarget, size: Int64) -> CleanupCandidate? {
        guard fileSystem.exists(target.url) else { return nil }
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

private struct TargetScanResult: Sendable {
    var candidates: [CleanupCandidate]
    var inaccessiblePaths: [String] = []
}

private struct PreparedScanJobs: Sendable {
    let jobs: [ScanJob]
    let inaccessiblePaths: [String]
}

private enum ScanJob: Sendable {
    case item(ScanTarget)
    case child(URL, parent: ScanTarget, minimumSize: Int64)

    var url: URL {
        switch self {
        case .item(let target): return target.url
        case .child(let url, _, _): return url
        }
    }
}
