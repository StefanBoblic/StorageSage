//
//  ScanResultCache.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol ScanResultCaching: Sendable {
    func load(maxAge: TimeInterval) -> ScanResult?
    func save(_ result: ScanResult)
}

struct DiskScanResultCache: ScanResultCaching {
    private let cacheFileURL: URL?

    init(cacheFileURL: URL? = nil) {
        self.cacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL()
    }

    func load(maxAge: TimeInterval) -> ScanResult? {
        guard
            let cacheFileURL,
            let data = try? Data(contentsOf: cacheFileURL),
            let cached = try? JSONDecoder().decode(CachedScanResult.self, from: data),
            Date().timeIntervalSince(cached.scannedAt) <= maxAge
        else { return nil }
        return cached.scanResult
    }

    func save(_ result: ScanResult) {
        guard let cacheFileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(CachedScanResult(result))
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            // Cache failures must never prevent a live scan.
        }
    }

    private static func defaultCacheFileURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StorageSage", isDirectory: true)
            .appendingPathComponent("overview-scan.json", isDirectory: false)
    }
}

private struct CachedScanResult: Codable {
    let candidates: [CachedCandidate]
    let volumeTotal: Int64
    let volumeAvailable: Int64
    let inaccessiblePaths: [String]
    let scannedAt: Date

    init(_ result: ScanResult) {
        candidates = result.candidates.map(CachedCandidate.init)
        volumeTotal = result.volume.total
        volumeAvailable = result.volume.available
        inaccessiblePaths = result.inaccessiblePaths
        scannedAt = result.scannedAt
    }

    var scanResult: ScanResult {
        ScanResult(
            candidates: candidates.map(\.cleanupCandidate),
            volume: VolumeSnapshot(total: volumeTotal, available: volumeAvailable),
            inaccessiblePaths: inaccessiblePaths,
            scannedAt: scannedAt
        )
    }
}

private struct CachedCandidate: Codable {
    enum Strategy: String, Codable {
        case trash
        case trashReviewedFile
        case trashReviewedDirectory
        case deleteUnavailableSimulators
        case none
    }

    let id: String
    let name: String
    let detail: String
    let path: String
    let category: StorageCategory
    let safety: SafetyLevel
    let strategy: Strategy
    let size: Int64
    let modifiedAt: Date?

    init(_ candidate: CleanupCandidate) {
        id = candidate.id
        name = candidate.name
        detail = candidate.detail
        path = candidate.path
        category = candidate.category
        safety = candidate.safety
        size = candidate.size
        modifiedAt = candidate.modifiedAt
        switch candidate.strategy {
        case .trash: strategy = .trash
        case .trashReviewedFile: strategy = .trashReviewedFile
        case .trashReviewedDirectory: strategy = .trashReviewedDirectory
        case .deleteUnavailableSimulators: strategy = .deleteUnavailableSimulators
        case .none: strategy = .none
        }
    }

    var cleanupCandidate: CleanupCandidate {
        let cleanupStrategy: CleanupStrategy
        switch strategy {
        case .trash: cleanupStrategy = .trash(URL(fileURLWithPath: path))
        case .trashReviewedFile: cleanupStrategy = .trashReviewedFile(URL(fileURLWithPath: path))
        case .trashReviewedDirectory: cleanupStrategy = .trashReviewedDirectory(URL(fileURLWithPath: path))
        case .deleteUnavailableSimulators: cleanupStrategy = .deleteUnavailableSimulators
        case .none: cleanupStrategy = .none
        }
        return CleanupCandidate(
            id: id,
            name: name,
            detail: detail,
            path: path,
            category: category,
            safety: safety,
            strategy: cleanupStrategy,
            size: size,
            modifiedAt: modifiedAt
        )
    }
}
